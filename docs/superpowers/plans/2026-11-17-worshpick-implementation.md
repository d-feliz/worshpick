# Worshpick — Plan de implementación

- **Fecha:** 2026-11-17
- **Spec:** [2026-11-16-worshpick-design.md](../specs/2026-11-16-worshpick-design.md)
- **Objetivo:** construir la v1 descrita en el spec: importar videos de letras, analizarlos con `claude -p`, buscar sin IA, sugerir canciones y arrastrar el setlist a Proclaim.

## Cómo usar este plan

- Las tareas van en orden. Cada tarea termina con las pruebas en verde y **un commit**.
- **TDD:** primero escribir la prueba que falla, después el código mínimo que la pasa, después limpiar.
- Las tareas marcadas **[manual]** no tienen prueba automática. Su criterio de terminado es una verificación a mano.
- Comandos de prueba:
  - Núcleo (rápido): `swift test --package-path Packages/WorshpickCore`
  - App completa: `scripts/test.sh` (genera el proyecto con XcodeGen y corre `xcodebuild test`)

## Herramientas

| Herramienta | Versión en este Mac | Uso |
|---|---|---|
| Xcode | 26.0 | Compilar la app. |
| Swift | 6.2 | Lenguaje. Modo de concurrencia estricto. |
| XcodeGen | Homebrew | Genera `Worshpick.xcodeproj` desde `project.yml`. El `.xcodeproj` no se guarda en git. |
| ffmpeg | Homebrew | Solo para generar los videos de prueba (`scripts/make-test-videos.sh`). La app no lo usa. |
| GRDB | 7.x (SwiftPM) | SQLite + FTS5. |
| `claude` CLI | 2.1.x | Análisis y sugerencias. |

## Estructura del código

El spec (§3) describe las carpetas. El plan las reparte en dos lugares para que las pruebas de la lógica corran con `swift test` en segundos, sin abrir la app:

```
worshpick/
├── project.yml                         XcodeGen: target Worshpick (macOS 15) + paquete local
├── Worshpick/                          target de la app (solo interfaz)
│   ├── App/WorshpickApp.swift
│   ├── App/AppEnvironment.swift        crea y conecta los stores y servicios
│   ├── Components/                     vistas sin estado
│   ├── Containers/                     vistas con estado
│   └── Assets/Assets.xcassets
├── Packages/WorshpickCore/             paquete Swift local (toda la lógica)
│   ├── Package.swift
│   ├── Sources/WorshpickCore/
│   │   ├── Models/
│   │   ├── Constants/
│   │   ├── Helpers/
│   │   ├── Stores/
│   │   └── Services/
│   └── Tests/WorshpickCoreTests/
│       └── Fixtures/                   catálogo JSON, videos, respuestas del CLI
├── scripts/
│   ├── generate-project.sh
│   ├── test.sh
│   └── make-test-videos.sh
└── docs/superpowers/{specs,plans}/
```

---

## Fase 0 — Base del proyecto

### T0.1 Esqueleto del proyecto

**Archivos:** `project.yml`, `Packages/WorshpickCore/Package.swift`, `Worshpick/App/WorshpickApp.swift`, `scripts/generate-project.sh`, `scripts/test.sh`, `.gitignore`.

- `Package.swift`: plataforma `.macOS(.v15)`, dependencia `GRDB.swift` `from: "7.0.0"`, target `WorshpickCore`, target de pruebas `WorshpickCoreTests` con `resources: [.copy("Fixtures")]`.
- `project.yml`:

  ```yaml
  name: Worshpick
  options:
    deploymentTarget: { macOS: "15.0" }
  packages:
    WorshpickCore: { path: Packages/WorshpickCore }
  targets:
    Worshpick:
      type: application
      platform: macOS
      sources: [Worshpick]
      dependencies: [{ package: WorshpickCore }]
      settings:
        base:
          PRODUCT_BUNDLE_IDENTIFIER: com.dfeliz.worshpick
          SWIFT_VERSION: "6.0"
          ENABLE_HARDENED_RUNTIME: YES
  ```

- La app **no** usa App Sandbox: necesita ejecutar el binario `claude` del usuario. Esto queda anotado en `project.yml` con un comentario de una línea.
- `.gitignore`: `*.xcodeproj`, `.build/`, `DerivedData/`, `.swiftpm/`, `xcuserdata/`.
- `WorshpickApp.swift`: ventana vacía con el título "Worshpick".

