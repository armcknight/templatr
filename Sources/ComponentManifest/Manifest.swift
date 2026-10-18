import Foundation
import TOMLKit

/// A component's `component.toml`. See README.md#the-manifest for the meaning
/// of each field, and schema/component.schema.json for the same format as a
/// JSON Schema, for editors.
///
/// Decoding is strict: an unknown key, an empty text, a value that does not
/// match its pattern, or an array with no elements is an error whose path in
/// the file is in its `DecodingError.Context`.
public struct Manifest: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var detect: Detect
    public var inputs: [Input]
    public var secrets: [Secret]
    public var steps: [Step]
    public var shared: [Shared]
    public var docs: [Doc]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, description, detect, inputs, secrets, steps, shared, docs
    }

    public init(
        name: String, description: String, detect: Detect, inputs: [Input], secrets: [Secret],
        steps: [Step], shared: [Shared], docs: [Doc]
    ) {
        self.name = name
        self.description = description
        self.detect = detect
        self.inputs = inputs
        self.secrets = secrets
        self.steps = steps
        self.shared = shared
        self.docs = docs
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectKeys(unknownTo: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.text(.name, .slug)
        description = try container.text(.description)
        detect = try container.decode(Detect.self, forKey: .detect)
        inputs = try container.decode([Input].self, forKey: .inputs)
        secrets = try container.decode([Secret].self, forKey: .secrets)
        steps = try container.decode([Step].self, forKey: .steps)
        shared = try container.decode([Shared].self, forKey: .shared)
        docs = try container.some(.docs, Doc.self)
    }

    /// Decodes a manifest from TOML text.
    /// - Throws: `ManifestError`, with the path of the problem in the file.
    public init(toml: String) throws {
        do {
            self = try TOMLDecoder().decode(Manifest.self, from: toml)
        } catch let error as TOMLParseError {
            throw ManifestError(path: nil, message: "\(error.description) \(error.source.debugDescription)")
        } catch let error as DecodingError {
            throw ManifestError(error)
        }
    }

    /// Decodes the manifest at `url`.
    /// - Throws: `ManifestError`, or the error reading the file.
    public init(contentsOf url: URL) throws {
        try self.init(toml: String(contentsOf: url, encoding: .utf8))
    }

    /// The manifest as TOML text.
    public func toml() throws -> String {
        try TOMLEncoder().encode(self)
    }
}

/// Why a manifest does not decode: where in the file, and what is wrong.
public struct ManifestError: Error, CustomStringConvertible, Equatable, Sendable {
    /// The path of the value, as `secrets/0/source`, or `(root)` for the whole
    /// table. `nil` when the file is not TOML at all.
    public var path: String?
    public var message: String

    public init(path: String?, message: String) {
        self.path = path
        self.message = message
    }

    init(_ error: DecodingError) {
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            self.init(path: context.pathDescription, message: context.debugDescription)
        case .keyNotFound(let key, let context):
            // TOMLKit puts the key on the path already; the parent table is the
            // place that needs it.
            var path = context.codingPath
            if path.last?.stringValue == key.stringValue { path.removeLast() }
            let parent = DecodingError.Context(codingPath: path, debugDescription: "").pathDescription
            self.init(path: parent, message: "'\(key.stringValue)' is required")
        @unknown default:
            self.init(path: nil, message: String(describing: error))
        }
    }

    public var description: String {
        path.map { "\($0): \(message)" } ?? message
    }
}

/// How to know, from its files only, that a repository uses the component:
/// every rule in `all` matches and, when `any` has rules, at least one of them.
public struct Detect: Codable, Equatable, Sendable {
    public var all: [DetectRule]?
    public var any: [DetectRule]?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case all, any
    }

    public init(all: [DetectRule]?, any: [DetectRule]?) {
        self.all = all
        self.any = any
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectKeys(unknownTo: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        all = try container.someIfPresent(.all, DetectRule.self)
        any = try container.someIfPresent(.any, DetectRule.self)
        if all == nil && any == nil {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath, debugDescription: "needs 'all' or 'any'"
            ))
        }
    }
}

/// A path glob, relative to the repository root, and a regular expression that
/// the contents of at least one matching file must match.
public struct DetectRule: Codable, Equatable, Sendable {
    public var glob: String
    public var contains: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case glob, contains
    }

    public init(glob: String, contains: String?) {
        self.glob = glob
        self.contains = contains
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectKeys(unknownTo: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        glob = try container.text(.glob)
        contains = try container.textIfPresent(.contains)
    }
}

