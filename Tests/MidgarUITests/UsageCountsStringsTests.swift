import Foundation
import Testing
import MidgarCore
@testable import MidgarUI

@Suite struct UsageCountsStringsTests {
    private static let languages = [
        "ar", "cs", "da", "de", "en", "es", "fi", "fr", "it", "ja", "ko", "nb", "nl", "pl", "pt-BR", "pt-PT", "ru", "sv", "tr", "uk", "vi",
        "zh-Hans", "zh-Hant"
    ]

    private typealias Table = [String: [String: String]]

    private static func catalogTable() throws -> Table {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MidgarUI/Resources/Localizable.xcstrings")
        let document = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let strings = try #require(document["strings"] as? [String: [String: Any]])
        return strings.mapValues { entry in
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            return localizations.compactMapValues { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
        }
    }

    private static func placeholders(_ text: String) -> [String] {
        text.matches(of: /%(?:\d+\$)?(?:lld|@|d)/).map { String($0.output) }.sorted()
    }

    private static var screenKeys: [String] {
        let fixed = [
            MidgarUIStrings.usageCountsTitle, MidgarUIStrings.usageCountsIntro, MidgarUIStrings.usageCountsSwitchFooter,
            MidgarUIStrings.whatThisAppSends, MidgarUIStrings.nothingIsSent, MidgarUIStrings.installWeekNote,
            MidgarUIStrings.thisAppsNumbers, MidgarUIStrings.weeklyActiveInstalls, MidgarUIStrings.newInstalls,
            MidgarUIStrings.allOfMidgarsNumbers, MidgarUIStrings.onOff(isEnabled: true), MidgarUIStrings.onOff(isEnabled: false)
        ]
        return fixed + MidgarSignal.Uniqueness.allCases.map(MidgarUIStrings.frequency(of:)) + MidgarSignalCatalog.entries.map(\.purpose)
    }

    @Test func everyStringTheScreenShowsIsInTheCatalogInEveryLanguage() throws {
        let table = try Self.catalogTable()

        for key in Self.screenKeys {
            let entry = try #require(table[key], "missing key: \(key)")
            for language in Self.languages {
                let value = try #require(entry[language], "\(language) is missing for: \(key)")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(language) is empty for: \(key)")
            }
        }
    }

    @Test func everyEventPurposeOfTheRegistryIsTranslatedNotJustTheOnesAnAppShowsToday() throws {
        let table = try Self.catalogTable()

        for entry in MidgarSignalCatalog.entries {
            let translations = try #require(table[entry.purpose], "\(entry.name) has no translations: \(entry.purpose)")
            #expect(translations["en"] == entry.purpose, "\(entry.name) English must be the registry's sentence")
            #expect(Set(translations.keys) == Set(Self.languages), "\(entry.name) languages")
        }
    }

    @Test func translationsKeepTheirPlaceholdersAndNameMidgarAndUseNoDashes() throws {
        let table = try Self.catalogTable()

        for key in Self.screenKeys {
            for (language, value) in try #require(table[key]) {
                #expect(Self.placeholders(value) == Self.placeholders(key), "\(language) placeholders differ for: \(key)")
                #expect(!value.contains("\u{2014}") && !value.contains("\u{2013}"), "\(language) has a dash: \(value)")
                if key.contains("Midgar") {
                    #expect(value.contains("Midgar"), "\(language) lost the name Midgar: \(value)")
                }
            }
        }
    }

    @Test func languagesWithTheirOwnScriptAreNotLeftInEnglish() throws {
        let table = try Self.catalogTable()

        for key in Self.screenKeys {
            for language in ["ar", "ja", "ko", "ru", "uk", "zh-Hans", "zh-Hant"] {
                #expect(table[key]?[language] != key, "\(language) is still English for: \(key)")
            }
        }
    }

    @Test func noStringInTheCatalogHasAnEmDash() throws {
        let table = try Self.catalogTable()

        for (key, values) in table {
            #expect(!key.contains("\u{2014}"), "em dash in key: \(key)")
            for (language, value) in values {
                #expect(!value.contains("\u{2014}"), "em dash in \(language) for: \(key)")
            }
        }
    }

    @Test func theFewerThanFigureTakesTheThresholdAsItsOnlyPlaceholder() throws {
        let table = try Self.catalogTable()
        let entry = try #require(table["fewer than %lld"])

        #expect(entry["en"] == "fewer than %lld")
        #expect(Set(entry.keys) == Set(Self.languages))
        #expect(MidgarUIStrings.fewerThan(10) == "fewer than 10")
    }
}
