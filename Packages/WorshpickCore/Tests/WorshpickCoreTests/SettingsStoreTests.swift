import Foundation
import Testing
@testable import WorshpickCore

@Suite struct SettingsStoreTests {
    @Test func defaultsIncludeRegularSundayTemplate() throws {
        let store = SettingsStore(fileURL: try makeTemporaryFolder().appending(path: "settings.json"))
        #expect(store.current.serviceTemplates == [.regularSunday])
        #expect(store.current.defaultSongCount == 5)
        #expect(store.current.avoidRepeatsSundayCount == 0)
        #expect(ServiceTemplate.regularSunday.slots.count == 5)
    }

    @Test func savedSettingsRoundTrip() throws {
        let fileURL = try makeTemporaryFolder().appending(path: "settings.json")
        try SettingsStore(fileURL: fileURL).update { settings in
            settings.analysisModel = "opus"
            settings.defaultOCREngine = .claude
            settings.avoidRepeatsSundayCount = 3
        }
        let reloaded = SettingsStore(fileURL: fileURL).current
        #expect(reloaded.analysisModel == "opus")
        #expect(reloaded.defaultOCREngine == .claude)
        #expect(reloaded.avoidRepeatsSundayCount == 3)
        #expect(reloaded.ingestSettings.analysisModel == "opus")
    }

    @Test func damagedFileFallsBackToDefaults() throws {
        let fileURL = try makeTemporaryFolder().appending(path: "settings.json")
        try Data("{ no es json".utf8).write(to: fileURL)
        #expect(SettingsStore(fileURL: fileURL).current == AppSettings())
    }

    @Test func missingKeysKeepDefaults() throws {
        let fileURL = try makeTemporaryFolder().appending(path: "settings.json")
        try Data(#"{"analysisModel": "haiku"}"#.utf8).write(to: fileURL)
        let settings = SettingsStore(fileURL: fileURL).current
        #expect(settings.analysisModel == "haiku")
        #expect(settings.invitationVocabulary == DefaultVocabularies.invitations)
    }
}
