# Worshpick — Spec de diseño

- **Fecha:** 2026-11-16
- **Estado:** Aprobado
- **Plataforma:** macOS 15+ (app nativa SwiftUI)

## 1. Propósito

Worshpick ayuda a elegir las canciones de alabanza de un servicio a partir de un catálogo propio de **videos de letras**.

El usuario importa sus videos. La IA extrae la letra y etiqueta cada canción con lo que la canción invita a hacer (Reflexión, Alegría, Esperanza...), sus temas, los pasajes bíblicos relacionados, el momento del servicio y la energía. Después el usuario elige canciones de dos maneras:

1. **Sugerencia** — describe el servicio (pasajes, idea principal) y la IA propone N canciones del catálogo. Es rápido, pero puede ser menos preciso.
2. **Búsqueda** — búsqueda manual simple pero potente por nombre, autor, letra, significado, etiquetas y pasajes.

El resultado es un **setlist**: una lista ordenada de archivos de video que el usuario arrastra a Proclaim.

### Criterios de éxito

- Importar un video de letras deja la canción buscable sin trabajo manual en la mayoría de los casos.
- Una búsqueda responde en menos de 50 ms y funciona sin internet.
- Preparar el setlist de un domingo lleva minutos, no una hora.

## 2. Decisiones tomadas

| Decisión | Elección |
|---|---|
| Fuente del catálogo | Videos de letras (texto en pantalla). |
| Cómo entran los archivos | El usuario arrastra archivos sueltos o usa "Importar…". |
| Almacenamiento | Worshpick **copia** cada video a su propia biblioteca. |
| Dónde se usa la IA | Solo al **importar** (extraer y etiquetar) y en el **sugeridor**. La búsqueda no usa IA. |
| Proveedor de IA | El CLI de Claude Code (`claude -p`), con la cuenta del usuario. No hace falta API key. |
| OCR | Apple Vision por defecto. Claude como motor alternativo (en Ajustes y por canción). |
| Búsqueda | SQLite + FTS5 + filtros por facetas + parser de referencias bíblicas. |
| Usuarios | Un usuario en un Mac. No hay sincronización ni cuentas en v1. |

## 3. Arquitectura

```
Worshpick.app (SwiftUI, macOS 15+)
├── Library          copia videos a ~/Library/Application Support/Worshpick/Videos/<uuid>/<nombre original>
├── IngestPipeline   cola persistente de trabajos, reanudable
│   ├── FrameSampler     AVFoundation → fotogramas; descarta casi-duplicados (hash perceptual)
│   ├── OCREngine        protocolo: VisionOCR | ClaudeOCR
│   └── SongAnalyzer     claude -p --json-schema → letra limpia + metadatos
├── ClaudeCLI        envoltorio de Process: localiza el binario, timeout, valida JSON, 1 reintento
├── CatalogStore     SQLite (GRDB) + FTS5: canciones, pasajes, setlists, historial de uso
├── Search           parser de consulta → FTS5 + filtros + referencias bíblicas (sin IA)
├── Suggester        servicio + plantilla + historial → claude -p → ids de canciones del catálogo
└── Setlist          lista ordenada mostrada como carpeta → arrastrar archivos a Proclaim
```

### Principios

- **Solo `IngestPipeline` y `Suggester` usan IA.** `Search` lee únicamente SQLite.
- **Claude nunca inventa canciones.** El sugeridor solo recibe canciones del catálogo y debe devolver ids que existen. La app descarta los ids desconocidos.
- **Todo resultado de la IA se puede editar.** Un campo editado a mano queda en `manuallyEditedFields` y un reprocesado no lo sobrescribe.
- **`ClaudeCLI` es un protocolo.** Las pruebas usan una implementación falsa con respuestas fijas.

### Estructura del proyecto

Adaptación de la estructura habitual al proyecto Swift:

