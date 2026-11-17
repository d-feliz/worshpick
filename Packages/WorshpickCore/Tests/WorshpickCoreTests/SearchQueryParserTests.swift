import Testing
@testable import WorshpickCore

@Suite struct SearchQueryParserTests {
    @Test func freeTextOnly() {
        let query = SearchQueryParser.parse("gracia  amor")
        #expect(query.freeText == ["gracia", "amor"])
        #expect(query.hasTextTerms)
    }

    @Test func eachPrefix() {
        #expect(SearchQueryParser.parse("autor:Rivera").authorTerms == ["Rivera"])
        #expect(SearchQueryParser.parse("letra:altar").lyricsTerms == ["altar"])
        #expect(SearchQueryParser.parse("tema:cruz").themeTerms == ["cruz"])
        #expect(SearchQueryParser.parse("#esperanza").invitationTags == ["esperanza"])
        #expect(SearchQueryParser.parse("Autor:Rivera").authorTerms == ["Rivera"])
    }

    @Test func emptyPrefixValueIsIgnored() {
        let query = SearchQueryParser.parse("autor: #")
        #expect(query.authorTerms.isEmpty)
        #expect(query.invitationTags.isEmpty)
    }

    @Test func quotedPhrases() {
        let query = SearchQueryParser.parse("\"nada me apartará\" amor")
        #expect(query.exactPhrases == ["nada me apartará"])
        #expect(query.freeText == ["amor"])
    }

    @Test func curlyQuotes() {
        #expect(SearchQueryParser.parse("“mi vida en el altar”").exactPhrases == ["mi vida en el altar"])
    }

    @Test func unclosedQuoteIsText() {
        let query = SearchQueryParser.parse("\"nada me")
        #expect(query.exactPhrases.isEmpty)
        #expect(query.freeText == ["nada", "me"])
    }

    @Test func combinesReferenceWithTextAndPrefixes() {
        let query = SearchQueryParser.parse("Rom 8 tema:amor #confianza gracia")
        #expect(query.references == [BibleReference(bookId: 45, startPosition: 8001, endPosition: 8999)])
        #expect(query.themeTerms == ["amor"])
        #expect(query.invitationTags == ["confianza"])
        #expect(query.freeText == ["gracia"])
    }

    @Test func emptyQuery() {
        #expect(SearchQueryParser.parse("   ").isEmpty)
        #expect(SearchQueryParser.parse(" - , ").isEmpty)
    }
}
