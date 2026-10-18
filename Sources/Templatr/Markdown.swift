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

    /// A component's blurb in the root README.md.
    static func component(_ name: String) -> MarkedSection {
        MarkedSection(begin: "<!-- templatr:begin \(name) -->", end: "<!-- templatr:end -->")
    }

    /// `text` with `body` between the markers, and nothing else changed. When
    /// the markers are not there, in order, they are added before the line
    /// that has `before`, or at the end.
    func replace(in text: String, with body: String, before: String? = nil) -> String {
        if let begin = text.range(of: begin),
           let end = text.range(of: end, range: begin.upperBound..<text.endIndex) {
            return String(text[..<begin.upperBound]) + "\n" + body + String(text[end.lowerBound...])
        }
        if let before, let found = text.range(of: before) {
            let line = text[..<found.lowerBound].lastIndex(of: "\n").map { text.index(after: $0) } ?? text.startIndex
            return String(text[..<line]) + begin + "\n" + body + end + "\n\n" + String(text[line...])
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
            let place = resolved.directory.map { ", in `\($0)/`" } ?? ""
            lines.append(
                "* [\(component.name)](\(component.link(tag: resolved.tag))) at `\(resolved.tag)`\(place): \(component.manifest.description)"
            )
        }

        var shared: [String] = []
        var seenShared: Set<String> = []
        for resolved in components {
            for piece in resolved.component.manifest.shared {
                let path = piece.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? piece.path
                let url = piece.repo == nil ? "\(Templates.url)/blob/\(resolved.tag)/\(path)" : piece.link
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
            let values = resolved.placeholders(templates: URL(fileURLWithPath: "/"))
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
            let values = resolved.placeholders(templates: URL(fileURLWithPath: "/"))
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

    /// The component's blurb for the root README.md, with a link to the
    /// README.md in its directory, or `nil` when it has none.
    static func blurb(_ resolved: ResolvedComponent) -> String? {
        guard let blurb = resolved.component.manifest.blurb else { return nil }
        let values = resolved.placeholders(templates: URL(fileURLWithPath: "/"))
        let text = values.render(blurb, quoted: false).text
        guard let directory = resolved.directory else { return text + "\n" }
        return "[\(directory)/](\(directory)/README.md): \(text)\n"
    }

    /// The CLAUDE.md section that imports each component's conventions.
    static func claudeSection(_ components: [ResolvedComponent]) -> String {
        components.map { "@\(Bootstrapper.vendoredClaudePath($0.component.name))\n" }.joined()
    }
}
