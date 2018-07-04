
class SnipetsContentStyles: FormattableContentStyles {
    var attributes: [NSAttributedStringKey: Any] {
        return WPStyleGuide.Notifications.snippetRegularStyle
    }

    var quoteStyles: [NSAttributedStringKey: Any]? = nil

    var rangeStylesMap: [FormattableContentRange.Kind: [NSAttributedStringKey: Any]]? = nil

    var linksColor: UIColor? = nil

    var key: String = "SnipetsContentStyles"
}