**Terminado cuando:** `swift test --package-path Packages/WorshpickCore` pasa con una prueba vacía, y `scripts/test.sh` compila la app.

### T0.2 Capturar respuestas reales del CLI [spike]

Es una exploración. Solo se guardan los fixtures, no el código.

1. Confirmar que hay sesión: `claude -p "hola"`. Si falla, el usuario ejecuta `claude` y vuelve a iniciar sesión.
2. Guardar en `Tests/WorshpickCoreTests/Fixtures/claude-cli/`:
   - `success-structured.json` — salida de `claude -p --output-format json --no-session-persistence --tools "" --json-schema '<schema pequeño>' "..."`. Anotar en qué campo llega el objeto estructurado (probablemente `structured_output`).
   - `auth-error.json` — salida con la sesión caducada (`is_error: true`, `result: "Failed to authenticate: ..."`).
   - `usage-limit.json` — si es posible reproducirlo. Si no, construirlo a mano a partir de la documentación del CLI y anotarlo en el nombre: `usage-limit.handmade.json`.

**Terminado cuando:** los fixtures están en git y la tarea T2.5 puede probar con ellos.

---

## Fase 1 — Datos y búsqueda (sin IA)

Al final de esta fase, la búsqueda funciona completa con un catálogo de prueba.

### T1.1 Modelos

**Archivos:** `Models/Song.swift`, `Models/Passage.swift`, `Models/Setlist.swift`, `Models/SongEnums.swift`.

- `Song` con todos los campos del spec §4, más `ocrText: String?` (texto OCR guardado para "Reanalizar", spec §5).
- Enums: `SongStatus` (`pending, extracting, analyzing, ready, failed`) + `failureReason: String?`; `Energy`; `SongLanguage`; `PassageKind`; `OCREngineKind`; `SetlistStatus`.
- `invitations`, `themes`, `keywords`, `moments`, `manuallyEditedFields` se guardan como JSON en una columna.
- `Passage`: `songId, bookId, kind, startPosition, endPosition`. Una posición es `chapter * 1000 + verse`. "Romanos 8" = `8001…8999`. Así un solo `BETWEEN` resuelve capítulos completos, versículos y rangos entre capítulos.
- `Setlist`, `SetlistItem` según el spec §4.

**Pruebas:** ida y vuelta Codable de cada modelo. Cálculo de `startPosition`/`endPosition` para "8", "8:28", "8:28-39" y "8:38-9:2".

### T1.2 Constantes

**Archivos:** `Constants/BibleBooks.swift`, `Constants/DefaultVocabularies.swift`.

- `BibleBooks`: los 66 libros con `id` (1–66), nombre en español, nombre en inglés y abreviaturas comunes en los dos idiomas (Gn/Gen/Génesis/Genesis, Sal/Salmo/Salmos/Ps/Psalm/Psalms, 1 Co/1Co/1 Cor/1 Corintios/1 Corinthians...). Las claves se normalizan: minúsculas, sin tildes, sin puntos, sin espacios.
- `DefaultVocabularies`: invitaciones, momentos y la plantilla de servicio "Domingo normal" del spec §7.

**Pruebas:** hay 66 libros; ninguna clave normalizada apunta a dos libros distintos.

### T1.3 `BibleReferenceParser`

**Archivo:** `Helpers/BibleReferenceParser.swift`

```swift
struct BibleReference: Equatable { let bookId: Int; let startPosition: Int; let endPosition: Int }
struct ParsedReferences { let references: [BibleReference]; let remainingText: String }
enum BibleReferenceParser { static func parse(_ text: String) -> ParsedReferences }
```

**Pruebas (tabla):**

| Entrada | Esperado |
|---|---|
| `Sal 23` | Salmos 23001–23999 |
| `salmo 23:1-3` | Salmos 23001–23003 |
| `Isaías 40:31` | Isaías 40031–40031 |
| `isaias 40.31` | igual |
| `Rom 8:38-9:2` | Romanos 8038–9002 |
| `1 Co 13` / `1Co 13` / `1 Corinthians 13` | 1 Corintios 13001–13999 |
| `Romans 8 gracia` | Romanos 8 + `remainingText = "gracia"` |
| `salmo` (sin capítulo) | sin referencia; `remainingText = "salmo"` |
| `Juan 99` | se acepta (no se valida el número de capítulos en v1) |