/// A value that differs per project, and where to read it from the repository.
public struct Input: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var example: String
    /// The value to use when no `infer` rule finds one, instead of asking.
    public var defaultValue: String?
    /// Tried in order; the first value found is used. An input with no rules,
    /// or whose value is not found and has no default, is asked for one time.
    public var infer: [InferRule]?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, description, example
        case defaultValue = "default"
        case infer
    }

    public init(name: String, description: String, example: String, defaultValue: String?, infer: [InferRule]?) {
        self.name = name
        self.description = description
        self.example = example
        self.defaultValue = defaultValue
        self.infer = infer
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectKeys(unknownTo: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.text(.name, .identifier)
        description = try container.text(.description)
        example = try container.text(.example)
        defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
        infer = try container.someIfPresent(.infer, InferRule.self)
    }
}

/// Where to read an input's value: a source, and an optional `map` that
/// replaces the value found with the value of its key. A value that is not a
/// key of the map is not found.
public struct InferRule: Codable, Equatable, Sendable {
    public var from: From
    public var map: [String: String]?

    /// The sources, as `from` names them.
    public enum From: Equatable, Sendable {
        /// A build setting, as `xcodebuild -showBuildSettings` prints it for the
        /// project's scheme.
        case buildSetting(key: String)
        /// The first argument of a call in a fastlane configuration file, such
        /// as `team_id("…")` in fastlane/Appfile. An array's values are joined
        /// with commas.
        case fastlaneConfig(file: String, key: String)
        /// A value in a TOML file, by its dotted key path.
        case toml(file: String, key: String)
        /// A value in a YAML file, by its dotted key path. A list's values are
        /// joined with `separator`, a comma by default.
        case yaml(file: String, key: String, separator: String?)
        /// The path of the first file that matches the glob and, when
        /// `contains` is set, whose contents match it; its name without the
        /// directory and the extension when `stem` is set; or `true` and
        /// `false` when `exists` is set.
        case glob(glob: String, contains: String?, exists: Bool?, stem: Bool?)
        /// The first capture group of a regular expression in the first file
        /// that matches the glob.
        case regex(glob: String, pattern: String)

        public var source: Source {
            switch self {
            case .buildSetting: .buildSetting
            case .fastlaneConfig: .fastlaneConfig
            case .toml: .toml
            case .yaml: .yaml
            case .glob: .glob
            case .regex: .regex
            }
        }
    }

    /// The value of `from`.
    public enum Source: String, CaseIterable, Codable, Sendable {
        case buildSetting = "build-setting"
        case fastlaneConfig = "fastlane-config"
        case toml, yaml, glob, regex

        /// The keys a rule with this source can have, besides `from` and `map`.
        var keys: Set<String> {
            switch self {
            case .buildSetting: ["key"]
            case .fastlaneConfig: ["file", "key"]
            case .toml: ["file", "key"]
            case .yaml: ["file", "key", "separator"]
            case .glob: ["glob", "contains", "exists", "stem"]
            case .regex: ["glob", "pattern"]
            }
        }
    }

    /// Every key a rule can have, over all the sources.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case from, map, key, file, separator, glob, contains, exists, stem, pattern
    }

    /// The keys every rule can have.
    static let commonKeys: Set<String> = [CodingKeys.from.rawValue, CodingKeys.map.rawValue]

    public init(from: From, map: [String: String]?) {
        self.from = from
        self.map = map
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.value(.from, Source.self)
        try decoder.rejectKeys(outside: Self.commonKeys.union(source.keys), context: " for from = \"\(source.rawValue)\"")
        switch source {
        case .buildSetting:
            from = .buildSetting(key: try container.text(.key, .constant))
        case .fastlaneConfig:
            from = .fastlaneConfig(file: try container.text(.file), key: try container.text(.key, .fastlaneKey))
        case .toml:
            from = .toml(file: try container.text(.file), key: try container.text(.key))
        case .yaml:
            from = .yaml(
                file: try container.text(.file), key: try container.text(.key),
                separator: try container.textIfPresent(.separator)
            )
        case .glob:
            from = .glob(
                glob: try container.text(.glob), contains: try container.textIfPresent(.contains),
                exists: try container.decodeIfPresent(Bool.self, forKey: .exists),
                stem: try container.decodeIfPresent(Bool.self, forKey: .stem)
            )
        case .regex:
            from = .regex(glob: try container.text(.glob), pattern: try container.text(.pattern))
        }
        map = try container.decodeIfPresent([String: String].self, forKey: .map)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(from.source, forKey: .from)
        switch from {
        case .buildSetting(let key):
            try container.encode(key, forKey: .key)
        case .fastlaneConfig(let file, let key), .toml(let file, let key):
            try container.encode(file, forKey: .file)
            try container.encode(key, forKey: .key)
        case .yaml(let file, let key, let separator):
            try container.encode(file, forKey: .file)
            try container.encode(key, forKey: .key)
            try container.encodeIfPresent(separator, forKey: .separator)
        case .glob(let glob, let contains, let exists, let stem):
            try container.encode(glob, forKey: .glob)
            try container.encodeIfPresent(contains, forKey: .contains)
            try container.encodeIfPresent(exists, forKey: .exists)
            try container.encodeIfPresent(stem, forKey: .stem)
        case .regex(let glob, let pattern):
            try container.encode(glob, forKey: .glob)
            try container.encode(pattern, forKey: .pattern)
        }
        try container.encodeIfPresent(map, forKey: .map)
    }
}

