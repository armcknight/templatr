import ComponentManifest
import Foundation
import Tagged

/// `templatr store-secrets`: stores the App Store Connect API keys and the Fly
/// deploy tokens in the Keychain, under the item names that the apple-app and
/// vapor-fly manifests give in their secrets' `source` fields. It is the
/// terminal half of making them: Apple has no CLI or API that makes a team API
/// key, so each key is made on the App Store Connect website first and its
/// .p8 file downloaded. Fly deploy tokens it makes itself, with `fly tokens
/// create deploy`.
///
/// A value is never printed, and never in a command's arguments, where `ps`
/// can show it: the Keychain gets it on `security`'s standard input, as
/// `bootstrap` stores a generated secret. Items are replaced, so running it
/// again replaces the values.
public struct SecretStorer: Sendable {
    public var templates: Templates
    public var services: Services

    public init(templates: Templates, services: Services) {
        self.templates = templates
        self.services = services
    }

    /// An App Store Connect API key: its .p8 file, its key ID and its issuer
    /// ID. The two IDs are both strings that App Store Connect shows next to
    /// each other, so each has a type of its own, and one cannot be given for
    /// the other.
    public struct APIKey: Equatable, Sendable {
        public typealias ID = Tagged<APIKey, String>
        public typealias IssuerID = Tagged<Issuer, String>
        public enum Issuer {}

        public var file: URL
        public var keyID: ID
        public var issuerID: IssuerID

        public init(file: URL, keyID: ID, issuerID: IssuerID) {
            self.file = file
            self.keyID = keyID
            self.issuerID = issuerID
        }
    }

    /// A Fly app's name, as `fly` takes it: lowercase letters, digits and
    /// dashes.
    public typealias FlyApp = Tagged<FlyAppTag, String>
    public enum FlyAppTag {}

    public struct Options: Sendable {
        /// The Uploads key, with the App Manager role: `ASC_KEY_P8_BASE64`,
        /// `ASC_KEY_ID` and `ASC_ISSUER_ID`.
        public var uploadsKey: APIKey?
        /// The Admin key, which match uses to make certificates and profiles:
        /// `ASC_ADMIN_KEY_P8_BASE64`, `ASC_ADMIN_KEY_ID` and
        /// `ASC_ADMIN_ISSUER_ID`.
        public var adminKey: APIKey?
        /// The Fly apps to make a deploy token for, each stored as the app's
        /// `FLY_API_TOKEN`.
        public var flyApps: [FlyApp]
        /// Print the item that each value would go in, and store nothing and
        /// make no token.
        public var dryRun: Bool

        public init(uploadsKey: APIKey? = nil, adminKey: APIKey? = nil, flyApps: [FlyApp] = [], dryRun: Bool = false) {
            self.uploadsKey = uploadsKey
            self.adminKey = adminKey
            self.flyApps = flyApps
            self.dryRun = dryRun
        }
    }

    /// What was done, for people: `stored` is one line for each item, and
    /// `missing` one for each item that is looked for and not there, with how
    /// to add it. Nothing in either is a value. The two kinds of line have
    /// types of their own, so a line for the person to act on is never printed
    /// as a line about what was done.
    public struct Outcome: Equatable, Sendable {
        public typealias Stored = Tagged<StoredTag, String>
        public typealias Missing = Tagged<MissingTag, String>
        public enum StoredTag {}
        public enum MissingTag {}

        public var stored: [Stored] = []
        public var missing: [Missing] = []

        public var isClean: Bool { missing.isEmpty }
    }

