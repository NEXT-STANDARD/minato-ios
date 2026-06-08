import Testing
import SwiftUI
@testable import bitchat

/// Verifies the categorical color tokens (transport / identity / favorite) are
/// defined and visually distinct from each other and from the existing accent /
/// safety palette — so the meaning of each category lives in exactly one place.
@Suite("MinatoTheme categorical tokens")
struct MinatoThemeTokensTests {

    @Test("nostr / selfMark / favorite are mutually distinct")
    func categoricalTokensDistinct() {
        let nostrVsSelf = MinatoTheme.nostr != MinatoTheme.selfMark
        let nostrVsFav = MinatoTheme.nostr != MinatoTheme.favorite
        let selfVsFav = MinatoTheme.selfMark != MinatoTheme.favorite
        #expect(nostrVsSelf)
        #expect(nostrVsFav)
        #expect(selfVsFav)
    }

    @Test("categorical tokens stay distinct from the brand accent and safety palette")
    func categoricalTokensDistinctFromCore() {
        let nostrDistinct = MinatoTheme.nostr != MinatoTheme.accent && MinatoTheme.nostr != MinatoTheme.danger
        let selfDistinct = MinatoTheme.selfMark != MinatoTheme.accent && MinatoTheme.selfMark != MinatoTheme.safe
        let favDistinct = MinatoTheme.favorite != MinatoTheme.accent && MinatoTheme.favorite != MinatoTheme.danger
        #expect(nostrDistinct)
        #expect(selfDistinct)
        #expect(favDistinct)
    }
}
