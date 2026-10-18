import Foundation
import TOMLKit
@testable import ComponentManifest

/// The `detect` and `infer` rules, as README.md#detect and README.md#inputs say
/// them, run on a repository's files. superlinear's bootstrap runs the rules
/// for real; this is a reference, to test the components' rules against
/// fixtures and against checkouts of the projects they come from.
///
/// It reads `glob`, `regex` and `toml` rules. `build-setting`,
/// `fastlane-config` and `yaml` rules find nothing here. A glob's `**` matches
/// any number of directories, and `.git`, `.build`, `.swiftpm`, `DerivedData`
/// and `node_modules` are not searched. A `regex` rule reads the first file
/// that matches the glob and that has the pattern.
struct Detection {
    let root: URL
    /// The repository root, which a rule with `root = true` reads.
    let repository: URL

    init(root: URL, repository: URL? = nil) {
        self.root = root
        self.repository = repository ?? root
    }

    /// The files a rule reads.
    func reading(root: Bool) -> Detection {
        root ? Detection(root: repository) : self
    }

    static let skippedDirectories: Set<String> = [".git", ".build", ".swiftpm", "DerivedData", "node_modules"]

    /// The rules of a component with a `directory` read the files there.
    func scoped(to manifest: Manifest) -> Detection {
        manifest.directory.map { Detection(root: root.appending(path: $0), repository: root) } ?? self
    }

    /// Whether the repository uses the component. A base component has no
    /// rules: it comes with the others.
    func detects(_ manifest: Manifest) -> Bool {
        guard let detect = manifest.detect else { return false }
        let scoped = scoped(to: manifest)
        let all = detect.all ?? []
        let any = detect.any ?? []
        return all.allSatisfy(scoped.matches) && (any.isEmpty || any.contains(where: scoped.matches))
    }

    /// Each input's value: the first one an `infer` rule finds, else its
    /// default, else `nil`, which bootstrap asks for.
    func inputs(of manifest: Manifest) -> [String: String?] {
        let scoped = scoped(to: manifest)
        return Dictionary(uniqueKeysWithValues: manifest.inputs.map { ($0.name, scoped.value(of: $0)) })
    }

    func value(of input: Input) -> String? {
        for rule in input.infer ?? [] {
            guard var found = reading(root: rule.root).value(rule.from) else { continue }
            if let map = rule.map {
                guard let mapped = map[found] else { continue }
                found = mapped
            }
            return found
        }
        return input.defaultValue
    }

    func value(_ from: InferRule.From) -> String? {
        switch from {
        case .toml(let file, let key):
            guard let text = read(file), let table = try? TOMLTable(string: text) else { return nil }
            var value: TOMLValueConvertible? = table
            for part in key.split(separator: ".") {
                value = value?.table?[String(part)]
            }
            return value.flatMap(Self.text)
        case .glob(let glob, let contains, let exists, let stem):
            let found = files(matching: glob, contains: contains).first?.path
            if exists == true { return found == nil ? "false" : "true" }
            if stem == true { return found.map { ((($0 as NSString).lastPathComponent) as NSString).deletingPathExtension } }
            return found
        case .regex(let glob, let pattern):
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            for file in files(matching: glob, contains: nil) {
                let text = file.text ?? ""
                if let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                   let range = Range(match.range(at: 1), in: text) {
                    return String(text[range])
                }
            }
            return nil
        case .buildSetting, .fastlaneConfig, .yaml:
            return nil
        }
    }

    func matches(_ rule: DetectRule) -> Bool {
        !reading(root: rule.root).files(matching: rule.glob, contains: rule.contains).isEmpty
    }

    /// The paths that match the glob and, with `contains`, the files whose
    /// contents match it, in order. `text` is `nil` for a directory.
    func files(matching glob: String, contains: String?) -> [(path: String, text: String?)] {
        let regex = contains.flatMap { try? NSRegularExpression(pattern: $0) }
        return paths(matching: glob).compactMap { path in
            let text = read(path)
            guard let regex else { return (path, text) }
            guard let text, regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else {
                return nil
            }
            return (path, text)
        }
    }

    /// The paths, relative to the root, of the files and directories that match
    /// the glob, sorted.
    func paths(matching glob: String) -> [String] {
        if !glob.contains(where: { "*?[".contains($0) }) {
            return FileManager.default.fileExists(atPath: root.appending(path: glob).path) ? [glob] : []
        }
        guard let regex = try? NSRegularExpression(pattern: Self.regex(forGlob: glob)),
              let enumerator = FileManager.default.enumerator(atPath: root.path)
        else { return [] }
        var found: [String] = []
        while let path = enumerator.nextObject() as? String {
            let isDirectory = enumerator.fileAttributes?[.type] as? FileAttributeType == .typeDirectory
            if isDirectory && Self.skippedDirectories.contains((path as NSString).lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil {
                found.append(path)
            }
        }
        return found.sorted()
    }

    /// A regular expression for a glob: `**` is any number of directories, and
    /// `*`, `?` and `[…]` do not cross a directory.
    static func regex(forGlob glob: String) -> String {
        let segments = glob.split(separator: "/", omittingEmptySubsequences: false)
        var pattern = "^"
        for (index, segment) in segments.enumerated() {
            let last = index == segments.count - 1
            if segment == "**" {
                pattern += last ? ".*" : "(?:.*/)?"
                continue
            }
            var characters = segment[...]
            while let character = characters.popFirst() {
                switch character {
                case "*": pattern += "[^/]*"
                case "?": pattern += "[^/]"
                case "[":
                    if let end = characters.firstIndex(of: "]") {
                        var body = String(characters[..<end])
                        if body.hasPrefix("!") { body = "^" + body.dropFirst() }
                        pattern += "[\(body)]"
                        characters = characters[characters.index(after: end)...]
                    } else {
                        pattern += "\\["
                    }
                default: pattern += NSRegularExpression.escapedPattern(for: String(character))
                }
            }
            if !last { pattern += "/" }
        }
        return pattern + "$"
    }

    private func read(_ path: String) -> String? {
        let url = root.appending(path: path)
        guard url.isFile, let data = try? Data(contentsOf: url) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func text(_ value: TOMLValueConvertible) -> String? {
        if let string = value.string { return string }
        if let int = value.int { return String(int) }
        if let bool = value.bool { return bool ? "true" : "false" }
        if let double = value.double { return String(double) }
        if let array = value.array { return array.compactMap(text).joined(separator: ",") }
        return nil
    }
}
