import ComponentManifest
import Foundation

/// A part of a text file between two marker lines, which templatr owns.
struct MarkedSection {
    let begin: String
    let end: String

    /// The README's "How this project is built" section.
    static let readme = MarkedSection(begin: Validator.beginMarker, end: Validator.endMarker)
    /// The component conventions that CLAUDE.md imports.
    static let claude = MarkedSection(begin: "<!-- templatr:begin components -->", end: "<!-- templatr:end -->")

    /// `text` with `body` between the markers, and nothing else changed. When
    /// the markers are not there, in order, they are added at the end.
    func replace(in text: String, with body: String) -> String {
        if let begin = text.range(of: begin),
           let end = text.range(of: end, range: begin.upperBound..<text.endIndex) {
            return String(text[..<begin.upperBound]) + "\n" + body + String(text[end.lowerBound...])
        }
        var text = text
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        return text + begin + "\n" + body + end + "\n"
    }
}

enum Markdown {
    /// The link targets in Markdown text.
    static func links(in text: String) -> [String] {
        text.matches(of: /\]\(([^)\s]+)\)/).map { String($0.1) }
    }

    /// The README's "How this project is built" section, between its markers,
    /// written from the components' manifests.
    static func readmeSection(_ components: [ResolvedComponent], links: [Link]) -> String {
        var lines = [
            "<!-- templatr bootstrap writes this section from the components' manifests. Do not edit it. -->",
            "## How this project is built",
            "",
            "This project uses these components from [\(Templates.repository)](\(Templates.url)):",
            "",
        ]
        for resolved in components {
            let component = resolved.component
            lines.append("* [\(component.name)](\(component.link(tag: resolved.tag))) at `\(resolved.tag)`: \(component.manifest.description)")
        }

        var shared: [String] = []
        var seenShared: Set<String> = []
        for resolved in components {
            for piece in resolved.component.manifest.shared {
                let url = piece.repo == nil ? "\(Templates.url)/blob/\(resolved.tag)/\(piece.path)" : piece.link
                guard seenShared.insert(url).inserted else { continue }
                let name = piece.repo.map { "\($0): \(piece.path)" } ?? piece.path
                shared.append("* [\(name)](\(url)), \(piece.kind.rawValue): \(piece.description)")
            }
        }
        if !shared.isEmpty {
            lines += ["", "### Shared pieces", ""] + shared
        }

        var secrets: [String] = []
        var seenSecrets: Set<String> = []
        for resolved in components {
            let values = PlaceholderValues(inputs: resolved.values, templates: URL(fileURLWithPath: "/"), tag: resolved.tag)
            for declared in resolved.component.manifest.secrets where seenSecrets.insert(declared.name).inserted {
                let secret = declared.filled(values).secret
                var line = "* `\(secret.name)` (\(secret.scope.rawValue)): \(secret.description) \(origin(of: secret))"
                if let human = secret.human {
                    line += " To get it: \(values.render(human.text, quoted: false).text)"
                }
                secrets.append(line)
            }
        }
        if !secrets.isEmpty {
            lines += ["", "### Secrets", "", "Only their names are here, never their values.", ""] + secrets
        }

        var humanSteps: [String] = []
        for resolved in components {
            let values = PlaceholderValues(inputs: resolved.values, templates: URL(fileURLWithPath: "/"), tag: resolved.tag)
            for step in resolved.component.manifest.steps {
                guard case .human(let human) = step.fix else { continue }
                humanSteps.append("* \(step.description) If not: \(values.render(human.text, quoted: false).text)")
            }
        }
        if !humanSteps.isEmpty {
            lines += ["", "### Steps a person does", ""] + humanSteps
        }

        lines += ["", "### Further reading", ""]
        var seenLinks: Set<String> = []
        for link in Guide.sections + components.flatMap(\.component.guide) + links
        where seenLinks.insert(link.url).inserted {
            lines.append("* [\(link.title)](\(link.url))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func origin(of secret: Secret) -> String {
        switch secret.source {
        case .keychain(let item):
            secret.scope == .local
                ? "It stays in the Keychain item `\(item)`, and is never a GitHub secret."
                : "From the Keychain item `\(item)`."
        case .onePassword(let reference):
            "From 1Password, `\(reference)`."
        case .generate(let kind):
            "Generated (\(kind.rawValue)) and kept in the Keychain item `\(secret.keychainItem ?? "")`."
        }
    }

    /// The CLAUDE.md section that imports each component's conventions.
    static func claudeSection(_ components: [ResolvedComponent]) -> String {
        components.map { "@\(Bootstrapper.vendoredClaudePath($0.component.name))\n" }.joined()
    }
}
