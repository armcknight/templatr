import Foundation
import Testing
@testable import Templatr

/// `templatr store-secrets`, with the stub Keychain and a stand-in `fly` that
/// makes a new token on each call, against this repository's manifests.
@Suite struct StoreSecretsTests {
    let bin: Directory
    let keys: Directory
    let stubs = Stubs()

    let uploadsKey = "-----BEGIN PRIVATE KEY-----\nuploads-key-contents\n-----END PRIVATE KEY-----\n"
    let adminKey = "-----BEGIN PRIVATE KEY-----\nadmin-key-contents\n-----END PRIVATE KEY-----\n"

    init() throws {
        bin = try Directory()
        keys = try Directory()
        try keys.write("Uploads.p8", uploadsKey)
        try keys.write("Admin.p8", adminKey)
        try keys.write("NotAKey.p8", "hello\n")
        try bin.writeExecutable("fly", """
            #!/bin/sh
            echo "fly $*" >> "\(bin.root.path)/arguments.log"
            case "$*" in
              "auth whoami") echo owner@example.com ;;
              "tokens create deploy --app "*)
                count=$(cat "\(bin.root.path)/fly.count" 2>/dev/null || echo 0)
                count=$((count + 1))
                echo $count > "\(bin.root.path)/fly.count"
                echo "FlyV1 token-$5-$count"
                ;;
              *) echo "unexpected: $*" >&2; exit 1 ;;
            esac
            """)
    }

    var storer: SecretStorer {
        var services = stubs.services()
        let path = bin.root.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
        services.runner = ProcessRunner(environment: ["PATH": path])
        return SecretStorer(templates: Templates(root: repositoryRoot, tag: "v1", tags: []), services: services)
    }

    func key(_ name: String, id: SecretStorer.APIKey.ID, issuer: SecretStorer.APIKey.IssuerID = "issuer-uuid") -> SecretStorer.APIKey {
        SecretStorer.APIKey(file: keys.root.appending(path: name), keyID: id, issuerID: issuer)
    }

    var everyOption: SecretStorer.Options {
        SecretStorer.Options(
            uploadsKey: key("Uploads.p8", id: "UPLOADS123"), adminKey: key("Admin.p8", id: "ADMIN45678"),
            flyApps: ["mtg-armcknight", "other-app"]
        )
    }

    var arguments: String { bin.read("arguments.log") ?? "" }

    func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }

    /// The MATCH_PASSWORD and MATCH_DEPLOY_KEY items, which are only looked for.
    func addMatchItems() {
        stubs.setKeychain("templatr.match.password", "pass", modified: stubs.now)
        stubs.setKeychain("templatr.match-deploy-key", "key", modified: stubs.now)
    }

    @Test func storesEachItemUnderTheManifestsName() throws {
        addMatchItems()
        let outcome = try storer.store(everyOption)
        #expect(outcome.isClean, "\(outcome.missing)")
        let stored = stubs.keychain
        #expect(stored["templatr.asc.key-id"] == "UPLOADS123")
        #expect(stored["templatr.asc.issuer-id"] == "issuer-uuid")
        #expect(stored["templatr.asc.key-p8-base64"] == base64(uploadsKey))
        #expect(stored["templatr.asc-admin.key-id"] == "ADMIN45678")
        #expect(stored["templatr.asc-admin.issuer-id"] == "issuer-uuid")
        #expect(stored["templatr.asc-admin.key-p8-base64"] == base64(adminKey))
        #expect(stored["templatr.fly.mtg-armcknight.deploy-token"] == "FlyV1 token-mtg-armcknight-1")
        #expect(stored["templatr.fly.other-app.deploy-token"] == "FlyV1 token-other-app-2")
        #expect(stored.count == 10)
        #expect(outcome.stored.count == 8)
        #expect(outcome.stored.map(\.rawValue).contains("Stored the Uploads key's .p8 file, base64 encoded in the Keychain item templatr.asc.key-p8-base64."))
    }

    @Test func noSecretIsInAnyArgumentOrTheOutcome() throws {
        addMatchItems()
        let outcome = try storer.store(everyOption)
        #expect(arguments.contains("fly tokens create deploy --app mtg-armcknight --expiry 8760h"))
        let text = (outcome.stored.map(\.rawValue) + outcome.missing.map(\.rawValue)).joined(separator: "\n")
        for secret in stubs.keychain.values where !["pass", "key"].contains(secret) {
            #expect(!arguments.contains(secret), "\(secret) is in an argument")
            #expect(!text.contains(secret), "\(secret) is in the outcome")
        }
    }

    @Test func dryRunStoresNothingAndMakesNoToken() throws {
        var options = everyOption
        options.dryRun = true
        let outcome = try storer.store(options)
        #expect(!outcome.isClean, "the match items are missing")
        #expect(stubs.keychain.isEmpty)
        #expect(arguments.isEmpty)
        for item in [
            "templatr.asc.key-id", "templatr.asc.issuer-id", "templatr.asc.key-p8-base64",
            "templatr.asc-admin.key-id", "templatr.asc-admin.issuer-id", "templatr.asc-admin.key-p8-base64",
            "templatr.fly.mtg-armcknight.deploy-token", "templatr.fly.other-app.deploy-token",
        ] {
            #expect(outcome.stored.contains { $0.rawValue.hasPrefix("Would store ") && $0.rawValue.hasSuffix("in the Keychain item \(item).") }, "\(item)")
        }
    }

    @Test func aSecondRunReplacesTheValues() throws {
        addMatchItems()
        #expect(try storer.store(everyOption).isClean)
        let outcome = try storer.store(everyOption)
        #expect(outcome.isClean)
        #expect(stubs.keychain["templatr.fly.mtg-armcknight.deploy-token"] == "FlyV1 token-mtg-armcknight-3")
        #expect(stubs.keychain["templatr.asc.key-id"] == "UPLOADS123")
    }

    @Test func missingMatchItemsAreReportedNotMade() throws {
        let outcome = try storer.store(SecretStorer.Options(flyApps: ["mtg-armcknight"]))
        #expect(!outcome.isClean)
        #expect(outcome.missing.contains { $0.rawValue.contains("no item templatr.match.password for MATCH_PASSWORD") })
        #expect(outcome.missing.contains { $0.rawValue.contains("no item templatr.match-deploy-key for MATCH_DEPLOY_KEY") })
        #expect(stubs.keychain.keys.sorted() == ["templatr.fly.mtg-armcknight.deploy-token"])
    }

    @Test func aFileThatIsNotAKeyStoresNothing() throws {
        addMatchItems()
        #expect(throws: TemplatrError.self) {
            try storer.store(SecretStorer.Options(uploadsKey: key("NotAKey.p8", id: "UPLOADS123"), flyApps: ["mtg-armcknight"]))
        }
        #expect(stubs.keychain.count == 2)
        #expect(!arguments.contains("tokens create"))
    }

    @Test func aFlyAppNameIsChecked() throws {
        #expect(throws: TemplatrError.self) {
            try storer.store(SecretStorer.Options(flyApps: ["Not An App"]))
        }
        #expect(arguments.isEmpty)
    }
}