/// A step a person must do. The text becomes a Needs human issue.
public struct Human: Codable, Equatable, Sendable {
    public var text: String
    /// True when the step needs a two-factor prompt, so it cannot be done
    /// unattended.
    public var twoFactor: Bool

    enum CodingKeys: String, CodingKey, CaseIterable {
        case text, twoFactor
    }

    public init(text: String, twoFactor: Bool) {
        self.text = text
        self.twoFactor = twoFactor
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectKeys(unknownTo: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.text(.text)
        twoFactor = try container.decodeIfPresent(Bool.self, forKey: .twoFactor) ?? false
    }
}

/// A secret the component needs, by name. Values are never in the manifest.
public struct Secret: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    /// Where bootstrap reads the value.
    public var source: Source
    public var scope: Scope
    /// What a person must do to get the value.
    public var human: Human?
    /// How often to make a new value.
    public var rotateEvery: RotationPeriod?

    /// A Keychain item, a 1Password reference, or a value bootstrap generates
    /// and stores in the Keychain.
    public enum Source: Equatable, Sendable, Codable {
        case keychain(item: String)
        /// The `op://<vault>/<item>/<field>` reference.
        case onePassword(reference: String)
        case generate(Generated)

        public enum Generated: String, CaseIterable, Sendable {
            case sshKey = "ssh-key"
            case password
            case hex32
        }

        /// The value as the manifest writes it, such as `keychain:demo.token`.
        public var rawValue: String {
            switch self {
            case .keychain(let item): "keychain:\(item)"
            case .onePassword(let reference): "1password:\(reference)"
            case .generate(let kind): "generate:\(kind.rawValue)"
            }
        }

