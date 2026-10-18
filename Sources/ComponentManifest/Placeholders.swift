import Foundation

/// `{{name}}` in scaffold files, step commands, certificates' `list` commands,
/// secrets' sources and human texts. GitHub Actions' `${{ expression }}` is not
/// one.
public enum Placeholders {
    /// The placeholders every component can use, besides `inputs.<name>`:
    /// `templates`, the path of a checkout of this repository at the project's
    /// tag, and `templates.tag`, that tag.
    public static let builtin: Set<String> = ["templates", "templates.tag"]

    /// The names in each `{{…}}` in `text`, trimmed.
    public static func names(in text: String) -> Set<String> {
        // A `$` before the braces makes it a GitHub Actions expression.
        Set(text.matches(of: /(\$?)\{\{\s*([^{}]*?)\s*\}\}/).filter { $0.1.isEmpty }.map { String($0.2) })
    }
}
