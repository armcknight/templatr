import ComponentManifest
import Foundation

/// What a project still needs: the result of `templatr check`, and of
/// `templatr bootstrap` after it has done what it can. `templatr check --json`
/// prints it; schema/check-report.schema.json is its format, which keeps its
/// `version` until a change would break a reader.
public struct Report: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = Report.currentVersion
    /// The components the project uses, with their pinned tags.
    public var components: [ComponentStatus] = []
    /// Components that detection finds but the record does not list. They are
    /// not added on their own.
    public var newComponents: [String] = []
    /// Components that the record lists but the templatr checkout does not have.
    public var unknownComponents: [String] = []
    /// Inputs with no value: not recorded, not found and with no default.
    public var missingInputs: [MissingInput] = []
    /// Steps whose check fails and whose fix is a command that did not make it
    /// pass, or, in `check`, was not run.
    public var failedSteps: [FailedStep] = []
    /// Steps that were not run because their commands use missing inputs.
    public var blockedSteps: [BlockedStep] = []
    /// Steps and secrets that a person must do, each one time.
    public var humanSteps: [HumanStep] = []
    /// Secrets that are not set: as GitHub secrets, or for `local` ones, in the
    /// Keychain. Never their values.
    public var missingSecrets: [MissingSecret] = []
    /// Secrets due for a new value within 30 days, or past due.
    public var expiries: [Expiry] = []
    /// Certificates, profiles and other files that expire within 30 days, or
    /// have expired, from the manifests' `certificates`.
    public var certificateExpiries: [CertificateExpiry] = []
    /// Components pinned to an older major version than the newest alias.
    public var oldTags: [OldTag] = []
    /// Links in README.md that no longer resolve.
    public var brokenLinks: [BrokenLink] = []
    /// What could not be checked, such as `gh` failing to list the secrets.
    public var errors: [String] = []

    public init() {}

    /// Whether the project needs nothing.
    public var isClean: Bool {
        newComponents.isEmpty && unknownComponents.isEmpty && missingInputs.isEmpty && failedSteps.isEmpty
            && blockedSteps.isEmpty && humanSteps.isEmpty && missingSecrets.isEmpty && expiries.isEmpty
            && certificateExpiries.isEmpty && oldTags.isEmpty && brokenLinks.isEmpty && errors.isEmpty
    }

    /// The report as JSON, with sorted keys and ISO 8601 dates.
    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(json: Data) throws -> Report {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Report.self, from: json)
    }
}

public struct ComponentStatus: Codable, Equatable, Sendable {
    public var name: String
    public var tag: String
    /// The newest alias of the templatr checkout, such as `v2`, when it knows
    /// its tags.
    public var newestTag: String?
}

public struct MissingInput: Codable, Equatable, Sendable {
    public var component: String
    public var name: String
    public var description: String
    public var example: String
}

public struct FailedStep: Codable, Equatable, Sendable {
    public var component: String
    public var id: String
    public var description: String
    /// The check's, or the fix's, standard output and error, shortened.
    public var output: String
}

public struct BlockedStep: Codable, Equatable, Sendable {
    public var component: String
    public var id: String
    public var description: String
    public var missingInputs: [String]
}

public struct HumanStep: Codable, Equatable, Sendable {
    public var component: String
    /// The step's ID, or `secret:<name>` for what a person does to get a
    /// secret.
    public var id: String
    public var description: String
    /// What to do, with the inputs filled in.
    public var text: String
    public var twoFactor: Bool
    /// The component's manifest on GitHub at the pinned tag.
    public var manifest: String
    /// The guide sections that explain the component.
    public var guide: [Link]
}

public struct MissingSecret: Codable, Equatable, Sendable {
    public var component: String
    public var name: String
    public var scope: String
    /// Where the value comes from, such as `keychain:templatr.match.password`.
    public var source: String
}

public struct Expiry: Codable, Equatable, Sendable {
    public var component: String
    public var secret: String
    /// The manifest's `rotateEvery`, such as `1y`.
    public var rotateEvery: String
    public var lastSet: Date
    public var due: Date
}

public struct CertificateExpiry: Codable, Equatable, Sendable {
    public var component: String
    /// The ID of the manifest's `certificates` entry that lists it.
    public var id: String
    /// The name its `list` command prints, such as a certificate's common name
    /// or a profile's name.
    public var name: String
    public var expires: Date
    /// What to do to replace it, with the inputs filled in.
    public var text: String
    public var twoFactor: Bool
}

public struct OldTag: Codable, Equatable, Sendable {
    public var component: String
    public var tag: String
    public var newest: String
}

public struct BrokenLink: Codable, Equatable, Sendable {
    public var file: String
    public var link: String
}