    /// Stores what `options` give, then looks for `MATCH_PASSWORD` and
    /// `MATCH_DEPLOY_KEY`, which it does not make. Every item name is read
    /// from the manifests first, so a manifest problem stops the run before
    /// anything is stored.
    /// - Throws: `TemplatrError` when a key file cannot be read or is not a
    ///   private key, when `fly` is not logged in, or when storing fails.
    public func store(_ options: Options) throws -> Outcome {
        try validate(options.uploadsKey, label: "Uploads")
        try validate(options.adminKey, label: "Admin")
        for app in options.flyApps where app.rawValue.isEmpty || app.rawValue.contains(where: { !($0.isLowercase || $0.isNumber || $0 == "-") }) {
            throw TemplatrError("'\(app)' is not a Fly app name")
        }

        let components = try templates.components()
        func item(_ component: String, _ secret: String, inputs: [String: String] = [:]) throws -> String {
            guard let component = components.first(where: { $0.name == component }) else {
                throw TemplatrError("the templatr checkout has no \(component) component")
            }
            guard let secret = component.manifest.secrets.first(where: { $0.name == secret }) else {
                throw TemplatrError("the \(component.name) manifest has no secret \(secret)")
            }
            guard let item = secret.keychainItem else {
                throw TemplatrError("the \(component.name) manifest has no Keychain source for the secret \(secret.name)")
            }
            let values = PlaceholderValues(inputs: inputs, templates: templates.root, tag: templates.tag)
            let (rendered, missing) = values.render(item, quoted: false)
            guard missing.isEmpty else {
                throw TemplatrError("the Keychain item \(item) for \(secret.name) needs \(missing.joined(separator: ", "))")
            }
            return rendered
        }
        let uploads = try (id: item("apple-app", "ASC_KEY_ID"), issuer: item("apple-app", "ASC_ISSUER_ID"), p8: item("apple-app", "ASC_KEY_P8_BASE64"))
        let admin = try (id: item("apple-app", "ASC_ADMIN_KEY_ID"), issuer: item("apple-app", "ASC_ADMIN_ISSUER_ID"), p8: item("apple-app", "ASC_ADMIN_KEY_P8_BASE64"))
        let matchPassword = try item("apple-app", "MATCH_PASSWORD")
        let matchKey = try item("apple-app", "MATCH_DEPLOY_KEY")
        let flyItems = try options.flyApps.map { (app: $0, item: try item("vapor-fly", "FLY_API_TOKEN", inputs: ["fly_app": $0.rawValue])) }

        if !options.flyApps.isEmpty && !options.dryRun {
            guard let whoami = try? services.runner.run(["fly", "auth", "whoami"], input: nil, in: nil), whoami.succeeded else {
                throw TemplatrError("fly is not logged in, or flyctl is not installed: run fly auth login, or brew install flyctl")
            }
        }

        var outcome = Outcome()
        func store(_ item: String, _ value: String, _ description: String) throws {
            if options.dryRun {
                outcome.stored.append(Outcome.Stored("Would store \(description) in the Keychain item \(item)."))
                return
            }
            guard !value.isEmpty else { throw TemplatrError("the value for \(item) is empty") }
            try services.keychain.store(item, value: value)
            outcome.stored.append(Outcome.Stored("Stored \(description) in the Keychain item \(item)."))
        }
        func store(_ key: APIKey, as items: (id: String, issuer: String, p8: String), label: String) throws {
            try store(items.id, key.keyID.rawValue, "the \(label) key's ID")
            try store(items.issuer, key.issuerID.rawValue, "the \(label) key's issuer ID")
            // The .p8 file, base64 encoded on one line.
            let encoded = options.dryRun ? "" : try Data(contentsOf: key.file).base64EncodedString()
            try store(items.p8, encoded, "the \(label) key's .p8 file, base64 encoded")
        }

        if let key = options.uploadsKey { try store(key, as: uploads, label: "Uploads") }
        if let key = options.adminKey { try store(key, as: admin, label: "Admin") }

        // The expiry is the manifest's rotateEvery of FLY_API_TOKEN, one year.
        for (app, item) in flyItems {
            if options.dryRun {
                outcome.stored.append(Outcome.Stored("Would store a new deploy token for the Fly app \(app) in the Keychain item \(item)."))
                continue
            }
            let result = try services.runner.run(["fly", "tokens", "create", "deploy", "--app", app.rawValue, "--expiry", "8760h"], input: nil, in: nil)
            guard result.succeeded else { throw TemplatrError("could not make a deploy token for \(app): \(result.transcript)") }
            let token = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { throw TemplatrError("fly printed no deploy token for \(app)") }
            try store(item, token, "a new deploy token for the Fly app \(app)")
        }

        // Only the items' attributes are read, never their values.
        if try services.keychain.lookup(matchPassword) == nil {
            outcome.missing.append(Outcome.Missing(
                "The Keychain has no item \(matchPassword) for MATCH_PASSWORD. Add the match repository's passphrase with "
                    + "`security add-generic-password -U -a templatr -s \(matchPassword) -w`, which asks for the value, so that it is not in the shell history."
            ))
        }
        if try services.keychain.lookup(matchKey) == nil {
            outcome.missing.append(Outcome.Missing(
                "The Keychain has no item \(matchKey) for MATCH_DEPLOY_KEY. Run templatr bootstrap on an apple-app project, which makes the key "
                    + "and stores it with its public half in \(matchKey).pub, then add the public half to the match repository as a read-only deploy key."
            ))
        }
        return outcome
    }

    /// Checks a key's file before anything is stored.
    private func validate(_ key: APIKey?, label: String) throws {
        guard let key else { return }
        guard let contents = try? String(contentsOf: key.file, encoding: .utf8) else {
            throw TemplatrError("cannot read the \(label) key's file, \(key.file.path)")
        }
        guard contents.contains("BEGIN PRIVATE KEY") else {
            throw TemplatrError("\(key.file.path) is not a .p8 private key")
        }
        guard !key.keyID.rawValue.isEmpty, !key.issuerID.rawValue.isEmpty else {
            throw TemplatrError("the \(label) key needs its .p8 file, its key ID and its issuer ID")
        }
    }
}
