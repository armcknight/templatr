import Foundation
import Testing
@testable import Templatr

/// bin/store-secrets, with a stand-in `security` that keeps its items as files,
/// a stand-in `fly` that makes a new token on each call, and a stand-in `swift`.
@Suite struct StoreSecretsTests {
    let bin: Directory
    let keys: Directory

    let uploadsKey = "-----BEGIN PRIVATE KEY-----\nuploads-key-contents\n-----END PRIVATE KEY-----\n"
    let adminKey = "-----BEGIN PRIVATE KEY-----\nadmin-key-contents\n-----END PRIVATE KEY-----\n"

    init() throws {
        bin = try Directory()
        keys = try Directory()
        try keys.write("Uploads.p8", uploadsKey)
        try keys.write("Admin.p8", adminKey)
        let root = bin.root.path
        // Each item is a file in keychain/, holding the value as hexadecimal.
        // Like security, it refuses to add an item that exists without -U, and
        // `security -i` prints the error and exits 0.
        try bin.writeExecutable("security", """
            #!/bin/sh
            echo "security $*" >> "\(root)/arguments.log"
            mkdir -p "\(root)/keychain"
            case "$1" in
              -i)
                while read -r command rest; do
                  [ "$command" = add-generic-password ] || { echo "unexpected: $command" >&2; continue; }
                  set -- $rest
                  update=0 item="" hex=""
                  while [ $# -gt 0 ]; do
                    case "$1" in
                      -U) update=1; shift ;;
                      -s) item="$2"; shift 2 ;;
                      -X) hex="$2"; shift 2 ;;
                      *) shift 2 ;;
                    esac
                  done
                  if [ -e "\(root)/keychain/$item" ] && [ $update -eq 0 ]; then
                    echo "security: The specified item already exists in the keychain." >&2
                    continue
                  fi
                  printf '%s' "$hex" > "\(root)/keychain/$item"
                done
                ;;
              find-generic-password)
                [ "$2" = -s ] && [ -e "\(root)/keychain/$3" ]
                ;;
              *) echo "unexpected: $*" >&2; exit 1 ;;
            esac
            """)
        try bin.writeExecutable("fly", """
            #!/bin/sh
            echo "fly $*" >> "\(root)/arguments.log"
            case "$*" in
              "auth whoami") echo owner@example.com ;;
              "tokens create deploy --app "*)
                count=$(cat "\(root)/fly.count" 2>/dev/null || echo 0)
                count=$((count + 1))
                echo $count > "\(root)/fly.count"
                echo "FlyV1 token-$5-$count"
                ;;
              *) echo "unexpected: $*" >&2; exit 1 ;;
            esac
            """)
        try bin.writeExecutable("swift", """
            #!/bin/sh
            echo "swift $*" >> "\(root)/arguments.log"
            """)
    }

    func run(_ arguments: [String]) throws -> CommandResult {
        let path = bin.root.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
        let script = repositoryRoot.appending(path: "bin/store-secrets").path
        return try ProcessRunner(environment: ["PATH": path]).run([script] + arguments, input: nil, in: nil)
    }

    var everyOption: [String] {
        [
            "--asc-key", keys.root.appending(path: "Uploads.p8").path, "--asc-key-id", "UPLOADS123",
            "--asc-issuer-id", "issuer-uuid",
            "--asc-admin-key", keys.root.appending(path: "Admin.p8").path, "--asc-admin-key-id", "ADMIN45678",
            "--asc-admin-issuer-id", "issuer-uuid",
            "--fly-app", "mtg-armcknight", "--fly-app", "other-app",
        ]
    }

    /// The stand-in Keychain's values, by item.
    var keychain: [String: String] {
        let directory = bin.root.appending(path: "keychain")
        let items = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Dictionary(uniqueKeysWithValues: items.map { item in
            let hex = Array(bin.read("keychain/" + item) ?? "")
            let bytes = stride(from: 0, to: hex.count - 1, by: 2).compactMap { UInt8(String(hex[$0...$0 + 1]), radix: 16) }
            return (item, String(decoding: bytes, as: UTF8.self))
        })
    }

    var arguments: String { bin.read("arguments.log") ?? "" }

    func base64(_ text: String) -> String { Data(text.utf8).base64EncodedString() }

    /// The MATCH_PASSWORD and MATCH_DEPLOY_KEY items, which the script only
    /// looks for.
    func addMatchItems() throws {
        try bin.write("keychain/superlinear.match.password", "00")
        try bin.write("keychain/superlinear.match-deploy-key", "00")
    }