```
Worshpick/
├── Components/    vistas SwiftUI sin estado (SongRow, TagChip, LyricsView...)
├── Containers/    vistas con estado (SearchScreen, SuggestScreen, SetlistPanel, SettingsScreen)
├── Stores/        CatalogStore, SetlistStore, SettingsStore
├── Services/      IngestPipeline, FrameSampler, OCREngine, SongAnalyzer, Suggester, ClaudeCLI
├── Helpers/       BibleReferenceParser, SearchQueryParser, PerceptualHash, FileNaming
├── Constants/     libros de la Biblia (es/en + abreviaturas), vocabularios por defecto, JSON schemas
├── Assets/
└── Tests/
```

## 4. Modelo de datos

### Song

| Campo | Origen | Nota |
|---|---|---|
| `id`, `videoFile`, `originalFileName`, `fileHash`, `duration`, `importedAt` | app | `fileHash` (SHA-256) evita importar dos veces el mismo video. |
| `title`, `artist` | IA (de los fotogramas y del nombre del archivo) | Editables. |
| `language` | IA | `es`, `en`, `other`. |
| `lyrics` | IA (OCR limpio, estrofas separadas por una línea en blanco, sin repeticiones de pantalla) | Editable. |
| `summary` | IA, 1–2 frases | |
| `keywords` | IA, 10–20 conceptos y sinónimos que **no** aparecen en la letra | Permiten "buscar por significado" sin IA. |
| `invitations` | IA, 1–3 valores de una lista fija | Ver vocabularios. |
| `themes` | IA, 2–5 | Claude recibe los temas que ya existen y debe reutilizarlos antes de crear uno nuevo. |
| `passages` | IA | Tabla aparte, ver abajo. |
| `moments` | IA, 1–2 valores de una lista fija | |
| `energy` | IA: `high` / `medium` / `low` | |
| `ocrEngine` | app | `vision` o `claude`. |
| `ocrConfidence` | app | Confianza media de Vision. Por debajo de 0,6 la canción queda marcada "Revisar". |
| `status` | app | `pending → extracting → analyzing → ready`, o `failed(reason)`. |
| `manuallyEditedFields` | app | Conjunto de nombres de campo. |

### Passage

`songId, bookId, chapter, verseStart?, verseEnd?, kind (quote | allusion)`

`bookId` sale de una tabla con los 66 libros, sus nombres en español e inglés y sus abreviaturas (Rom, Ro, Romanos, Romans...).

### Setlist

`id, serviceDate, serviceDescription, status (draft | used), items[]`
`SetlistItem: position, songId, slotLabel?` (p. ej. "Apertura")

El **historial de uso** se calcula con los setlists en estado `used`. Ese historial alimenta "no usada en los últimos N domingos".

### Vocabularios por defecto (editables en Ajustes)

- **Invitaciones:** Adoración, Alegría, Celebración, Gratitud, Reflexión, Arrepentimiento, Entrega, Confianza, Esperanza, Consuelo, Envío.
- **Momentos:** Apertura, Adoración, Respuesta, Ofrenda, Santa Cena, Cierre.
- **Energía:** Alta, Media, Baja.

## 5. Importación con IA

### Flujo

1. El usuario arrastra videos (`.mp4`, `.mov`, `.m4v`) a la ventana o usa "Importar…".
2. La app calcula `fileHash`. Si ya existe, avisa y no importa el archivo.
3. Copia el video a la biblioteca como `Videos/<uuid>/<nombre original>` y crea la canción con `status = pending`. La carpeta `<uuid>` evita colisiones y conserva el nombre original, que es el nombre que Proclaim muestra cuando el usuario arrastra el archivo.
4. **FrameSampler:** toma 1 fotograma cada 1,5 s (configurable), lo reduce a 1280 px de ancho y descarta los casi-duplicados con un hash perceptual (dHash). Máximo 120 fotogramas por canción.
5. **OCR:**
   - **VisionOCR** (por defecto): `VNRecognizeTextRequest` en modo preciso, idiomas `es-ES` y `en-US`. El resultado es una lista ordenada de bloques `{timestamp, text, confidence}`. Los bloques consecutivos iguales se unen.
   - **ClaudeOCR**: escribe hasta 40 fotogramas únicos en una carpeta temporal y llama a `claude -p`. Claude solo puede usar la herramienta de lectura, y solo en esa carpeta. Devuelve los mismos bloques de texto.
