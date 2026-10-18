import Foundation

/// Checks every component in a checkout of this repository: each manifest
/// decodes, and what the format alone cannot say holds.
public struct Validator: Sendable {
    /// The repository root.
    public var root: URL
    /// The anchors superlinear's docs/anchors.md lists, or `nil` to skip that
    /// check.
    public var anchors: Set<String>?

    public static let beginMarker = "<!-- superlinear:begin how-this-is-built -->"
    public static let endMarker = "<!-- superlinear:end -->"

    public init(root: URL, anchors: Set<String>?) {
        self.root = root.standardizedFileURL
        self.anchors = anchors
    }

    /// Every problem, in the order found. The repository is valid when there
    /// are none.
    public func problems() -> [String] {
        var problems: [String] = []
        var manifests: [(name: String, manifest: Manifest)] = []

        let components = root.appending(path: "components")
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: components, includingPropertiesForKeys: [.isDirectoryKey], options: []
        ))?.filter(\.isDirectory).sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        if directories.isEmpty {
            problems.append("components/: there are no components")
        }
        for directory in directories {
            guard directory.appending(path: "component.toml").isFile else {
                problems.append("\(relative(directory)): component.toml is missing")
                continue
            }
            let (componentProblems, manifest) = validateComponent(in: directory)
            problems += componentProblems
            if let manifest {
                manifests.append((directory.lastPathComponent, manifest))
            }
        }

        problems += layoutProblems(manifests)

        let readme = root.appending(path: "README.md")
        if let text = try? String(contentsOf: readme, encoding: .utf8) {
            let links = Set(Self.links(in: text))
            for (name, manifest) in manifests {
                if !links.contains("components/\(name)") {
                    problems.append("README.md: does not link to components/\(name)")
                }
                for item in manifest.shared where !links.contains(item.link) {
                    problems.append("README.md: does not link to the shared \(item.kind.rawValue) \(item.link)")
                }
            }
        } else {
            problems.append("README.md is missing")
        }

        return problems
    }

    /// The component's problems, and its manifest when it decodes.
    func validateComponent(in directory: URL) -> ([String], Manifest?) {
        var problems: [String] = []
        let manifestURL = directory.appending(path: "component.toml")
        let `where` = relative(manifestURL)
        let component = relative(directory)

        let manifest: Manifest
        do {
            manifest = try Manifest(contentsOf: manifestURL)
        } catch {
            return (["\(`where`): \(error)"], nil)
        }

        if manifest.name != directory.lastPathComponent {
            problems.append(
                "\(`where`): name '\(manifest.name)' is not the directory's name '\(directory.lastPathComponent)'"
            )
        }

        for (kind, values) in [
            ("input", manifest.inputs.map(\.name)),
            ("secret", manifest.secrets.map(\.name)),
            ("step", manifest.steps.map(\.id)),
        ] {
            for value in Self.duplicates(in: values) {
                problems.append("\(`where`): \(kind) '\(value)' is declared more than one time")
            }
        }

        for secret in manifest.secrets where secret.scope == .local {
            if case .keychain = secret.source { continue }
            problems.append("\(`where`): secret \(secret.name) is local, so its source must be a keychain: item")
        }

        for (group, rules) in [("all", manifest.detect?.all), ("any", manifest.detect?.any)] {
            for (index, rule) in (rules ?? []).enumerated() {
                if let contains = rule.contains {
                    problems += Self.regexProblems(at: "\(`where`): detect.\(group)[\(index)]", pattern: contains, needsGroup: false)
                }
            }
        }
        for input in manifest.inputs {
            for (index, rule) in (input.infer ?? []).enumerated() {
                let label = "\(`where`): input \(input.name) infer[\(index)]"
                switch rule.from {
                case .regex(_, let pattern):
                    problems += Self.regexProblems(at: label, pattern: pattern, needsGroup: true)
                case .glob(_, let contains, let exists, let stem):
                    if let contains {
                        problems += Self.regexProblems(at: label, pattern: contains, needsGroup: false)
                    }
                    if exists == true && stem == true {
                        problems.append("\(label): exists and stem cannot both be true")
                    }
                default:
                    break
                }
            }
        }

        if !directory.appending(path: "CLAUDE.md").isFile {
            problems.append("\(component): CLAUDE.md is missing")
        }

        let scaffold = directory.appending(path: "scaffold")
        if manifest.base {
            // The root README.md, with the project-wide section.
            let readme = scaffold.appending(path: "README.md")
            if let text = try? String(contentsOf: readme, encoding: .utf8) {
                if !Self.hasMarkers(text) {
                    problems.append(
                        "\(relative(readme)): needs \(Self.beginMarker) and then \(Self.endMarker), one time each"
                    )
                }
            } else {
                problems.append("\(component): scaffold/README.md is missing")
            }
        } else if let subdirectory = manifest.directory {
            // The component's own README.md. The project-wide section is in the
            // base component's root README.md only.
            let readme = scaffold.appending(path: "\(subdirectory)/README.md")
            if let text = try? String(contentsOf: readme, encoding: .utf8) {
                if text.contains(Self.beginMarker) || text.contains(Self.endMarker) {
                    problems.append(
                        "\(relative(readme)): has the how-this-is-built markers, which only the base component's README.md has"
                    )
                }
            } else {
                problems.append("\(component): scaffold/\(subdirectory)/README.md is missing")
            }
        }
        if !manifest.base {
            let workflows = ".github/workflows/\(manifest.name)-"
            let inside = manifest.directory.map { "\($0)/" }
            for path in Self.scaffoldPaths(in: scaffold) {
                if path.hasPrefix(workflows) || inside.map(path.hasPrefix) == true { continue }
                let allowed = inside.map { "under \($0) or " } ?? ""
                problems.append(
                    "\(component)/scaffold/\(path): must be \(allowed)a workflow named \(workflows)*, so that no other component has it"
                )
            }
        }

        let allowed = Placeholders.builtin.union(manifest.inputs.map { "inputs.\($0.name)" })
        var sources: [(label: String, text: String)] = []
        for file in textFiles(under: scaffold) {
            sources.append((relative(file.url), file.text))
        }
        for step in manifest.steps {
            sources.append(("\(`where`): step \(step.id) check", step.check))
            if case .command(let fix) = step.fix {
                sources.append(("\(`where`): step \(step.id) fix", fix))
            }
        }
        for secret in manifest.secrets {
            sources.append(("\(`where`): secret \(secret.name) source", secret.source.rawValue))
            if let human = secret.human {
                sources.append(("\(`where`): secret \(secret.name)", human.text))
            }
        }
        for step in manifest.steps {
            if case .human(let human) = step.fix {
                sources.append(("\(`where`): step \(step.id) fix", human.text))
            }
        }
        if let blurb = manifest.blurb {
            sources.append(("\(`where`): blurb", blurb))
        }
        for (label, text) in sources {
            for name in Placeholders.names(in: text).subtracting(allowed).sorted() {
                problems.append("\(label): unknown placeholder {{\(name)}}")
            }
        }

        for item in manifest.shared where item.repo == nil {
            if !FileManager.default.fileExists(atPath: root.appending(path: item.path).path) {
                problems.append("\(`where`): shared path '\(item.path)' does not exist")
            }
        }

        if let anchors {
            for doc in manifest.docs where !anchors.contains(doc.anchor) {
                problems.append("\(`where`): docs anchor '\(doc.anchor)' is not listed in docs/anchors.md")
            }
        }

        return (problems, manifest)
    }

    /// What two components' layouts would make collide in a project: a second
    /// base component, two components in one directory, and a scaffold path
    /// that two components have.
    func layoutProblems(_ manifests: [(name: String, manifest: Manifest)]) -> [String] {
        var problems: [String] = []
        let bases = manifests.filter(\.manifest.base).map(\.name)
        if bases.count > 1 {
            problems.append("components/: \(bases.joined(separator: ", ")) are base components; there can be one")
        }
        var directories: [String: String] = [:]
        for (name, manifest) in manifests {
            guard let directory = manifest.directory else { continue }
            if let other = directories[directory] {
                problems.append("components/\(name)/component.toml: directory '\(directory)' is also \(other)'s")
            } else {
                directories[directory] = name
            }
        }
        var owners: [String: String] = [:]
        for (name, _) in manifests {
            let scaffold = root.appending(path: "components/\(name)/scaffold")
            for path in Self.scaffoldPaths(in: scaffold) {
                if let other = owners[path] {
                    problems.append("components/\(name)/scaffold/\(path): \(other)'s scaffold has it too")
                } else {
                    owners[path] = name
                }
                if let first = path.split(separator: "/").first.map(String.init), path.contains("/"),
                   let owner = directories[first], owner != name {
                    problems.append("components/\(name)/scaffold/\(path): is in \(owner)'s directory")
                }
            }
        }
        return problems
    }

    /// The paths of the files in a scaffold, relative to it, sorted.
    public static func scaffoldPaths(in scaffold: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: scaffold.path) else { return [] }
        var paths: [String] = []
        while let path = enumerator.nextObject() as? String {
            if enumerator.fileAttributes?[.type] as? FileAttributeType == .typeRegular {
                paths.append(path)
            }
        }
        return paths.sorted()
    }

    /// The scaffold's README has the generated section's markers, one time each
    /// and in order.
    static func hasMarkers(_ text: String) -> Bool {
        let begins = text.ranges(of: beginMarker)
        let ends = text.ranges(of: endMarker)
        guard let begin = begins.first, let end = ends.first else { return false }
        return begins.count == 1 && ends.count == 1 && begin.lowerBound < end.lowerBound
    }

    /// The link targets in Markdown text, without a leading `./` or a trailing
    /// `/`.
    static func links(in markdown: String) -> [String] {
        markdown.matches(of: /\]\(([^)\s]+)\)/).map { match in
            var link = String(match.1)
            if link.hasPrefix("./") { link.removeFirst(2) }
            while link.hasSuffix("/") { link.removeLast() }
            return link
        }
    }

    /// The values that appear more than one time, each one time, in order.
    static func duplicates(in values: [String]) -> [String] {
        var seen: Set<String> = []
        var repeated: [String] = []
        for value in values {
            if seen.contains(value) && !repeated.contains(value) {
                repeated.append(value)
            }
            seen.insert(value)
        }
        return repeated
    }

    /// Why `pattern` is not a regular expression that the component can use.
    static func regexProblems(at label: String, pattern: String, needsGroup: Bool) -> [String] {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            return ["\(label): invalid regular expression '\(pattern)': \(error.localizedDescription)"]
        }
        if needsGroup && regex.numberOfCaptureGroups < 1 {
            return ["\(label): '\(pattern)' has no capture group"]
        }
        return []
    }

    /// Every file under `directory` that is UTF-8 text, sorted by path.
    private func textFiles(under directory: URL) -> [(url: URL, text: String)] {
        guard directory.isDirectory,
              let enumerator = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: []
              )
        else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator where url.isFile {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }.compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).map { (url, $0) }
        }
    }

    /// `url` relative to the root, as the problems print it.
    private func relative(_ url: URL) -> String {
        let prefix = root.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }
}

extension URL {
    var isFile: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    var isDirectory: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