### T1.4 `CatalogStore`

**Archivos:** `Stores/CatalogStore.swift`, `Stores/CatalogMigrations.swift`.

- `DatabaseQueue` de GRDB en `~/Library/Application Support/Worshpick/catalog.sqlite` (las pruebas usan una base en memoria).
- Migración v1: tablas `song`, `passage`, `setlist`, `setlistItem`, y la tabla FTS5:

  ```sql
  CREATE VIRTUAL TABLE songSearch USING fts5(
    title, artist, keywords, themes, summary, lyrics,
    tokenize = 'unicode61 remove_diacritics 2',
    prefix = '2 3'
  );
  ```

  `songSearch.rowid` = `song.rowid`. El orden de las columnas define los pesos de BM25 en T1.6.
- API: `insertPendingSong`, `saveAnalyzedSong(_:passages:)`, `updateStatus`, `song(id:)`, `allSongs`, `existingThemes()`, `songExists(fileHash:)`, `saveManualEdit(songId:field:value:)`.
- `saveAnalyzedSong` respeta `manuallyEditedFields`: un campo editado a mano conserva su valor. Reescribe la fila de `songSearch` en la misma transacción.

**Pruebas:** guardar y leer; el índice FTS se actualiza al guardar; un reanálisis no cambia los campos editados a mano; `existingThemes` no devuelve duplicados.

### T1.5 `SearchQueryParser`

**Archivo:** `Helpers/SearchQueryParser.swift`

```swift
struct SearchQuery {
  var freeText: [String]          // términos sueltos → prefijo
  var exactPhrases: [String]      // "entre comillas"
  var authorTerms: [String]       // autor:
  var lyricsTerms: [String]       // letra:
  var themeTerms: [String]        // tema:
  var invitationTags: [String]    // #esperanza
  var references: [BibleReference]
}
```

Primero extrae las comillas y los prefijos. Después pasa el resto por `BibleReferenceParser`. Lo que queda es `freeText`.

**Pruebas:** cada prefijo solo; combinaciones; comillas sin cerrar (se tratan como texto); consulta vacía.

### T1.6 `SearchService`

**Archivos:** `Services/SearchService.swift`, `Models/SearchFilters.swift`, `Models/SearchResult.swift`.

```swift
struct SearchFilters { var invitations, themes, moments: Set<String>; var energies: Set<Energy>
                       var languages: Set<SongLanguage>; var notUsedInLastSundays: Int?; var needsReviewOnly: Bool }
struct SearchResult { let song: Song; let matchReason: MatchReason; let lastUsedDate: Date? }
enum MatchReason { case lyricsSnippet(String), passage(BibleReference), theme(String), title, artist, keyword(String), filtersOnly }
```

- Convierte `SearchQuery` en una expresión FTS5 `MATCH`: `freeText` → `term*`; frases → `"…"`; `autor:` → `artist : term*`; `letra:` → `lyrics : term*`; `tema:` → `themes : term*`.
- Orden: `bm25(songSearch, 10.0, 6.0, 4.0, 4.0, 3.0, 2.0)` (título, artista, keywords, temas, resumen, letra).
- Fragmento resaltado: `snippet(songSearch, 5, '⟦', '⟧', '…', 12)`. La vista convierte las marcas en negrita.
- Referencias: `EXISTS (SELECT 1 FROM passage p WHERE p.songId = song.id AND p.bookId = ? AND p.startPosition <= :queryEnd AND p.endPosition >= :queryStart)`.
- Filtros: los valores de un filtro se combinan con O; filtros distintos, con Y (spec §6). `#tag` se suma al filtro de invitaciones.
- Consulta vacía y sin filtros → todas las canciones `ready`, por título.
- `matchReason`: pasaje si hubo referencia; si no, la columna con coincidencia de más peso.

**Fixture:** `Fixtures/catalog-sample.json` con unas 15 canciones reales o inventadas, que cubren español, inglés, tildes, pasajes y todas las invitaciones.

