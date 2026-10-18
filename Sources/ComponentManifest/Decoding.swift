import Foundation

/// A key with any name, to see which keys a table has.
struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// A constraint on a string value: the schema's `pattern`, and what a value
/// that does not match it is told.
struct Format: Sendable {
    let pattern: String
    let expectation: String

    func matches(_ value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    /// A component's name or a step's ID.
    static let slug = Format(
        pattern: "^[a-z][a-z0-9]*(-[a-z0-9]+)*$",
        expectation: "lowercase words separated by hyphens, such as apple-app"
    )
    /// An input's name.
    static let identifier = Format(
        pattern: "^[a-z][a-z0-9_]*$",
        expectation: "a lowercase identifier, such as bundle_id"
    )
    /// A secret's name or a build setting's key.
    static let constant = Format(
        pattern: "^[A-Z][A-Z0-9_]*$",
        expectation: "an uppercase identifier, such as MATCH_PASSWORD"
    )
    /// A fastlane configuration call's name.
    static let fastlaneKey = Format(
        pattern: "^[a-z][a-z0-9_]*$",
        expectation: "a lowercase identifier, such as team_id"
    )
    static let secretSource = Format(
        pattern: "^(keychain:.+|1password:op://.+|generate:(ssh-key|password|hex32))$",
        expectation: "keychain:<item>, 1password:op://<vault>/<item>/<field> or generate:<ssh-key|password|hex32>"
    )
    static let rotationPeriod = Format(
        pattern: "^[1-9][0-9]*[dwmy]$",
        expectation: "a number of days, weeks, months or years, such as 90d or 1y"
    )
    static let repository = Format(
        pattern: "^[A-Za-z0-9-]+/[A-Za-z0-9._-]+$",
        expectation: "a GitHub repository, as owner/name"
    )
    /// The version of a shared piece in this repository.
    static let localVersion = Format(
        pattern: "^v[1-9][0-9]*(\\.[0-9]+)?$",
        expectation: "a tag of this repository, such as v1 or v1.1"
    )
    /// The version of a shared piece in another repository.
    static let externalVersion = Format(
        pattern: "^v?[0-9]+(\\.[0-9]+){0,2}$",
        expectation: "the tag of that repository that projects call it at, such as 4 or v1.2.3"
    )
    static let anchor = Format(
        pattern: "^[a-z][a-z0-9-]*\\.md#[a-z0-9][a-z0-9-]*$",
        expectation: "<page>.md#<id>, such as builds.md#ci"
    )
}

extension Decoder {
    /// Throws when the table has a key that `Key` does not name.
    func rejectKeys<Key: CodingKey & CaseIterable>(unknownTo keys: Key.Type) throws {
        try rejectKeys(outside: Set(Key.allCases.map(\.stringValue)), context: "")
    }

    /// Throws when the table has a key that is not in `known`.
    func rejectKeys(outside known: Set<String>, context: String) throws {
        let container = try self.container(keyedBy: AnyKey.self)
        let unknown = container.allKeys.map(\.stringValue).filter { !known.contains($0) }.sorted()
        guard let first = unknown.first else { return }
        let names = known.sorted().joined(separator: ", ")
        throw DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: codingPath,
            debugDescription: "'\(first)' was unexpected\(context); the keys are \(names)"
        ))
    }
}

extension KeyedDecodingContainer {
    /// A string that is not empty.
    func text(_ key: Key) throws -> String {
        let value = try decode(String.self, forKey: key)
        try requireNotEmpty(value, at: key)
        return value
    }

    /// A string that matches `format`.
    func text(_ key: Key, _ format: Format) throws -> String {
        let value = try decode(String.self, forKey: key)
        try require(value, matches: format, at: key)
        return value
    }

    /// A string that is not empty, when the key is present.
    func textIfPresent(_ key: Key) throws -> String? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else { return nil }
        try requireNotEmpty(value, at: key)
        return value
    }

    /// A string that matches `format`, when the key is present.
    func textIfPresent(_ key: Key, _ format: Format) throws -> String? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else { return nil }
        try require(value, matches: format, at: key)
        return value
    }

    /// A string that is one of an enumeration's values.
    func value<T: RawRepresentable & CaseIterable>(_ key: Key, _ type: T.Type) throws -> T where T.RawValue == String {
        let raw = try decode(String.self, forKey: key)
        guard let value = T(rawValue: raw) else {
            let names = T.allCases.map(\.rawValue).joined(separator: ", ")
            throw corrupted(at: key, "'\(raw)' is not one of \(names)")
        }
        return value
    }

    /// Like `value(_:_:)`, when the key is present.
    func valueIfPresent<T: RawRepresentable & CaseIterable>(_ key: Key, _ type: T.Type) throws -> T? where T.RawValue == String {
        guard contains(key) else { return nil }
        return try value(key, type)
    }

    /// An array with at least one element.
    func some<T: Decodable>(_ key: Key, _ type: T.Type) throws -> [T] {
        let values = try decode([T].self, forKey: key)
        if values.isEmpty { throw corrupted(at: key, "has no elements") }
        return values
    }

    /// Like `some(_:_:)`, when the key is present.
    func someIfPresent<T: Decodable>(_ key: Key, _ type: T.Type) throws -> [T]? {
        guard contains(key) else { return nil }
        return try some(key, type)
    }

    func require(_ value: String, matches format: Format, at key: Key) throws {
        if !format.matches(value) {
            throw corrupted(at: key, "'\(value)' is not \(format.expectation)")
        }
    }

    func requireNotEmpty(_ value: String, at key: Key) throws {
        if value.isEmpty { throw corrupted(at: key, "is empty") }
    }

    func corrupted(at key: Key, _ description: String) -> DecodingError {
        .dataCorrupted(DecodingError.Context(codingPath: codingPath + [key], debugDescription: description))
    }
}

extension DecodingError.Context {
    /// The path as the validator prints it: `secrets/0/source`, or `(root)`.
    var pathDescription: String {
        let parts = codingPath.map { key in key.intValue.map(String.init) ?? key.stringValue }
        return parts.isEmpty ? "(root)" : parts.joined(separator: "/")
    }
}
