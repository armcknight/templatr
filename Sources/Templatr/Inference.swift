import ComponentManifest
import Foundation
import TOMLKit
import Yams

/// The files a component's rules read: those in its directory, and those of
/// the whole repository for a rule with `root = true`.
struct ComponentFiles {
    let own: RepositoryFiles
    let repository: RepositoryFiles

    func files(root: Bool) -> RepositoryFiles {
        root ? repository : own
    }
}

extension Detect {
    /// Every rule in `all` matches and, when `any` has rules, at least one of
    /// them does.
    func matches(_ files: ComponentFiles) -> Bool {
        (all ?? []).allSatisfy { $0.matches(files) } && (any.map { $0.contains { $0.matches(files) } } ?? true)
    }
}

extension DetectRule {
    func matches(_ files: ComponentFiles) -> Bool {
        let files = files.files(root: root)
        guard let contains else { return !files.matching(glob).isEmpty }
        return files.files(matching: glob).contains { path in
            files.text(of: path).map { Patterns.matches(contains, $0) } ?? false
        }
    }
}

/// Reads the build settings of a project's app target.
public protocol BuildSettingsProvider: Sendable {
    /// The settings of the app target that `scheme` builds, in the Release
    /// configuration when the project has one, or `nil` when they cannot be
    /// read. `project`, `workspace` and `scheme` are relative to the
    /// repository, and `nil` when not known.
    func buildSettings(repository: URL, project: String?, workspace: String?, scheme: String?) -> [String: String]?
}

/// Build settings from `xcodebuild -showBuildSettings -json`.
public struct XcodeBuildSettings: BuildSettingsProvider {
    public var runner: any CommandRunner

    public init(runner: any CommandRunner) {
        self.runner = runner
    }

    public func buildSettings(repository: URL, project: String?, workspace: String?, scheme: String?) -> [String: String]? {
        var arguments = ["xcodebuild", "-showBuildSettings", "-json"]
        if let workspace {
            arguments += ["-workspace", workspace]
        } else if let project {
            arguments += ["-project", project]
        }
        if let scheme {
            arguments += ["-scheme", scheme]
        }
        // The release product name is the one in App Store Connect; a debug
        // configuration's can name a development variant.
        guard let targets = targets(arguments + ["-configuration", "Release"], in: repository)
            ?? targets(arguments, in: repository)
        else { return nil }
        let app = targets.first { $0.buildSettings["WRAPPER_EXTENSION"] == "app" } ?? targets.first
        return app?.buildSettings
    }

    private func targets(_ arguments: [String], in repository: URL) -> [Target]? {
        guard let result = try? runner.run(arguments, input: nil, in: repository), result.succeeded else { return nil }
        return try? JSONDecoder().decode([Target].self, from: result.output)
    }

    private struct Target: Decodable {
        var buildSettings: [String: String]
    }
}

/// Finds inputs' values in a repository.
struct Inferrer {
    let files: ComponentFiles
    let buildSettings: any BuildSettingsProvider

    /// The values that the `infer` rules find for `inputs`, by name. `known`
    /// values, such as recorded ones, are not looked for, but name the Xcode
    /// project and scheme for build settings.
    func infer(_ inputs: [Input], known: [String: String]) -> [String: String] {
        var found: [String: String] = [:]
        let unknown = inputs.filter { known[$0.name] == nil }
        // Rules that do not need build settings go first, so that the project,
        // workspace and scheme are known when xcodebuild runs.
        let needsSettings: (Input) -> Bool = { input in
            input.infer?.contains { if case .buildSetting = $0.from { true } else { false } } ?? false
        }
        for input in unknown where !needsSettings(input) {
            found[input.name] = value(of: input, settings: nil)
        }
        let later = unknown.filter(needsSettings)
        guard !later.isEmpty else { return found }
        let names = known.merging(found) { $1 }
        let nonEmpty: (String) -> String? = { names[$0].flatMap { $0.isEmpty ? nil : $0 } }
        let settings = buildSettings.buildSettings(
            repository: files.own.root, project: nonEmpty("project"), workspace: nonEmpty("workspace"), scheme: nonEmpty("scheme")
        )
        for input in later {
            found[input.name] = value(of: input, settings: settings)
        }
        return found
    }