        public init?(rawValue: String) {
            guard Format.secretSource.matches(rawValue) else { return nil }
            if let item = rawValue.removing(prefix: "keychain:") {
                self = .keychain(item: item)
            } else if let reference = rawValue.removing(prefix: "1password:") {
                self = .onePassword(reference: reference)
            } else if let kind = rawValue.removing(prefix: "generate:").flatMap(Generated.init(rawValue:)) {
                self = .generate(kind)
            } else {
                return nil
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let source = Source(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "'\(raw)' is not \(Format.secretSource.expectation)"
                )
            }
            self = source
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    /// `team`: one value for every project; `app`: one per app; `repo`: one per
    /// repository. Each of those is a GitHub Actions secret. `local`: one
    /// value, kept only in the owner's Keychain for commands run on their Mac,
    /// and never set as a GitHub secret.
    public enum Scope: String, CaseIterable, Codable, Sendable {
        case team, app, repo, local
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case name, description, source, scope, human, rotateEvery
    }

    public init(
        name: String, description: String, source: Source, scope: Scope, human: Human?,
        rotateEvery: RotationPeriod?
    ) {
        self.name = name
        self.description = description
        self.source = source
        self.scope = scope
        self.human = human
        self.rotateEvery = rotateEvery
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectKeys(unknownTo: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.text(.name, .constant)
        description = try container.text(.description)
        source = try container.decode(Source.self, forKey: .source)
        scope = try container.value(.scope, Scope.self)
        human = try container.decodeIfPresent(Human.self, forKey: .human)
        rotateEvery = try container.decodeIfPresent(RotationPeriod.self, forKey: .rotateEvery)
    }
}

/// How often to make a new value for a secret: a count of days, weeks, months
/// or years, written as `90d` or `1y`.
public struct RotationPeriod: Codable, Equatable, Sendable {
    public var count: Int
    public var unit: Unit

    public enum Unit: String, CaseIterable, Sendable {
        case days = "d"
        case weeks = "w"
        case months = "m"
        case years = "y"
    }

    public init(count: Int, unit: Unit) {
        self.count = count
        self.unit = unit
    }

    public var rawValue: String { "\(count)\(unit.rawValue)" }

    public init?(rawValue: String) {
        guard Format.rotationPeriod.matches(rawValue),
              let unit = rawValue.last.flatMap({ Unit(rawValue: String($0)) }),
              let count = Int(rawValue.dropLast())
        else { return nil }
        self.init(count: count, unit: unit)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let period = RotationPeriod(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "'\(raw)' is not \(Format.rotationPeriod.expectation)"
            )
        }
        self = period
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// A step of setting a project up. Its check runs; when it fails, its fix runs,
/// or becomes a Needs human issue.
public struct Step: Codable, Equatable, Sendable {
    public var id: String
    public var description: String
    /// `app`: done one time for each app; `repo`: one time for the repository.
    public var scope: Scope
    /// A shell command, run at the repository root. Exit status 0 means the step
    /// is done.
    public var check: String
    public var fix: Fix

    public enum Scope: String, CaseIterable, Codable, Sendable {
        case team, app, repo
    }

    /// A shell command that does the step, or a human step.
    public enum Fix: Equatable, Sendable, Codable {
        case command(String)
        case human(Human)

        enum CodingKeys: String, CodingKey, CaseIterable {
            case human
        }

        public init(from decoder: Decoder) throws {
            if let container = try? decoder.singleValueContainer(), let command = try? container.decode(String.self) {
                if command.isEmpty {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "is empty")
                }
                self = .command(command)
                return
            }
            try decoder.rejectKeys(unknownTo: CodingKeys.self)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self = .human(try container.decode(Human.self, forKey: .human))
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .command(let command):
                var container = encoder.singleValueContainer()
                try container.encode(command)
            case .human(let human):
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(human, forKey: .human)
            }
        }
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, description, scope, check, fix
    }

    public init(id: String, description: String, scope: Scope, check: String, fix: Fix) {
        self.id = id
        self.description = description
        self.scope = scope
        self.check = check
        self.fix = fix
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectKeys(unknownTo: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.text(.id, .slug)
        description = try container.text(.description)
        scope = try container.valueIfPresent(.scope, Scope.self) ?? .repo
        check = try container.text(.check)
        fix = try container.decode(Fix.self, forKey: .fix)
    }
}

/// A reusable piece that the component uses, in this repository or another.
public struct Shared: Codable, Equatable, Sendable {
    public var kind: Kind
    /// The GitHub repository that has the piece, as owner/name, when it is not
    /// this one.
    public var repo: String?
    /// The path in this repository, or in `repo`.
    public var path: String
    /// The first tag of this repository that has the piece in its current form;
    /// or, with `repo`, the tag of that repository that projects call it at,
    /// such as a major version tag.
    public var version: String
    public var description: String

    public enum Kind: String, CaseIterable, Codable, Sendable {
        case workflow, fastlane, make, brewfile, script
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, repo, path, version, description
    }

    public init(kind: Kind, repo: String?, path: String, version: String, description: String) {
        self.kind = kind
        self.repo = repo
        self.path = path
        self.version = version
        self.description = description
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectKeys(unknownTo: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.value(.kind, Kind.self)
        repo = try container.textIfPresent(.repo, .repository)
        path = try container.text(.path)
        version = try container.text(.version, repo == nil ? .localVersion : .externalVersion)
        description = try container.text(.description)
    }

    /// Where the piece is linked: its path for a piece in this repository, or
    /// `https://github.com/<repo>/blob/<version>/<path>` for one in another.
    public var link: String {
        repo.map { "https://github.com/\($0)/blob/\(version)/\(path)" } ?? path
    }
}

/// A section of the superlinear guide that explains the component.
public struct Doc: Codable, Equatable, Sendable {
    public var title: String
    /// An anchor that docs/anchors.md in the superlinear repository lists, as
    /// `<page>.md#<id>`.
    public var anchor: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case title, anchor
    }

    public init(title: String, anchor: String) {
        self.title = title
        self.anchor = anchor
    }

    public init(from decoder: Decoder) throws {
        try decoder.rejectKeys(unknownTo: CodingKeys.self)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.text(.title)
        anchor = try container.text(.anchor, .anchor)
    }
}

extension String {
    /// The rest of the string after `prefix`, when it starts with it.
    func removing(prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
