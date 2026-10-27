import ComponentManifest
import Foundation

/// The macOS Keychain's generic passwords, by service name.
public protocol Keychain: Sendable {
    /// The item's value, or `nil` when there is no item.
    func read(_ item: String) throws -> String?
    /// Whether the item exists, and when it last changed, without its value.
    func lookup(_ item: String) throws -> KeychainItem?
    /// Adds the item, or replaces its value.
    func store(_ item: String, value: String) throws
}

public struct KeychainItem: Equatable, Sendable {
    /// When the item last changed, when the Keychain says.
    public var modified: Date?

    public init(modified: Date?) {
        self.modified = modified
    }
}

/// A password manager that reads `op://` references.
public protocol PasswordManager: Sendable {
    func read(reference: String) throws -> String?
}

/// A repository's GitHub Actions secrets.
public protocol SecretStore: Sendable {
    /// The names of the repository's secrets, and when each was last set.
    func list(repository: URL) throws -> [String: Date]
    /// Sets the secret. The value goes to the store only, never to a log.
    func set(_ name: String, value: String, repository: URL) throws
}

/// The Keychain through the `security` command.
public struct SystemKeychain: Keychain {
    public var runner: any CommandRunner

    public init(runner: any CommandRunner) {
        self.runner = runner
    }

    public func read(_ item: String) throws -> String? {
        // -g prints the value on standard error, marking the hexadecimal form
        // that security uses for a value with new lines. (-w prints that form
        // without a mark, so a hexadecimal value could not be told from it.)
        let result = try runner.run(["security", "find-generic-password", "-s", item, "-g"], input: nil, in: nil)
        guard result.succeeded else { return nil }
        return Self.password(in: String(decoding: result.error, as: UTF8.self))
    }

    /// The value in `security -g` output: `password: "value"`, or
    /// `password: 0x<hex>  "escaped"`.
    static func password(in output: String) -> String? {
        guard let line = output.split(separator: "\n").first(where: { $0.hasPrefix("password: ") }) else { return nil }
        let value = line.dropFirst("password: ".count)
        if value.hasPrefix("0x") {
            let hex = value.dropFirst(2).prefix { $0.isHexDigit }
            var bytes: [UInt8] = []
            var index = hex.startIndex
            while index < hex.endIndex, let end = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) {
                guard let byte = UInt8(hex[index..<end], radix: 16) else { return nil }
                bytes.append(byte)
                index = end
            }
            return String(decoding: bytes, as: UTF8.self)
        }
        guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { return nil }
        return String(value.dropFirst().dropLast())
    }

    public func lookup(_ item: String) throws -> KeychainItem? {
        // Without -w, security prints the item's attributes and not its value.
        let result = try runner.run(["security", "find-generic-password", "-s", item], input: nil, in: nil)
        guard result.succeeded else { return nil }
        return KeychainItem(modified: Self.modified(in: result.text))
    }

    public func store(_ item: String, value: String) throws {
        // The value goes on standard input to `security -i`, as hexadecimal, so
        // it is not in any process's arguments and may have new lines.
        let hex = Data(value.utf8).map { String(format: "%02x", $0) }.joined()
        let command = "add-generic-password -U -a templatr -s \(Shell.quote(item)) -X \(hex)\n"
        let result = try runner.run(["security", "-i"], input: Data(command.utf8), in: nil)
        // `security -i` exits 0 even when its command fails, and then prints
        // the error.
        guard result.succeeded, result.error.isEmpty else {
            throw TemplatrError("could not store the Keychain item \(item)")
        }
    }

    /// The `mdat` attribute, as `"mdat"<timedate>=0x… "20261017120000Z\000"`.
    static func modified(in attributes: String) -> Date? {
        guard let stamp = Patterns.firstGroup(#""mdat"<timedate>=\S+\s+"(\d{14})Z"#, in: attributes) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.date(from: stamp)
    }
}

/// 1Password through the `op` command.
public struct OnePasswordCLI: PasswordManager {
    public var runner: any CommandRunner

    public init(runner: any CommandRunner) {
        self.runner = runner
    }

    public func read(reference: String) throws -> String? {
        let result = try runner.run(["op", "read", "--no-newline", reference], input: nil, in: nil)
        return result.succeeded ? result.text : nil
    }
}

/// GitHub Actions secrets through the `gh` command, for the repository that
/// `gh` finds in the directory.
public struct GitHubCLI: SecretStore {
    public var runner: any CommandRunner

    public init(runner: any CommandRunner) {
        self.runner = runner
    }

    public func list(repository: URL) throws -> [String: Date] {
        let result = try runner.run(["gh", "secret", "list", "--json", "name,updatedAt"], input: nil, in: repository)
        guard result.succeeded else {
            throw TemplatrError("gh secret list failed: \(result.transcript)")
        }
        struct Entry: Decodable {
            var name: String
            var updatedAt: Date
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try decoder.decode([Entry].self, from: result.output)
        return Dictionary(entries.map { ($0.name, $0.updatedAt) }) { $1 }
    }

    public func set(_ name: String, value: String, repository: URL) throws {
        // With no --body, gh reads the value from standard input.
        let result = try runner.run(["gh", "secret", "set", name], input: Data(value.utf8), in: repository)
        guard result.succeeded else {
            throw TemplatrError("gh secret set \(name) failed: \(result.transcript)")
        }
    }
}

extension Secret {
    /// The secret with the placeholders in its source filled, such as the Fly
    /// app in `keychain:templatr.fly.{{inputs.fly_app}}.deploy-token`, and
    /// the placeholders that have no value.
    func filled(_ values: PlaceholderValues) -> (secret: Secret, missing: [String]) {
        let rendered = values.render(source.rawValue, quoted: false)
        var secret = self
        if let source = Source(rawValue: rendered.text) {
            secret.source = source
        }
        return (secret, rendered.missing)
    }

    /// The Keychain item that holds the value: the source's item, or for a
    /// generated secret `templatr.<name>`, such as
    /// `templatr.match-deploy-key`. `nil` for a 1Password secret.
    public var keychainItem: String? {
        switch source {
        case .keychain(let item): item
        case .onePassword: nil
        case .generate: "templatr." + name.lowercased().replacingOccurrences(of: "_", with: "-")
        }
    }
}

enum Generator {
    /// A new value, and for an SSH key its public half.
    static func generate(
        _ kind: Secret.Source.Generated, comment: String, runner: any CommandRunner
    ) throws -> (value: String, publicHalf: String?) {
        switch kind {
        case .password:
            let characters = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
            var generator = SystemRandomNumberGenerator()
            return (String((0..<32).map { _ in characters.randomElement(using: &generator)! }), nil)
        case .hex32:
            var generator = SystemRandomNumberGenerator()
            return ((0..<32).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined(), nil)
        case .sshKey:
            // ssh-keygen only writes to files: they go in a directory only this
            // user can read, which is deleted at once.
            let directory = FileManager.default.temporaryDirectory.appending(path: "templatr-\(UUID().uuidString)")
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
            )
            defer { try? FileManager.default.removeItem(at: directory) }
            let key = directory.appending(path: "key")
            let result = try runner.run(
                ["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", comment, "-f", key.path], input: nil, in: nil
            )
            guard result.succeeded else { throw TemplatrError("ssh-keygen failed: \(result.transcript)") }
            let value = try String(contentsOf: key, encoding: .utf8)
            let publicHalf = try String(contentsOf: directory.appending(path: "key.pub"), encoding: .utf8)
            return (value, publicHalf.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
