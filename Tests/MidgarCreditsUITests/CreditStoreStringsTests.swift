import Foundation
import Testing
@testable import MidgarCreditsUI

@Suite struct CreditStoreStringsTests {
    private static let languages = ["en", "de", "es", "fr", "it", "ja", "ko", "pl", "pt-BR", "zh-Hans", "zh-Hant"]

    private static let keys = [
        "Your balance",
        "%lld credits",
        "Your balance could not be loaded.",
        "Free allowances",
        "%lld of %lld left",
        "Resets %@",
        "You need %lld more credits to continue.",
        "Enough for this",
        "Buy for %@",
        "Loading credit packs",
        "Credit packs unavailable",
        "The App Store did not return any credit packs. Check your connection and try again.",
        "Your purchase is being confirmed",
        "Your credits arrive as soon as it is confirmed. You do not need to buy again.",
        "%lld credits added",
        "Waiting for approval. Your credits arrive as soon as it is approved.",
        "You are offline. Check your connection and try again.",
        "Credits are unavailable right now. Nothing was charged.",
        "Your session has expired. Sign in and try again.",
        "Too many requests. Try again in a moment.",
        "The purchase could not be verified. If you were charged, contact support.",
        "Credit packs are not available right now."
    ]

    private func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    private func counted(_ key: String, _ count: Int, in language: String) throws -> String {
        let format = try bundle(language).localizedString(forKey: key, value: nil, table: nil)
        return String(format: format, locale: Locale(identifier: language), count)
    }

    @Test func everyCreditStoreStringIsTranslatedInEveryLanguageOfTheCatalog() throws {
        for language in Self.languages {
            let bundle = try bundle(language)
            for key in Self.keys {
                let value = bundle.localizedString(forKey: key, value: "__missing__", table: nil)
                #expect(value != "__missing__", "\(language) lacks \(key)")
                if language != "en" {
                    #expect(value != key, "\(language) has \(key) untranslated")
                }
            }
        }
    }

    @Test func englishAndTheLanguagesLikeItCountOneCreditAndManyCredits() throws {
        #expect(try counted("%lld credits", 1, in: "en") == "1 credit")
        #expect(try counted("%lld credits", 150, in: "en") == "150 credits")
        #expect(try counted("%lld credits", 1, in: "de") == "1 Credit")
        #expect(try counted("%lld credits", 2, in: "de") == "2 Credits")
        #expect(try counted("%lld credits", 1, in: "es") == "1 crédito")
        #expect(try counted("%lld credits", 3, in: "es") == "3 créditos")
        #expect(try counted("%lld credits", 1, in: "fr") == "1 crédit")
        #expect(try counted("%lld credits", 3, in: "it") == "3 crediti")
        #expect(try counted("%lld credits", 3, in: "pt-BR") == "3 créditos")
    }

    @Test func polishCountsCreditsInTheFormTheNumberTakes() throws {
        #expect(try counted("%lld credits", 1, in: "pl") == "1 kredyt")
        #expect(try counted("%lld credits", 3, in: "pl") == "3 kredyty")
        #expect(try counted("%lld credits", 5, in: "pl") == "5 kredytów")
        #expect(try counted("%lld credits", 22, in: "pl") == "22 kredyty")
        #expect(try counted("%lld credits added", 1, in: "pl") == "Dodano 1 kredyt")
        #expect(try counted("%lld credits added", 12, in: "pl") == "Dodano 12 kredytów")
        #expect(try counted("You need %lld more credits to continue.", 5, in: "pl").contains("5 kredytów"))
    }

    @Test func languagesWithoutPluralFormsHaveOneForm() throws {
        #expect(try counted("%lld credits", 1, in: "ja") == "1 クレジット")
        #expect(try counted("%lld credits", 150, in: "ko") == "150 크레딧")
        #expect(try counted("%lld credits", 150, in: "zh-Hans") == "150 积分")
        #expect(try counted("%lld credits", 150, in: "zh-Hant") == "150 點數")
    }

    @Test func theShortfallAndTheCreditedMessageTakeTheCountToo() throws {
        #expect(try counted("You need %lld more credits to continue.", 1, in: "en") == "You need 1 more credit to continue.")
        #expect(try counted("You need %lld more credits to continue.", 20, in: "en") == "You need 20 more credits to continue.")
        #expect(try counted("%lld credits added", 1, in: "en") == "1 credit added")
        #expect(try counted("%lld credits added", 700, in: "de") == "700 Credits hinzugefügt")
    }

    @Test func theAllowanceLineKeepsBothNumbersInEveryLanguage() throws {
        for language in Self.languages {
            let format = try bundle(language).localizedString(forKey: "%lld of %lld left", value: nil, table: nil)
            let line = String(format: format, locale: Locale(identifier: language), 2, 3)

            #expect(line.contains("2") && line.contains("3"), "\(language): \(line)")
        }
    }
}
