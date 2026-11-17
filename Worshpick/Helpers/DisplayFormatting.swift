import Foundation
import WorshpickCore

enum DisplayFormatting {
    static func duration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "" }
        let totalSeconds = Int(seconds.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    static func lastUsed(_ date: Date?, today: Date = .now, calendar: Calendar = .current) -> String? {
        guard let date else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: today)).day ?? 0
        if days < 0 { return "Programada el \(date.formatted(date: .abbreviated, time: .omitted))" }
        if days < 7 { return "Cantada esta semana" }
        let weeks = days / 7
        return weeks == 1 ? "Cantada hace 1 semana" : "Cantada hace \(weeks) semanas"
    }

    static func energy(_ energy: Energy?) -> String {
        energy.flatMap { DefaultVocabularies.energyLabels[$0] } ?? "—"
    }

    static func language(_ language: SongLanguage?) -> String {
        switch language {
        case .es: "Español"
        case .en: "Inglés"
        case .other: "Otro"
        case nil: "—"
        }
    }

    static func status(_ song: Song) -> String {
        switch song.status {
        case .pending: "En cola"
        case .extracting: "Leyendo letra…"
        case .analyzing: "Analizando con Claude…"
        case .ready: "Lista"
        case .failed: song.failureReason ?? "Error"
        }
    }

    static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
