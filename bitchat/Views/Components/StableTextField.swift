#if os(iOS)
import SwiftUI
import UIKit

/// A UITextField wrapper that preserves Japanese IME composing state
/// across SwiftUI view re-renders. SwiftUI's native TextField commits
/// marked text (composing) when the parent view re-renders, which breaks
/// CJK input. This wrapper isolates the UITextField from re-renders.
struct StableTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: UIFont
    var textColor: UIColor
    var placeholderColor: UIColor
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.font = font
        tf.textColor = textColor
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .sentences
        tf.returnKeyType = .send
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: placeholderColor]
        )
        tf.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return tf
    }

    func updateUIView(_ tf: UITextField, context: Context) {
        // Only update text if the UITextField is NOT actively composing (has marked text).
        // Also skip if the values already match to avoid cursor jumps.
        if tf.markedTextRange == nil, tf.text != text {
            tf.text = text
        }
        tf.font = font
        tf.textColor = textColor
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: StableTextField

        init(_ parent: StableTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ tf: UITextField) {
            // Only sync to binding when NOT composing (no marked text)
            if tf.markedTextRange == nil {
                parent.text = tf.text ?? ""
            }
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}
#endif
