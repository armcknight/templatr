import ComponentManifest
import Foundation

/// The values of a component's placeholders in one project.
struct PlaceholderValues {
    /// By placeholder name: `inputs.<name>`, `templates`, `templates.tag` and
    /// `directory`.
    var values: [String: String]

    init(inputs: [String: String], templates: URL, tag: String, directory: String? = nil) {
        values = ["templates": templates.path, "templates.tag": tag]
        if let directory {
            values[Placeholders.directory] = directory
        }
        for (name, value) in inputs {
            values["inputs.\(name)"] = value
        }
    }

    /// `text` with each `{{name}}` replaced by its value, quoted for the shell
    /// when `quoted`. Placeholders with no value stay as they are, and are
    /// returned in `missing`. `${{ … }}` is a GitHub Actions expression and
    /// stays.
    func render(_ text: String, quoted: Bool) -> (text: String, missing: [String]) {
        var result = ""
        var missing: [String] = []
        var rest = text[...]
        for match in text.matches(of: /(\$?)\{\{\s*([^{}]*?)\s*\}\}/) {
            result += text[rest.startIndex..<match.range.lowerBound]
            rest = text[match.range.upperBound...]
            let name = String(match.2)
            if match.1.isEmpty, let value = values[name] {
                // `{{templates}}` is a path, quoted too, so it may have spaces.
                result += quoted ? Shell.quote(value) : value
            } else {
                if match.1.isEmpty && !missing.contains(name) { missing.append(name) }
                result += text[match.range]
            }
        }
        return (result + rest, missing)
    }
}
