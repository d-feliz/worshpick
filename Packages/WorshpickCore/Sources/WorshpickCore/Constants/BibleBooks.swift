import Foundation

public struct BibleBook: Sendable, Hashable {
    public let id: Int
    public let spanishName: String
    public let englishName: String
    public let abbreviations: [String]

    public var allNames: [String] { [spanishName, englishName] + abbreviations }
}

public enum BibleBooks {
    public static let all: [BibleBook] = oldTestament + newTestament

    public static func book(id: Int) -> BibleBook? {
        guard all.indices.contains(id - 1) else { return nil }
        return all[id - 1]
    }

    public static func book(named name: String) -> BibleBook? {
        bookByLookupKey[lookupKey(for: name)]
    }

    /// "1 Co.", "1co" and "1 CO" all become "1co".
    public static func lookupKey(for name: String) -> String {
        name.normalizedForMatching.filter { $0.isLetter || $0.isNumber }
    }

    static let bookByLookupKey: [String: BibleBook] = {
        var books: [String: BibleBook] = [:]
        for book in all {
            for name in book.allNames {
                books[lookupKey(for: name)] = book
            }
        }
        return books
    }()

    private static func numberedBook(
        _ id: Int, _ number: Int, spanish: String, english: String, abbreviations: [String]
    ) -> BibleBook {
        BibleBook(
            id: id,
            spanishName: "\(number) \(spanish)",
            englishName: "\(number) \(english)",
            abbreviations: abbreviations.map { "\(number) \($0)" }
        )
    }

    private static let oldTestament: [BibleBook] = [
        BibleBook(id: 1, spanishName: "Génesis", englishName: "Genesis", abbreviations: ["Gn", "Gén", "Gen", "Ge"]),
        BibleBook(id: 2, spanishName: "Éxodo", englishName: "Exodus", abbreviations: ["Éx", "Ex", "Exo", "Exod"]),
        BibleBook(id: 3, spanishName: "Levítico", englishName: "Leviticus", abbreviations: ["Lv", "Lev"]),
        BibleBook(id: 4, spanishName: "Números", englishName: "Numbers", abbreviations: ["Nm", "Núm", "Num"]),
        BibleBook(id: 5, spanishName: "Deuteronomio", englishName: "Deuteronomy", abbreviations: ["Dt", "Deut"]),
        BibleBook(id: 6, spanishName: "Josué", englishName: "Joshua", abbreviations: ["Jos", "Josh"]),
        BibleBook(id: 7, spanishName: "Jueces", englishName: "Judges", abbreviations: ["Jue", "Jc", "Judg", "Jdg"]),
        BibleBook(id: 8, spanishName: "Rut", englishName: "Ruth", abbreviations: ["Rt"]),
        numberedBook(9, 1, spanish: "Samuel", english: "Samuel", abbreviations: ["S", "Sa", "Sam", "Sm"]),
        numberedBook(10, 2, spanish: "Samuel", english: "Samuel", abbreviations: ["S", "Sa", "Sam", "Sm"]),
        numberedBook(11, 1, spanish: "Reyes", english: "Kings", abbreviations: ["R", "Re", "Rey", "Ki", "Kgs"]),
        numberedBook(12, 2, spanish: "Reyes", english: "Kings", abbreviations: ["R", "Re", "Rey", "Ki", "Kgs"]),
        numberedBook(13, 1, spanish: "Crónicas", english: "Chronicles", abbreviations: ["Cr", "Cro", "Crón", "Chr", "Chron"]),
        numberedBook(14, 2, spanish: "Crónicas", english: "Chronicles", abbreviations: ["Cr", "Cro", "Crón", "Chr", "Chron"]),
        BibleBook(id: 15, spanishName: "Esdras", englishName: "Ezra", abbreviations: ["Esd", "Ezr"]),
        BibleBook(id: 16, spanishName: "Nehemías", englishName: "Nehemiah", abbreviations: ["Neh", "Ne"]),
        BibleBook(id: 17, spanishName: "Ester", englishName: "Esther", abbreviations: ["Est", "Esth"]),
        BibleBook(id: 18, spanishName: "Job", englishName: "Job", abbreviations: ["Jb"]),
        BibleBook(id: 19, spanishName: "Salmos", englishName: "Psalms", abbreviations: ["Sal", "Salmo", "Sl", "Ps", "Psa", "Psalm"]),
        BibleBook(id: 20, spanishName: "Proverbios", englishName: "Proverbs", abbreviations: ["Pr", "Pro", "Prov", "Prv"]),
        BibleBook(id: 21, spanishName: "Eclesiastés", englishName: "Ecclesiastes", abbreviations: ["Ec", "Ecl", "Eccl", "Eccles", "Qo"]),
        BibleBook(id: 22, spanishName: "Cantares", englishName: "Song of Songs", abbreviations: ["Cnt", "Cant", "Cantar de los Cantares", "Song", "Song of Solomon", "SS"]),
        BibleBook(id: 23, spanishName: "Isaías", englishName: "Isaiah", abbreviations: ["Is", "Isa"]),
        BibleBook(id: 24, spanishName: "Jeremías", englishName: "Jeremiah", abbreviations: ["Jr", "Jer"]),
        BibleBook(id: 25, spanishName: "Lamentaciones", englishName: "Lamentations", abbreviations: ["Lm", "Lam"]),
        BibleBook(id: 26, spanishName: "Ezequiel", englishName: "Ezekiel", abbreviations: ["Ez", "Eze", "Ezek"]),
        BibleBook(id: 27, spanishName: "Daniel", englishName: "Daniel", abbreviations: ["Dn", "Dan"]),
        BibleBook(id: 28, spanishName: "Oseas", englishName: "Hosea", abbreviations: ["Os", "Hos"]),
        BibleBook(id: 29, spanishName: "Joel", englishName: "Joel", abbreviations: ["Jl"]),
        BibleBook(id: 30, spanishName: "Amós", englishName: "Amos", abbreviations: ["Am"]),
        BibleBook(id: 31, spanishName: "Abdías", englishName: "Obadiah", abbreviations: ["Abd", "Ab", "Ob", "Obad"]),
        BibleBook(id: 32, spanishName: "Jonás", englishName: "Jonah", abbreviations: ["Jon"]),
        BibleBook(id: 33, spanishName: "Miqueas", englishName: "Micah", abbreviations: ["Mi", "Miq", "Mic"]),
        BibleBook(id: 34, spanishName: "Nahúm", englishName: "Nahum", abbreviations: ["Na", "Nah"]),
        BibleBook(id: 35, spanishName: "Habacuc", englishName: "Habakkuk", abbreviations: ["Hab", "Hb"]),
        BibleBook(id: 36, spanishName: "Sofonías", englishName: "Zephaniah", abbreviations: ["Sof", "Zeph", "Zep"]),
        BibleBook(id: 37, spanishName: "Hageo", englishName: "Haggai", abbreviations: ["Hag", "Hg"]),
        BibleBook(id: 38, spanishName: "Zacarías", englishName: "Zechariah", abbreviations: ["Zac", "Zech", "Zec"]),
        BibleBook(id: 39, spanishName: "Malaquías", englishName: "Malachi", abbreviations: ["Mal", "Ml"]),
    ]