**Pruebas:**
- "corazon" encuentra "corazón"; "gra" encuentra "gracia".
- Si un término está en el título de A y en la letra de B, A sale primero.
- "perdón" encuentra una canción que solo lo tiene en `keywords`.
- "Romanos 8" encuentra una canción con Romanos 8:38-39 y no una con Romanos 12.
- Los filtros combinan O dentro de un filtro e Y entre filtros.
- `matchReason` correcto en cada caso.
- **Rendimiento:** 5.000 canciones sintéticas; la consulta de 3 términos con 2 filtros tarda menos de 50 ms (mediana de 20 ejecuciones).

### T1.7 `SetlistStore` e historial de uso

**Archivo:** `Stores/SetlistStore.swift`

- CRUD de setlists e items; reordenar; `markAsUsed(setlistId:)`.
- `lastUsedDateBySongId() -> [UUID: Date]` sale de los setlists `used`.
- `songIdsUsedInLastSundays(_ count: Int, relativeTo today: Date) -> Set<UUID>`: incluye las canciones con `serviceDate >= today - count × 7 días`.
- `SearchService` usa esta función para el filtro "No usada en N domingos" y para "cantada hace X semanas".

**Pruebas:** límites exactos de la ventana de días; un setlist en borrador no cuenta como uso.

---

## Fase 2 — Importación con IA

### T2.1 `LibraryService`

**Archivo:** `Services/LibraryService.swift`

- `importVideo(at sourceURL: URL) async throws -> ImportOutcome` (`.imported(Song)`, `.duplicate(existing: Song)`).
- Pasos: SHA-256 en streaming (`CryptoKit`, bloques de 1 MB) → `songExists(fileHash:)` → copia a `Videos/<uuid>/<nombre original>` → duración con `AVURLAsset` → `insertPendingSong`.
- Extensiones aceptadas: `mp4`, `mov`, `m4v`. Las demás → `ImportError.unsupportedFileType`.
- Si la copia falla (p. ej. disco lleno), se borra la carpeta `<uuid>` y no se crea la canción (spec §10).

**Pruebas:** importa un video de prueba; un segundo import del mismo archivo devuelve `.duplicate`; una extensión no aceptada da error; ante un error de copia simulado (un `FileCopier` falso) no queda ni carpeta ni canción.

### T2.2 Videos de prueba

**Archivo:** `scripts/make-test-videos.sh` → `Fixtures/videos/`.

Un script Swift (`scripts/render-lyric-screens.swift`) dibuja las pantallas en PNG y ffmpeg las une en 3 videos (el ffmpeg de Homebrew no trae `drawtext`): cortos (10–15 s, 640×360, H.264, sin audio), cada uno con 3–4 pantallas de letra con `drawtext`:
- `cancion-es.mp4` — letra en español con tildes y ñ.
- `song-en.mp4` — letra en inglés.
- `sin-texto.mp4` — solo color de fondo (para el caso "Vision no encuentra texto").

Los videos se guardan en git (pesan pocos KB) para que las pruebas no dependan de ffmpeg.

### T2.3 `ScreenFingerprint` y `FrameSampler`

**Archivos:** `Helpers/ScreenFingerprint.swift`, `Services/FrameSampler.swift`.

- `ScreenFingerprint(of: CGImage)` (miniatura 64×36 en escala de grises) y `difference(from:) -> Double` (diferencia media por píxel). *Cambio durante la implementación:* un dHash 9×8 no distinguía pantallas de letra con el mismo fondo.
- `FrameSampler.sampleFrames(from: URL, interval: TimeInterval = 1.5, maximumFrameCount: Int = 120) async throws -> [SampledFrame]` con `AVAssetImageGenerator.images(for:)`. Reduce cada fotograma a 1280 px de ancho. Descarta un fotograma si su diferencia con el último fotograma guardado es ≤ 1,0 (entre pantallas distintas se mide ~2–3).
- `SampledFrame { timestamp, image: CGImage }`.

**Pruebas:** dos imágenes iguales → diferencia 0; pantallas distintas → diferencia > 1,0; `cancion-es.mp4` devuelve tantos fotogramas como pantallas tiene (±1); nunca más de `maximumFrameCount`.

### T2.4 `OCREngine` y `VisionOCR`

**Archivos:** `Services/OCR/OCREngine.swift`, `Services/OCR/VisionOCR.swift`, `Services/OCR/OCRTextBlocks.swift`.

```swift
struct OCRTextBlock: Codable { let timestamp: TimeInterval; let text: String; let confidence: Double }
protocol OCREngine: Sendable { func recognizeText(in frames: [SampledFrame]) async throws -> [OCRTextBlock] }
```

