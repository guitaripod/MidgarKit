import Foundation
import Testing
@testable import MidgarCommerceUI

@Suite struct AnchorPluralTests {
    private static let key = "%lld years of %@ costs %@. %@ is %@ and never renews."

    private func anchor(_ years: Int, in language: String) throws -> String {
        let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let format = bundle.localizedString(forKey: Self.key, value: nil, table: nil)
        return String(format: format, locale: Locale(identifier: language), years, "Annual", "$39.98", "Lifetime", "$39.99")
    }

    @Test func polishCountsYearsInTheFormTheNumberTakes() throws {
        #expect(try anchor(1, in: "pl").hasPrefix("Za 1 rok z planem"))
        #expect(try anchor(2, in: "pl").hasPrefix("Za 2 lata z planem"))
        #expect(try anchor(4, in: "pl").hasPrefix("Za 4 lata z planem"))
        #expect(try anchor(5, in: "pl").hasPrefix("Za 5 lat z planem"))
        #expect(try anchor(12, in: "pl").hasPrefix("Za 12 lat z planem"))
        #expect(try anchor(22, in: "pl").hasPrefix("Za 22 lata z planem"))
    }

    @Test func languagesWithOneAndOtherCountOneYearAndManyYears() throws {
        #expect(try anchor(1, in: "en").hasPrefix("1 year of Annual"))
        #expect(try anchor(3, in: "en").hasPrefix("3 years of Annual"))
        #expect(try anchor(1, in: "de").hasPrefix("1 Jahr mit"))
        #expect(try anchor(3, in: "de").hasPrefix("3 Jahre mit"))
        #expect(try anchor(1, in: "es").hasPrefix("1 año de"))
        #expect(try anchor(3, in: "es").hasPrefix("3 años de"))
        #expect(try anchor(1, in: "fr").hasPrefix("1 an avec"))
        #expect(try anchor(3, in: "fr").hasPrefix("3 ans avec"))
        #expect(try anchor(1, in: "it").hasPrefix("1 anno con"))
        #expect(try anchor(3, in: "it").hasPrefix("3 anni con"))
        #expect(try anchor(1, in: "pt-BR").hasPrefix("1 ano de"))
        #expect(try anchor(3, in: "pt-BR").hasPrefix("3 anos de"))
    }

    @Test func languagesWithoutPluralFormsUseTheirOneForm() throws {
        #expect(try anchor(3, in: "ja").hasPrefix("3年分の"))
        #expect(try anchor(3, in: "ko").hasPrefix("3년 치"))
        #expect(try anchor(3, in: "zh-Hans").hasPrefix("3 年的"))
        #expect(try anchor(3, in: "zh-Hant").hasPrefix("3 年的"))
    }

    @Test func everyArgumentOfTheLineReachesTheSentenceInEveryLanguage() throws {
        for language in ["en", "de", "es", "fr", "it", "pl", "pt-BR", "ja", "ko", "zh-Hans", "zh-Hant"] {
            let line = try anchor(2, in: language)

            #expect(line.contains("Annual") && line.contains("$39.98") && line.contains("Lifetime") && line.contains("$39.99"), "\(language): \(line)")
        }
    }
}