    private static let newTestament: [BibleBook] = [
        BibleBook(id: 40, spanishName: "Mateo", englishName: "Matthew", abbreviations: ["Mt", "Mat", "Matt"]),
        BibleBook(id: 41, spanishName: "Marcos", englishName: "Mark", abbreviations: ["Mr", "Mc", "Mar", "Mk", "Mrk"]),
        BibleBook(id: 42, spanishName: "Lucas", englishName: "Luke", abbreviations: ["Lc", "Luc", "Lk"]),
        BibleBook(id: 43, spanishName: "Juan", englishName: "John", abbreviations: ["Jn", "Jua", "Joh"]),
        BibleBook(id: 44, spanishName: "Hechos", englishName: "Acts", abbreviations: ["Hch", "Hech", "Act", "Hechos de los Apóstoles"]),
        BibleBook(id: 45, spanishName: "Romanos", englishName: "Romans", abbreviations: ["Ro", "Rom", "Rm"]),
        numberedBook(46, 1, spanish: "Corintios", english: "Corinthians", abbreviations: ["Co", "Cor"]),
        numberedBook(47, 2, spanish: "Corintios", english: "Corinthians", abbreviations: ["Co", "Cor"]),
        BibleBook(id: 48, spanishName: "Gálatas", englishName: "Galatians", abbreviations: ["Gá", "Gál", "Gal", "Ga"]),
        BibleBook(id: 49, spanishName: "Efesios", englishName: "Ephesians", abbreviations: ["Ef", "Efe", "Eph"]),
        BibleBook(id: 50, spanishName: "Filipenses", englishName: "Philippians", abbreviations: ["Fil", "Flp", "Phil", "Php"]),
        BibleBook(id: 51, spanishName: "Colosenses", englishName: "Colossians", abbreviations: ["Col"]),
        numberedBook(52, 1, spanish: "Tesalonicenses", english: "Thessalonians", abbreviations: ["Ts", "Tes", "Th", "Thess"]),
        numberedBook(53, 2, spanish: "Tesalonicenses", english: "Thessalonians", abbreviations: ["Ts", "Tes", "Th", "Thess"]),
        numberedBook(54, 1, spanish: "Timoteo", english: "Timothy", abbreviations: ["Ti", "Tim", "Tm"]),
        numberedBook(55, 2, spanish: "Timoteo", english: "Timothy", abbreviations: ["Ti", "Tim", "Tm"]),
        BibleBook(id: 56, spanishName: "Tito", englishName: "Titus", abbreviations: ["Tit", "Tt"]),
        BibleBook(id: 57, spanishName: "Filemón", englishName: "Philemon", abbreviations: ["Flm", "Filem", "Phlm", "Philem"]),
        BibleBook(id: 58, spanishName: "Hebreos", englishName: "Hebrews", abbreviations: ["He", "Heb"]),
        BibleBook(id: 59, spanishName: "Santiago", englishName: "James", abbreviations: ["Stg", "Sant", "Jas", "Jm"]),
        numberedBook(60, 1, spanish: "Pedro", english: "Peter", abbreviations: ["P", "Pe", "Ped", "Pet", "Pt"]),
        numberedBook(61, 2, spanish: "Pedro", english: "Peter", abbreviations: ["P", "Pe", "Ped", "Pet", "Pt"]),
        numberedBook(62, 1, spanish: "Juan", english: "John", abbreviations: ["Jn", "Jua", "Joh"]),
        numberedBook(63, 2, spanish: "Juan", english: "John", abbreviations: ["Jn", "Jua", "Joh"]),
        numberedBook(64, 3, spanish: "Juan", english: "John", abbreviations: ["Jn", "Jua", "Joh"]),
        BibleBook(id: 65, spanishName: "Judas", englishName: "Jude", abbreviations: ["Jud", "Jds"]),
        BibleBook(id: 66, spanishName: "Apocalipsis", englishName: "Revelation", abbreviations: ["Ap", "Apoc", "Apo", "Rev", "Revelations"]),
    ]
}