- `VisionOCR`: `RecognizeTextRequest` (Vision para Swift, macOS 15), nivel preciso, idiomas `["es-ES", "en-US"]`, corrección de idioma activada. Une las líneas de un fotograma en un bloque, de arriba abajo.
- `OCRTextBlocks.mergeConsecutiveDuplicates` une bloques seguidos con el mismo texto normalizado.
- `averageConfidence` → `Song.ocrConfidence`. Si es < 0,6 o no hay texto, la canción queda en "Revisar".

**Pruebas:** `cancion-es.mp4` contiene las líneas esperadas (comparación sin tildes ni mayúsculas, ≥ 90 % de las palabras); `sin-texto.mp4` devuelve 0 bloques; la unión de duplicados funciona.

### T2.5 `ClaudeCLI`

**Archivos:** `Services/Claude/ClaudeRunning.swift`, `Services/Claude/ProcessClaudeRunner.swift`, `Services/Claude/ClaudeBinaryLocator.swift`, `Services/Claude/ClaudeResultEnvelope.swift`, `Tests/.../FakeClaudeRunner.swift`.

```swift
struct ClaudeRequest { let prompt: String; let jsonSchema: String; let model: String
                       let allowedTools: [String]; let readableDirectories: [URL]; let timeout: Duration }
protocol ClaudeRunning: Sendable { func run(_ request: ClaudeRequest) async throws -> Data /* objeto estructurado */ }
enum ClaudeError: Error { case notInstalled, notLoggedIn(message: String), usageLimitReached(message: String),
                          timedOut, invalidOutput(details: String), failed(message: String) }
```

- Argumentos: `-p <prompt> --output-format json --no-session-persistence --model <model> --json-schema <schema> --tools <lista o "">`. Si hay directorios: `--add-dir <dir>`. El prompt va por stdin si supera 100 KB.
- `ClaudeBinaryLocator`: ruta de Ajustes → `~/.local/bin/claude` → `/opt/homebrew/bin/claude` → `/usr/local/bin/claude` → `zsh -lc 'command -v claude'`. Una app abierta desde Finder no hereda el `PATH` de la terminal; por eso la búsqueda es explícita.
- `ClaudeResultEnvelope` decodifica la salida JSON del CLI (formato tomado de los fixtures de T0.2). `is_error` + texto "authenticate" → `notLoggedIn`; texto de límite de uso → `usageLimitReached`; otro error → `failed`.
- Timeout (por defecto 3 minutos, spec §10): termina el proceso y lanza `timedOut`.
- `FakeClaudeRunner`: devuelve respuestas fijas por orden y guarda las peticiones recibidas.

**Pruebas:** el decodificador con cada fixture de T0.2; la construcción de argumentos; el localizador con un sistema de archivos falso; el timeout con un ejecutable de prueba (`/bin/sleep`).

### T2.6 JSON schemas y prompts

**Archivos:** `Constants/ClaudeSchemas.swift`, `Constants/ClaudePrompts.swift`, `Models/SongAnalysisResponse.swift`, `Models/OCRResponse.swift`, `Models/SuggestionResponse.swift`.

- `songAnalysisSchema`: `title, artist, language, lyrics, summary, keywords[10..20], invitations[1..3] (enum = vocabulario actual), themes[2..5], moments[1..2] (enum), energy (enum), passages[{ book, chapter, verseStart?, verseEnd?, chapterEnd?, kind }]`. El schema se construye en tiempo de ejecución porque los vocabularios son editables.
- `ocrSchema`: `blocks[{ frameIndex, text }]`.
- `suggestionSchema`: `slots[{ slotIndex, songId, reason, alternativeSongIds[0..2] }]`.
- Los prompts están en español y piden: letra sin repeticiones de pantalla, estrofas separadas por una línea en blanco, reutilizar temas existentes, `keywords` solo con conceptos que **no** están en la letra, pasajes solo si la alusión es clara.
- Cada respuesta tiene un `Decodable` y una validación: los valores de los enums deben existir en el vocabulario.

**Pruebas:** cada schema es JSON válido; una respuesta de ejemplo decodifica; una respuesta con una invitación fuera del vocabulario no pasa la validación.

### T2.7 `SongAnalyzer`

**Archivo:** `Services/SongAnalyzer.swift`