6. **SongAnalyzer:** una llamada a `claude -p --output-format json --json-schema <schema> --no-session-persistence`, sin herramientas. Entrada: los bloques OCR, el nombre original del archivo, los vocabularios y los temas existentes. Salida: todos los campos de IA de `Song` y sus `passages`.
7. La app valida el JSON contra el schema. Si no es válido, reintenta una vez. Si falla otra vez: `failed(reason)`.
8. Guarda la canción con `status = ready` y actualiza el índice FTS5.

### Comportamiento de la cola

- Los estados se guardan en la base de datos. Al abrir la app, la cola continúa donde se quedó.
- OCR y Claude corren en etapas separadas: mientras Claude analiza la canción A, Vision procesa la canción B.
- Concurrencia de Claude: 1 llamada a la vez por defecto (configurable de 1 a 3).
- Cada canción muestra su estado en la lista. Una barra global muestra el progreso: "Analizando 12 de 40".

### Reprocesar

En el menú contextual de cada canción:

- **Reanalizar** — repite solo el paso 6 con el texto OCR guardado.
- **Reprocesar con Claude OCR** — repite los pasos 5 y 6 con ClaudeOCR.

Ninguna de las dos opciones sobrescribe los campos de `manuallyEditedFields`.

## 6. Búsqueda

La búsqueda no usa IA. Es instantánea y funciona sin conexión.

### Caja de búsqueda

- **Texto libre** → FTS5 sobre todos los campos de texto. Pesos (BM25): título ×10, artista ×6, keywords y temas ×4, resumen ×3, letra ×2.
  - Tokenizador `unicode61 remove_diacritics 2`: no distingue tildes ni mayúsculas.
  - Busca por prefijo: "gra" encuentra "gracia".
  - `"frase entre comillas"` busca la frase exacta.
- **Referencias bíblicas** → `BibleReferenceParser` detecta referencias como "Sal 23", "Isaías 40:31" o "Romans 8". Una canción coincide si alguno de sus pasajes **se solapa** con el rango buscado. Las referencias y el texto restante de la consulta se combinan con Y.
- **Prefijos opcionales** para usuarios avanzados: `autor:`, `letra:`, `tema:`, `#esperanza` (invitación).

### Filtros (chips)

Invitación · Tema · Momento · Energía · Idioma · "No usada en los últimos N domingos" · Estado "Revisar".

Valores distintos del mismo filtro se combinan con O. Filtros distintos se combinan con Y.

### Resultados

- Cada fila muestra: título, artista, chips de invitación y momento, energía, duración y "cantada hace X semanas".
- Cada fila muestra **por qué coincide**: un fragmento de letra con la coincidencia resaltada, "Pasaje: Romanos 8:38" o "Tema: gracia".
- Al seleccionar una canción, un panel lateral muestra la letra completa, los metadatos editables y una vista previa del video.
- Los resultados se actualizan mientras el usuario escribe. Objetivo: < 50 ms con 5.000 canciones.

## 7. Sugerencia de canciones

### Entrada

- **Descripción del servicio** (texto libre): pasajes que se predicarán, idea principal, ocasión.
- **Fecha del servicio.**
- **Plantilla** (de Ajustes) o "Sin plantilla" con N canciones.

### Plantillas de servicio

Una plantilla es una lista ordenada de huecos. Cada hueco tiene una etiqueta y criterios opcionales:

```
Domingo normal
  1. Apertura      — momento: Apertura, energía: Alta
  2. Apertura      — momento: Apertura, energía: Alta
  3. Adoración     — momento: Adoración
  4. Adoración     — momento: Adoración, energía: Baja
  5. Respuesta     — momento: Respuesta
```

### Proceso

1. La app quita del catálogo las canciones usadas en los últimos N domingos (si esa opción está activa) y las que no están en estado `ready`.
2. La app construye un catálogo compacto: `id, título, artista, idioma, invitaciones, temas, pasajes, momentos, energía, resumen` (unos 60 tokens por canción).
3. Una llamada a `claude -p --json-schema` con la descripción del servicio, la plantilla y el catálogo compacto.
4. Salida por hueco: `{slotIndex, songId, reason, alternativeSongIds[2]}`.
5. La app descarta los ids que no existen o que están excluidos, y las canciones repetidas entre huecos. Si un hueco queda vacío, lo muestra como "Sin sugerencia" para que el usuario lo llene con la búsqueda.