    @Test func storesEachItemUnderTheManifestsName() throws {
        try addMatchItems()
        let result = try run(everyOption)
        #expect(result.succeeded, "\(result.transcript)")
        let stored = keychain
        #expect(stored["superlinear.asc.key-id"] == "UPLOADS123")
        #expect(stored["superlinear.asc.issuer-id"] == "issuer-uuid")
        #expect(stored["superlinear.asc.key-p8-base64"] == base64(uploadsKey))
        #expect(stored["superlinear.asc-admin.key-id"] == "ADMIN45678")
        #expect(stored["superlinear.asc-admin.issuer-id"] == "issuer-uuid")
        #expect(stored["superlinear.asc-admin.key-p8-base64"] == base64(adminKey))
        #expect(stored["superlinear.fly.mtg-armcknight.deploy-token"] == "FlyV1 token-mtg-armcknight-1")
        #expect(stored["superlinear.fly.other-app.deploy-token"] == "FlyV1 token-other-app-2")
        #expect(stored.count == 10)
    }

    @Test func noSecretIsInAnyArgumentOrTheOutput() throws {
        try addMatchItems()
        let result = try run(everyOption)
        #expect(result.succeeded, "\(result.transcript)")
        #expect(arguments.contains("fly tokens create deploy --app mtg-armcknight --expiry 8760h"))
        let output = result.transcript
        for secret in keychain.values where secret != "\0" {
            let hex = Data(secret.utf8).map { String(format: "%02x", $0) }.joined()
            #expect(!arguments.contains(secret) && !arguments.contains(hex), "\(secret) is in an argument")
            #expect(!output.contains(secret) && !output.contains(hex), "\(secret) is in the output")
        }
        for argument in arguments.split(separator: "\n") where argument.hasPrefix("security") {
            #expect(argument == "security -i" || argument.hasPrefix("security find-generic-password -s "))
        }
    }

    @Test func dryRunStoresNothingAndMakesNoToken() throws {
        let result = try run(everyOption + ["--check", "/tmp/project", "--dry-run"])
        #expect(result.succeeded == false, "the match items are missing")
        #expect(keychain.filter { !$0.key.hasPrefix("superlinear.match") }.isEmpty)
        #expect(!arguments.contains("security -i"))
        #expect(!arguments.contains("fly "))
        #expect(!arguments.contains("swift "))
        for item in [
            "superlinear.asc.key-id", "superlinear.asc.issuer-id", "superlinear.asc.key-p8-base64",
            "superlinear.asc-admin.key-id", "superlinear.asc-admin.issuer-id", "superlinear.asc-admin.key-p8-base64",
            "superlinear.fly.mtg-armcknight.deploy-token", "superlinear.fly.other-app.deploy-token",
        ] {
            #expect(result.text.contains("in the Keychain item \(item)."), "\(item)")
        }
        #expect(!result.transcript.contains("UPLOADS123"))
        #expect(!result.transcript.contains(base64(uploadsKey)))
    }

    @Test func aSecondRunUpdatesTheItems() throws {
        try addMatchItems()
        #expect(try run(everyOption).succeeded)
        let result = try run(everyOption)
        #expect(result.succeeded, "\(result.transcript)")
        #expect(keychain["superlinear.fly.mtg-armcknight.deploy-token"] == "FlyV1 token-mtg-armcknight-3")
        #expect(keychain["superlinear.asc.key-id"] == "UPLOADS123")
    }

    @Test func missingMatchItemsAreReportedNotMade() throws {
        let result = try run(["--fly-app", "mtg-armcknight"])
        #expect(result.status == 1)
        let errors = String(decoding: result.error, as: UTF8.self)
        #expect(errors.contains("no item superlinear.match.password for MATCH_PASSWORD"))
        #expect(errors.contains("no item superlinear.match-deploy-key for MATCH_DEPLOY_KEY"))
        #expect(keychain.keys.sorted() == ["superlinear.fly.mtg-armcknight.deploy-token"])
    }

    @Test func checksEachRepositoryAtTheEnd() throws {
        try addMatchItems()
        let result = try run(["--check", "/tmp/one", "--check", "/tmp/two words"])
        #expect(result.succeeded, "\(result.transcript)")
        let root = repositoryRoot.path
        #expect(arguments.contains("swift run --package-path \(root) templatr check /tmp/one\n"))
        #expect(arguments.contains("swift run --package-path \(root) templatr check /tmp/two words\n"))
    }

    @Test func aKeyNeedsAllThreeOptions() throws {
        let result = try run(["--asc-key", keys.root.appending(path: "Uploads.p8").path, "--asc-key-id", "UPLOADS123"])
        #expect(result.status == 2)
        #expect(keychain.isEmpty)
    }
}