- `analyze(song:ocrText:vocabularies:existingThemes:) async throws -> AnalyzedSong` (campos + passages).
- Convierte cada `passage.book` en `bookId` con `BibleBooks`. Los libros desconocidos se descartan y se registran en el log.
- Si la decodificación o la validación fallan: 1 reintento. El segundo fallo → `ClaudeError.invalidOutput`.

**Pruebas (con `FakeClaudeRunner`):** respuesta válida → `AnalyzedSong` correcto; JSON inválido y después válido → éxito con 2 llamadas; dos inválidos → error; libro desconocido descartado; el prompt incluye los temas existentes.

### T2.8 `ClaudeOCR`

**Archivo:** `Services/OCR/ClaudeOCR.swift`

- Escribe hasta 40 fotogramas (`frame-000.jpg`…, JPEG calidad 0,8) en una carpeta temporal.
- `ClaudeRequest` con `allowedTools: ["Read"]` y `readableDirectories: [carpeta]`. El prompt lista los nombres de archivo en orden.
- Convierte `frameIndex` en `timestamp` y usa `confidence = 1.0`. Borra la carpeta al terminar, también cuando hay error.
- Si hay más de 40 fotogramas, elige 40 repartidos de forma uniforme.

**Pruebas:** con `FakeClaudeRunner`: los archivos existen durante la llamada y no existen después; el reparto uniforme; el mapeo índice → timestamp.

### T2.9 `IngestPipeline`

**Archivo:** `Services/IngestPipeline.swift` (un `actor`).

- Dos etapas en paralelo: **extracción** (FrameSampler + OCR, de una en una) y **análisis** (Claude, concurrencia 1–3 según Ajustes).
- Los cambios de estado se guardan en `CatalogStore` (`pending → extracting → analyzing → ready | failed`). `ocrText` se guarda al terminar la extracción.
- `resumeOnLaunch()`: `extracting` vuelve a `pending`; `analyzing` con `ocrText` continúa en análisis.
- `ClaudeError.notInstalled` / `notLoggedIn` / `usageLimitReached` → la cola se **pausa** (las canciones conservan su estado) y publica `pipelineState = .paused(reason)`. `resume()` la reanuda.
- Otros errores → `failed(reason)` solo para esa canción. `retry(songId:)` la vuelve a poner en la cola.
- `reanalyze(songId:)` → solo el análisis, con el `ocrText` guardado.
- `reprocessWithClaudeOCR(songId:)` → extracción con `ClaudeOCR` + análisis.
- Publica el progreso (`AsyncStream<IngestProgress>`): "Analizando 12 de 40".

**Pruebas (con fakes de OCR y Claude):** ruta feliz para 3 canciones; un fallo de Claude marca solo esa canción; `notLoggedIn` pausa la cola sin marcar `failed`; reanudar al abrir; `reanalyze` no vuelve a ejecutar el OCR; `reprocessWithClaudeOCR` usa el motor Claude; los campos editados a mano se conservan.

---

## Fase 3 — Sugeridor

### T3.1 Ajustes y plantillas

**Archivos:** `Models/AppSettings.swift`, `Models/ServiceTemplate.swift`, `Stores/SettingsStore.swift`.

- `AppSettings` (Codable, guardado como JSON en Application Support): ruta del CLI, modelo de importación (por defecto `sonnet`), modelo de sugerencias (por defecto `sonnet`), motor OCR, intervalo entre fotogramas, concurrencia de Claude, vocabularios, número de canciones por defecto (5), plantillas, "evitar repeticiones" N (por defecto 0 = desactivado).
- `ServiceTemplate { name, slots: [ServiceSlot] }`; `ServiceSlot { label, moment?, invitation?, energy? }`.
- `SettingsStore` es `@Observable`. Si el archivo no existe o está dañado, usa los valores por defecto.

**Pruebas:** ida y vuelta; un archivo dañado da los valores por defecto; las plantillas por defecto están presentes.

### T3.2 `Suggester`

**Archivo:** `Services/Suggester.swift`

