import Foundation
import Testing

struct ToolsLocalizationTests {
    /// `swift test` does not compile String Catalogs into .lproj folders, so the catalog source is checked directly.
    @Test func everyKeyHasAGermanTranslation() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Tools/Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        let strings = try #require(json?["strings"] as? [String: Any])
        #expect(!strings.isEmpty)
        for (key, value) in strings {
            let localizations = (value as? [String: Any])?["localizations"] as? [String: Any]
            let de = ((localizations?["de"] as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
            #expect(de?.isEmpty == false, "Missing German translation for \(key)")
        }
    }
}
