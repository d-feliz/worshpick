import Foundation

public struct SuggestionRequest: Sendable {
    public var serviceDescription: String
    public var serviceDate: Date
    /// nil means "no template": `songCount` slots without criteria.
    public var template: ServiceTemplate?
    public var songCount: Int

    public init(serviceDescription: String, serviceDate: Date, template: ServiceTemplate?, songCount: Int) {
        self.serviceDescription = serviceDescription
        self.serviceDate = serviceDate
        self.template = template
        self.songCount = songCount
    }
}

public struct SuggestedSlot: Sendable, Equatable, Identifiable {
    public var slotIndex: Int
    public var label: String
    public var songId: UUID?
    public var reason: String
    public var alternativeSongIds: [UUID]

    public var id: Int { slotIndex }
    public var hasSuggestion: Bool { songId != nil }
}

public struct SuggestionDraft: Sendable, Equatable {
    public var serviceDescription: String
    public var serviceDate: Date
    public var slots: [SuggestedSlot]
}

public enum SuggesterError: Error, Equatable, LocalizedError {
    case noCandidateSongs

    public var errorDescription: String? {
        "No hay canciones disponibles para sugerir. Importa canciones o desactiva \"evitar repeticiones\"."
    }
}

/// Claude only chooses among catalog songs; any id it returns that is not a candidate is dropped.
public struct Suggester: Sendable {
    private let catalogStore: CatalogStore
    private let setlistStore: SetlistStore
    private let claudeRunner: any ClaudeRunning
    private let settingsProvider: @Sendable () -> AppSettings

    public init(
        catalogStore: CatalogStore, setlistStore: SetlistStore, claudeRunner: any ClaudeRunning,
        settingsProvider: @escaping @Sendable () -> AppSettings
    ) {
        self.catalogStore = catalogStore
        self.setlistStore = setlistStore
        self.claudeRunner = claudeRunner
        self.settingsProvider = settingsProvider
    }

    public func suggest(_ request: SuggestionRequest, today: Date = .now) async throws -> SuggestionDraft {
        let settings = settingsProvider()
        let template = request.template ?? .withoutCriteria(songCount: request.songCount)
        let candidateSongs = try candidateSongs(avoidRepeatsSundayCount: settings.avoidRepeatsSundayCount, today: today)
        guard !candidateSongs.isEmpty else { throw SuggesterError.noCandidateSongs }

        let passagesBySongId = try catalogStore.passagesBySongId()
        let compactCatalog = candidateSongs.map { Self.compactCatalogLine(for: $0, passages: passagesBySongId[$0.id] ?? []) }
        let output = try await claudeRunner.run(ClaudeRequest(
            prompt: ClaudePrompts.suggestion(
                serviceDescription: request.serviceDescription, serviceDate: request.serviceDate,
                slots: template.slots, compactCatalog: compactCatalog
            ),
            jsonSchema: ClaudeSchemas.suggestionSchema,
            model: settings.suggestionModel
        ))
        let response: SuggestionResponse
        do {
            response = try JSONDecoder().decode(SuggestionResponse.self, from: output)
        } catch {
            throw ClaudeError.invalidOutput(details: String(describing: error))
        }

        return SuggestionDraft(
            serviceDescription: request.serviceDescription,
            serviceDate: request.serviceDate,
            slots: Self.validatedSlots(from: response, template: template, candidateSongIds: Set(candidateSongs.map(\.id)))
        )
    }

    func candidateSongs(avoidRepeatsSundayCount: Int, today: Date) throws -> [Song] {
        let readySongs = try catalogStore.songs(withStatuses: [.ready])
        guard avoidRepeatsSundayCount > 0 else { return readySongs }
        let recentlyUsedSongIds = try setlistStore.songIdsUsedInLastSundays(avoidRepeatsSundayCount, relativeTo: today)
        return readySongs.filter { !recentlyUsedSongIds.contains($0.id) }
    }

    static func compactCatalogLine(for song: Song, passages: [Passage]) -> String {
        let line: [String: Any] = [
            "id": song.id.uuidString,
            "title": song.title,
            "artist": song.artist,
            "language": song.language?.rawValue ?? "",
            "invitations": song.invitations,
            "themes": song.themes,
            "passages": passages.map(\.reference.displayText),
            "moments": song.moments,
            "energy": song.energy?.rawValue ?? "",
            "summary": song.summary,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// A song chosen for an earlier slot leaves later slots that repeat it empty.
    static func validatedSlots(from response: SuggestionResponse, template: ServiceTemplate, candidateSongIds: Set<UUID>) -> [SuggestedSlot] {
        let responseSlotsByIndex = Dictionary(response.slots.map { ($0.slotIndex, $0) }, uniquingKeysWith: { first, _ in first })
        var chosenSongIds: Set<UUID> = []
        var slots: [SuggestedSlot] = template.slots.enumerated().map { slotIndex, templateSlot in
            let responseSlot = responseSlotsByIndex[slotIndex]
            let proposedSongId = responseSlot.flatMap { UUID(uuidString: $0.songId) }
            let isUsableSong = proposedSongId.map { candidateSongIds.contains($0) && !chosenSongIds.contains($0) } ?? false
            guard isUsableSong, let songId = proposedSongId else {
                return SuggestedSlot(slotIndex: slotIndex, label: templateSlot.label, songId: nil, reason: "", alternativeSongIds: [])
            }
            chosenSongIds.insert(songId)
            return SuggestedSlot(slotIndex: slotIndex, label: templateSlot.label, songId: songId, reason: responseSlot?.reason ?? "", alternativeSongIds: [])
        }

        for slotIndex in slots.indices {
            let proposedAlternatives = responseSlotsByIndex[slotIndex]?.alternativeSongIds.compactMap(UUID.init(uuidString:)) ?? []
            var alternatives: [UUID] = []
            for alternative in proposedAlternatives where candidateSongIds.contains(alternative) && !chosenSongIds.contains(alternative) && !alternatives.contains(alternative) {
                alternatives.append(alternative)
            }
            slots[slotIndex].alternativeSongIds = alternatives
        }
        return slots
    }
}