- `suggest(serviceDescription:serviceDate:template:songCount:) async throws -> SuggestionDraft`.
- Pasos del spec §7:
  1. Candidatas = canciones `ready` menos las usadas en los últimos N domingos.
  2. Catálogo compacto: una línea JSON por canción con `id, title, artist, language, invitations, themes, passages (texto legible), moments, energy, summary`.
  3. Llamada a Claude con `suggestionSchema` y el modelo de sugerencias.
  4. Validación: descarta ids que no son candidatos y canciones repetidas entre huecos (se queda la primera); filtra las alternativas con las mismas reglas.
  5. Los huecos sin canción válida → `.noSuggestion`.
- Sin plantilla: se crea una plantilla temporal de N huecos sin criterios, con las etiquetas "Canción 1…N".
- `SuggestionDraft` → `SetlistStore.createDraft(from:)`.

**Pruebas (con `FakeClaudeRunner`):** las canciones excluidas no aparecen en el prompt; un id inventado se descarta; un id repetido en dos huecos deja el segundo hueco vacío; las alternativas se filtran; sin plantilla se crean N huecos.

---

## Fase 4 — Interfaz

Las vistas no tienen pruebas unitarias. `scripts/snapshot-ui.sh` (solo Debug) dibuja la ventana a PNG con una biblioteca temporal; no dibuja las superficies Liquid Glass. Cada tarea termina con una verificación a mano en la app, usando el catálogo de prueba (opción de depuración "Cargar catálogo de prueba").

### T4.1 Ventana principal [manual]

**Archivos:** `App/AppEnvironment.swift`, `Containers/MainWindow.swift`, `Containers/SidebarNavigation.swift`.

- `NavigationSplitView`: barra lateral (**Biblioteca**, **Sugerir**, **Setlists**), contenido en el centro y el panel del setlist a la derecha (`.inspector`), siempre visible.
- `AppEnvironment` crea `CatalogStore`, `SetlistStore`, `SettingsStore`, `IngestPipeline`, `SearchService` y `Suggester`, y los pasa por `.environment`.
- Al abrir: `IngestPipeline.resumeOnLaunch()`.

### T4.2 Importación [manual]

**Archivos:** `Containers/ImportDropZone.swift`, `Components/IngestProgressBar.swift`, `Components/ClaudeStatusBanner.swift`.

- Se pueden soltar archivos sobre toda la ventana de Biblioteca, o usar el botón "Importar…" (`fileImporter`, varios archivos).
- Los duplicados y los tipos no aceptados se muestran en un resumen al final ("3 importadas, 1 ya existía").
- Barra de progreso global y estado en cada fila.
- `ClaudeStatusBanner` aparece cuando la cola está en pausa. Muestra el motivo, cómo resolverlo (p. ej. "Abre Terminal y ejecuta `claude` para iniciar sesión") y un botón "Reanudar".

**Verificación:** importar los 3 videos de prueba; ver los estados avanzar; sin sesión de Claude aparece el banner y la cola se pausa.

### T4.3 Búsqueda y detalle [manual]

**Archivos:** `Containers/LibraryScreen.swift`, `Containers/SongDetailPanel.swift`, `Components/SearchFilterChips.swift`, `Components/SongRow.swift`, `Components/MatchReasonLabel.swift`, `Components/LyricsView.swift`, `Components/TagChip.swift`.

- `.searchable` con búsqueda en cada pulsación; las consultas se ejecutan fuera del hilo principal y una consulta nueva cancela la anterior.
- Chips de filtro debajo de la caja: Invitación, Tema, Momento, Energía, Idioma, "No usada en N domingos", "Revisar".
- `SongRow`: título, artista, chips, energía, duración, "cantada hace X semanas", `MatchReasonLabel` con el fragmento resaltado. Si la canción no está `ready`, la fila muestra su estado.
- `SongDetailPanel`: `VideoPlayer` (AVKit), letra completa, metadatos editables (cada edición llama a `saveManualEdit`), menú con Reanalizar / Reprocesar con Claude OCR / Reintentar.
- Si la canción está en "Revisar", el panel muestra un aviso con el botón "Reprocesar con Claude OCR" (spec §10).
- Botón "Añadir al setlist" en la fila y en el detalle; también se puede arrastrar la fila al panel del setlist.

**Verificación:** con el catálogo de prueba, repetir a mano las consultas de T1.6 y comprobar las razones de coincidencia; editar una etiqueta, reanalizar y comprobar que la edición se conserva.

### T4.4 Panel del setlist como carpeta [manual]

**Archivos:** `Containers/SetlistPanel.swift`, `Containers/SetlistFileGrid.swift` (AppKit), `Components/SetlistHeader.swift`.

