#if os(iOS)
    import Runestone
    import UIKit

    final class ProfileEditorTheme: Theme {
        let font: UIFont = .monospacedSystemFont(ofSize: 14, weight: .regular)
        let textColor: UIColor = .label

        let gutterBackgroundColor: UIColor = .secondarySystemBackground
        let gutterHairlineColor: UIColor = .separator

        let lineNumberColor: UIColor = .secondaryLabel
        let lineNumberFont: UIFont = .monospacedSystemFont(ofSize: 14, weight: .regular)

        let selectedLineBackgroundColor: UIColor = .systemFill
        let selectedLinesLineNumberColor: UIColor = .label
        let selectedLinesGutterBackgroundColor: UIColor = .secondarySystemBackground

        let invisibleCharactersColor: UIColor = .tertiaryLabel

        let pageGuideHairlineColor: UIColor = .separator
        let pageGuideBackgroundColor: UIColor = .secondarySystemBackground

        let markedTextBackgroundColor: UIColor = .systemFill
        let markedTextBackgroundCornerRadius: CGFloat = 4

        func textColor(for rawHighlightName: String) -> UIColor? {
            guard let highlightName = HighlightName(rawHighlightName) else {
                return nil
            }
            switch highlightName {
            case .comment:
                return .secondaryLabel
            case .property:
                return .systemCyan
            case .string:
                return .systemGreen
            case .number:
                return .systemOrange
            case .constantBuiltin:
                return .systemPurple
            case .error:
                return .systemRed
            }
        }

        func fontTraits(for _: String) -> FontTraits {
            []
        }
    }

    private enum HighlightName: String {
        case comment
        case property
        case string
        case number
        case constantBuiltin = "constant.builtin"
        case error

        init?(_ rawHighlightName: String) {
            var components = rawHighlightName.split(separator: ".")
            while !components.isEmpty {
                let candidateRawHighlightName = components.joined(separator: ".")
                if let highlightName = Self(rawValue: candidateRawHighlightName) {
                    self = highlightName
                    return
                }
                components.removeLast()
            }
            return nil
        }
    }
#endif