### Resultado

Las sugerencias se convierten en un **setlist en borrador**. Para cada hueco, el usuario puede:

- leer el motivo de la sugerencia,
- cambiar la canción por una de las alternativas,
- reemplazarla con la búsqueda manual,
- reordenar o quitar canciones.

## 8. Setlist y salida

La salida es simple: el usuario arrastra los archivos del setlist a Proclaim. Worshpick no exporta nada ni se integra con Proclaim de otra forma.

- Un panel de setlist, siempre visible a la derecha, acepta canciones de la búsqueda (botón o arrastrar) y del sugeridor.
- El panel muestra el setlist **como una carpeta de Finder**: cada canción es un archivo de video con su miniatura y su nombre de archivo, en el orden del setlist.
- Cada archivo se puede **arrastrar** a Proclaim (o a cualquier app que acepte archivos). El arrastre entrega el archivo real de la biblioteca, con su nombre legible (ver §5, paso 3).
- El usuario puede seleccionar varios archivos (⌘/⇧-clic o ⌘A) y arrastrarlos juntos. Se entregan en el orden del setlist.
- **Marcar como usado** pasa el setlist a `used` con su fecha. Este paso alimenta el historial.

## 9. Ajustes

- **Claude CLI:** ruta del binario (se detecta sola), modelo para importar, modelo para sugerir, prueba de conexión.
- **OCR:** motor por defecto (Vision / Claude), intervalo entre fotogramas.
- **Vocabularios:** invitaciones y momentos.
- **Sugerencias:** número de canciones por defecto, plantillas de servicio, "evitar canciones usadas en los últimos N domingos" (0 = desactivado).
- **Biblioteca:** ubicación y espacio usado.

## 10. Errores

| Situación | Comportamiento |
|---|---|
| No se encuentra `claude` o no hay sesión iniciada | Banner con instrucciones. Las canciones quedan en `pending`. La búsqueda funciona con lo que ya existe. |
| Claude devuelve JSON inválido | 1 reintento. Después `failed(reason)` con un botón "Reintentar". |
| Timeout de Claude (3 min) | Igual que JSON inválido. |
| Límite de uso de Claude | La cola se pausa y muestra el mensaje del CLI. El usuario la reanuda. |
| Video ilegible o sin pista de video | `failed("No se puede leer el video")`. |
| Vision no encuentra texto | La canción queda en "Revisar" y la app propone "Reprocesar con Claude OCR". |
| Disco lleno al copiar | Se cancela la importación de ese archivo con un aviso. No se crea la canción. |
| El sugeridor devuelve ids inválidos | Se descartan. Los huecos vacíos se muestran como "Sin sugerencia". |

## 11. Pruebas

- **Unitarias:**
  - `BibleReferenceParser`: abreviaturas es/en, rangos, solapamiento, entradas inválidas.
  - `SearchQueryParser`: prefijos, comillas, referencias mezcladas con texto.
  - Ranking FTS5 con un catálogo de prueba: el título pesa más que la letra, no distingue tildes, prefijos.
  - Validación de las respuestas de Claude contra los JSON schemas (válidas e inválidas).
  - Filtro de repeticiones del sugeridor y descarte de ids desconocidos.
- **Integración:** la cola de importación completa con 3 videos de muestra y un `ClaudeCLI` falso. Incluye la reanudación después de cerrar la app.
- **Prueba manual:** importar el catálogo real, revisar 20 canciones al azar y medir los aciertos de letra y etiquetas.

## 12. Fuera de alcance (v1)

- Integración con Proclaim más allá de arrastrar archivos (formatos de importación, automatización).
- Exportar el setlist a una carpeta o como texto.
- Sincronización entre varios Macs o varios usuarios.
- Catálogos que no son videos de letras (audio, PDF, ChordPro).
- Transcripción de audio.
- Búsqueda con IA o embeddings.
- Tonalidad, BPM y acordes.