- *Cambio durante la implementación:* se usa `SetlistFileTable`, un `NSTableView` (lista tipo Finder) en lugar de `NSCollectionView`, porque arrastra varias filas en el orden de las filas.
- `SetlistFileGrid` es un `NSCollectionView` dentro de `NSViewRepresentable`. SwiftUI no permite bien arrastrar **varios** archivos a la vez fuera de la app; `NSCollectionView` sí, y además da selección múltiple, ⌘A y reordenar.
- Cada elemento: miniatura (`QLThumbnailGenerator`) y nombre del archivo, como en Finder.
- Arrastrar hacia fuera: cada elemento seleccionado escribe su `URL` de archivo (`NSURL` como `NSPasteboardWriting`) en el orden del setlist.
- Reordenar dentro del panel y aceptar canciones que llegan desde la búsqueda.
- `SetlistHeader`: fecha, descripción, menú de setlists, "Nuevo setlist", "Marcar como usado".

**Verificación:** arrastrar 1 y 3 archivos a Finder (llegan con el nombre original); arrastrar 3 archivos a **Proclaim** y confirmar que llegan en el orden del setlist.

### T4.5 Pantalla de sugerencias [manual]

**Archivos:** `Containers/SuggestScreen.swift`, `Components/SuggestionSlotRow.swift`.

- Formulario: descripción del servicio (texto de varias líneas), fecha, plantilla o "Sin plantilla" + N.
- Botón "Sugerir" con indicador de progreso y botón de cancelar.
- Resultado: un hueco por fila con etiqueta, canción, motivo y un menú de alternativas; "Buscar otra" abre la Biblioteca con ese hueco como destino.
- "Crear setlist" crea el borrador y lo abre en el panel.

**Verificación:** con el catálogo de prueba y sesión de Claude, una sugerencia con la plantilla "Domingo normal" llena los 5 huecos; con "evitar repeticiones" activo no aparecen canciones usadas.

### T4.6 Ajustes [manual]

**Archivos:** `Containers/SettingsScreen.swift` (escena `Settings`), `Components/VocabularyEditor.swift`, `Components/ServiceTemplateEditor.swift`.

- Pestañas: **Claude** (ruta + botón "Probar conexión", modelos, concurrencia), **OCR** (motor, intervalo), **Vocabularios**, **Sugerencias** (N, plantillas, evitar repeticiones), **Biblioteca** (ubicación, espacio usado, "Mostrar en Finder").
- "Probar conexión" ejecuta una llamada mínima y muestra el resultado o el `ClaudeError`.

**Verificación:** cambiar el motor OCR y el modelo; los cambios siguen después de reiniciar la app; una ruta errónea en "Probar conexión" da un mensaje claro.

---

## Fase 5 — Verificación final

### T5.1 Prueba con el catálogo real [manual]

1. Importar el catálogo real completo. Anotar el tiempo total y las canciones en `failed` o "Revisar".
2. Revisar 20 canciones al azar: letra correcta (≥ 95 % de las líneas), invitaciones y momentos razonables, pasajes correctos.
3. Repetir 10 búsquedas típicas del equipo y comprobar que la canción esperada sale entre los 5 primeros resultados.
4. Preparar el setlist de un domingo real con el sugeridor y arrastrarlo a Proclaim.
5. Anotar los problemas en issues de GitHub. Los ajustes de prompts van en una tarea aparte.

**Terminado cuando:** los puntos 2–4 se cumplen o tienen un issue abierto.

---

## Correspondencia con el spec

| Spec | Tareas |
|---|---|
| §3 Arquitectura | T0.1, T4.1 |
| §4 Modelo de datos y vocabularios | T1.1, T1.2, T1.4, T3.1 |
| §5 Importación, cola, reprocesar | T2.1–T2.9, T4.2, T4.3 |
| §6 Búsqueda | T1.3, T1.5, T1.6, T1.7, T4.3 |
| §7 Sugerencias | T3.1, T3.2, T4.5 |
| §8 Setlist como carpeta | T1.7, T4.4 |
| §9 Ajustes | T3.1, T4.6 |
| §10 Errores | T2.1, T2.4, T2.5, T2.9, T3.2, T4.2 |
| §11 Pruebas | Todas las tareas con pruebas + T5.1 |
