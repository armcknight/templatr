import Foundation
import Tagged

public enum BundleIDTag {}
/// An app's bundle ID, such as `io.example.app`.
public typealias BundleID = Tagged<BundleIDTag, String>

public enum MatchPasswordTag {}
/// The password the match repository's files are encrypted with.
public typealias MatchPassword = Tagged<MatchPasswordTag, String>

/// A certificate or profile and the date it expires.
public struct Expiry: Equatable, Sendable {
    public var expires: Date
    /// `certificate <common name>` or `profile <name>`.
    public var name: String

    public init(expires: Date, name: String) {
        self.expires = expires
        self.name = name
    }

    /// The line that a manifest's `list` command prints: the expiry as an
    /// ISO 8601 date and time, a tab, and the name.
    public var line: String {
        "\(ISO8601DateFormatter().string(from: expires))\t\(name)"
    }
}

/// Why the match repository could not be read, as a message for a person.
public struct MatchError: Error, CustomStringConvertible, Equatable {
    public var description: String

    public init(_ description: String) {
        self.description = description
    }
}
