import Foundation

public struct AppSettings: Codable, Sendable, Equatable {
    public var claudeBinaryPath: String?
    public var analysisModel = "sonnet"
    public var suggestionModel = "sonnet"
    public var defaultOCREngine = OCREngineKind.vision
    public var frameInterval = FrameSampler.defaultInterval
    public var claudeConcurrency = 1
    public var invitationVocabulary = DefaultVocabularies.invitations
    public var momentVocabulary = DefaultVocabularies.moments
    public var defaultSongCount = 5
    public var serviceTemplates = [ServiceTemplate.regularSunday]
    /// 0 turns the "avoid repeats" rule off.
    public var avoidRepeatsSundayCount = 0

    public init() {}

    public var ingestSettings: IngestSettings {
        IngestSettings(
            defaultOCREngine: defaultOCREngine, frameInterval: frameInterval, claudeConcurrency: claudeConcurrency,
            analysisModel: analysisModel, invitationVocabulary: invitationVocabulary, momentVocabulary: momentVocabulary
        )
    }

    /// Missing keys keep their default, so settings saved by an older version still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        claudeBinaryPath = try container.decodeIfPresent(String.self, forKey: .claudeBinaryPath)
        analysisModel = try container.decodeIfPresent(String.self, forKey: .analysisModel) ?? defaults.analysisModel
        suggestionModel = try container.decodeIfPresent(String.self, forKey: .suggestionModel) ?? defaults.suggestionModel
        defaultOCREngine = try container.decodeIfPresent(OCREngineKind.self, forKey: .defaultOCREngine) ?? defaults.defaultOCREngine
        frameInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .frameInterval) ?? defaults.frameInterval
        claudeConcurrency = try container.decodeIfPresent(Int.self, forKey: .claudeConcurrency) ?? defaults.claudeConcurrency
        invitationVocabulary = try container.decodeIfPresent([String].self, forKey: .invitationVocabulary) ?? defaults.invitationVocabulary
        momentVocabulary = try container.decodeIfPresent([String].self, forKey: .momentVocabulary) ?? defaults.momentVocabulary
        defaultSongCount = try container.decodeIfPresent(Int.self, forKey: .defaultSongCount) ?? defaults.defaultSongCount
        serviceTemplates = try container.decodeIfPresent([ServiceTemplate].self, forKey: .serviceTemplates) ?? defaults.serviceTemplates
        avoidRepeatsSundayCount = try container.decodeIfPresent(Int.self, forKey: .avoidRepeatsSundayCount) ?? defaults.avoidRepeatsSundayCount
    }
}
