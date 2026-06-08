import SwiftUI

extension Font {
    /// MINATO type ramp. Currently delegates to the inherited bitchat font helper
    /// so the look is unchanged; swapping the typeface later is a one-place edit.
    /// Prefer this in MINATO-owned views going forward.
    static func minatoSystem(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        bitchatSystem(size: size, weight: weight, design: design)
    }
}
