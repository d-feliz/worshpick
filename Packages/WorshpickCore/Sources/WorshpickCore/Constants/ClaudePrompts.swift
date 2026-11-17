import Foundation

public enum ClaudePrompts {
    public static func songAnalysis(
        originalFileName: String, ocrText: String, invitations: [String], moments: [String], existingThemes: [String]
    ) -> String {
        """
        Eres un asistente que cataloga canciones de alabanza para una iglesia.
        Recibes el texto que un OCR leyó en las pantallas de un video de letras. El texto puede tener errores de \
        reconocimiento, pantallas repetidas y créditos (título, autor, licencia).

        Devuelve un JSON con:
        - title y artist: normalmente están en la primera pantalla o en el nombre del archivo. artist vacío si no aparece.
        - language: es, en u other.
        - lyrics: la letra limpia y corregida. Quita las repeticiones de pantalla consecutivas, pero conserva el orden \
        de la canción. Separa las estrofas con una línea en blanco. No incluyas créditos ni licencias.
        - summary: 1 o 2 frases sobre el mensaje de la canción, en español.
        - keywords: 10 a 20 conceptos, sinónimos o ideas que expresan el significado de la canción pero que NO aparecen \
        literalmente en la letra (por ejemplo "perdón" para una letra que dice "lavaste mi pecado"). En español.
        - invitations: 1 a 3 valores, solo de esta lista: \(invitations.joined(separator: ", ")).
        - themes: 2 a 5 temas teológicos en español y en minúsculas. Reutiliza uno de los temas existentes si encaja \
        antes de crear uno nuevo. Temas existentes: \(existingThemes.isEmpty ? "(ninguno todavía)" : existingThemes.joined(separator: ", ")).
        - moments: 1 o 2 momentos del servicio, solo de esta lista: \(moments.joined(separator: ", ")).
        - energy: high, medium o low.
        - passages: pasajes bíblicos que la letra cita (kind quote) o a los que alude con claridad (kind allusion). \
        Usa el nombre del libro en español. No inventes pasajes; si no hay ninguno claro, devuelve una lista vacía.

        Nombre del archivo: \(originalFileName)

        Texto OCR (cada bloque es una pantalla):
        \(ocrText)
        """
    }

    public static func frameOCR(frameFileNames: [String]) -> String {
        """
        Lee el texto que aparece en cada una de estas imágenes, que son fotogramas de un video de letras de una canción. \
        Usa la herramienta Read para abrir cada archivo, en este orden:
        \(frameFileNames.enumerated().map { "\($0.offset): \($0.element)" }.joined(separator: "\n"))

        Devuelve un bloque por imagen que tenga texto, con frameIndex igual al número de la lista y el texto tal como \
        aparece, con sus saltos de línea. Omite las imágenes sin texto. No corrijas ni completes la letra.
        """
    }

    public static func suggestion(
        serviceDescription: String, serviceDate: Date, slots: [ServiceSlot], compactCatalog: [String]
    ) -> String {
        let dateText = serviceDate.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "es")))
        let slotLines = slots.enumerated().map { "\($0.offset): \($0.element.label) (\($0.element.criteriaDescription))" }
        return """
            Eres un asistente que ayuda a un líder de alabanza a elegir canciones para un servicio de iglesia.

            Servicio del \(dateText):
            \(serviceDescription)

            Elige una canción del catálogo para cada hueco. Respeta los criterios de cada hueco cuando sea posible y \
            prioriza canciones cuyo mensaje, temas y pasajes encajen con el servicio. No repitas una canción en dos huecos.
            Para cada hueco devuelve slotIndex, songId (el id exacto del catálogo), reason (una frase en español que \
            explique por qué encaja) y hasta 2 alternativeSongIds del catálogo. Usa solo ids que aparecen en el catálogo.

            Huecos:
            \(slotLines.joined(separator: "\n"))

            Catálogo (una canción JSON por línea):
            \(compactCatalog.joined(separator: "\n"))
            """
    }

    public static let connectionTest = "Responde con ok = true."
}