    private func value(of input: Input, settings: [String: String]?) -> String? {
        for rule in input.infer ?? [] {
            guard var value = value(of: rule.from, in: files.files(root: rule.root), settings: settings) else { continue }
            if case .buildSetting(_, let separator?) = rule.from {
                guard let list = Self.list(value, map: rule.map) else { continue }
                return list.joined(separator: separator)
            }
            if let map = rule.map {
                guard let mapped = map[value] else { continue }
                value = mapped
            }
            return value
        }
        return nil
    }

    private func value(of source: InferRule.From, in files: RepositoryFiles, settings: [String: String]?) -> String? {
        switch source {
        case .buildSetting(let key, _):
            return settings?[key]
        case .fastlaneConfig(let file, let key):
            return files.text(of: file).flatMap { Self.fastlaneArgument(key, in: $0) }
        case .toml(let file, let key):
            guard let text = files.text(of: file), let table = try? TOMLTable(string: text) else { return nil }
            return Self.tomlValue(table, at: key)
        case .yaml(let file, let key, let separator):
            guard let text = files.text(of: file), let document = try? Yams.load(yaml: text) else { return nil }
            return Self.yamlValue(document, at: key, separator: separator ?? ",")
        case .glob(let glob, let contains, let exists, let stem):
            let matches = contains == nil
                ? files.matching(glob)
                : files.files(matching: glob).filter { path in
                    files.text(of: path).map { Patterns.matches(contains!, $0) } ?? false
                }
            if exists == true { return matches.isEmpty ? "false" : "true" }
            if stem == true { return matches.first.map(Self.stem) }
            return matches.first
        case .regex(let glob, let pattern):
            for path in files.files(matching: glob) {
                if let text = files.text(of: path), let value = Patterns.firstGroup(pattern, in: text) {
                    return value
                }
            }
            return nil
        }
    }

    /// The name of the file at `path`, without its directory and extension.
    static func stem(_ path: String) -> String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// The first argument of the call `key` in a fastlane configuration file:
    /// a string, or an array of strings joined with commas.
    static func fastlaneArgument(_ key: String, in text: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let string = #""([^"]*)"|'([^']*)'"#
        let call = "(?m)^[ \\t]*\(escaped)[ \\t]*\\(?[ \\t]*"
        if let match = Patterns.firstMatch(call + "\\[([^\\]]*)\\]", in: text),
           let range = Range(match.range(at: 1), in: text) {
            let elements = String(text[range]).matches(of: /"([^"]*)"|'([^']*)'/).map { String($0.1 ?? $0.2 ?? "") }
            return elements.isEmpty ? nil : elements.joined(separator: ",")
        }
        guard let match = Patterns.firstMatch(call + "(?:\(string))", in: text) else { return nil }
        for group in 1...2 {
            if let range = Range(match.range(at: group), in: text) { return String(text[range]) }
        }
        return nil
    }

    static func tomlValue(_ table: TOMLTable, at key: String) -> String? {
        var value: (any TOMLValueConvertible)? = table
        for part in key.split(separator: ".") {
            value = value?.table?[String(part)]
        }
        guard let value else { return nil }
        if let array = value.array {
            return array.compactMap { scalar($0) }.joined(separator: ",")
        }
        return scalar(value)
    }

    private static func scalar(_ value: any TOMLValueConvertible) -> String? {
        if let string = value.string { return string }
        if let bool = value.bool { return String(bool) }
        if let int = value.int { return String(int) }
        if let double = value.double { return String(double) }
        return nil
    }

    /// The words of a list separated by white space, each replaced by its value
    /// in `map`, with no value twice. Nil when the list is empty or a word is
    /// not a key of `map`.
    static func list(_ value: String, map: [String: String]?) -> [String]? {
        var values: [String] = []
        for word in value.split(whereSeparator: \.isWhitespace).map(String.init) {
            guard let mapped = map.map({ $0[word] }) ?? word else { return nil }
            if !values.contains(mapped) { values.append(mapped) }
        }
        return values.isEmpty ? nil : values
    }

    static func yamlValue(_ document: Any, at key: String, separator: String) -> String? {
        var value: Any? = document
        for part in key.split(separator: ".") {
            value = (value as? [String: Any])?[String(part)]
        }
        switch value {
        case let list as [Any]:
            return list.map { "\($0)" }.joined(separator: separator)
        case let string as String:
            return string
        case let other?:
            return other is [String: Any] ? nil : "\(other)"
        case nil:
            return nil
        }
    }
}
