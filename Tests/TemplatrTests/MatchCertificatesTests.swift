#if os(macOS)
import CommonCrypto
import CryptoKit
import Foundation
import Testing
@testable import Templatr

/// The apple-app component's list-match-certificates script, run against a
/// fake match repository. It is a Swift script that reads the files with the
/// Security framework, so these run only on macOS.
@Suite struct MatchCertificatesTests {
    static let script = repositoryRoot.appending(path: "components/apple-app/bin/list-match-certificates").path
    static let password = "correct horse"
    /// The profiles' expiry dates, in whole seconds: one before the
    /// distribution certificate's, in 30 days, and one after.
    static let adHocExpiry = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 + 10 * 86_400).rounded())
    static let appStoreExpiry = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 + 90 * 86_400).rounded())

    /// A match repository, as a local git repository: a certificate encrypted
    /// as fastlane encrypts now (version 2), one encrypted as older fastlane
    /// did (version 1, with MD5), and three profiles, one of each version and
    /// one with SHA-256, for three bundle IDs.
    static func matchRepository() throws -> Directory {
        let work = try Directory()
        let repository = try Directory()
        try openssl(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "30", "-subj", "/CN=Apple Distribution: Example (TEAM)",
                     "-keyout", "key.pem", "-out", "cert.pem"], in: work.root)
        try openssl(["x509", "-in", "cert.pem", "-outform", "DER", "-out", "cert.cer"], in: work.root)
        try openssl(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "400", "-subj", "/CN=Apple Development: Example (TEAM)",
                     "-keyout", "old-key.pem", "-out", "old-cert.pem"], in: work.root)
        try openssl(["x509", "-in", "old-cert.pem", "-outform", "DER", "-out", "old-cert.cer"], in: work.root)

        try repository.write("certs/distribution/ABC.cer", encryptV2(Data(contentsOf: work.root.appending(path: "cert.cer"))))
        try repository.write("certs/development/DEF.cer", encryptV1(work.root.appending(path: "old-cert.cer"), digest: "md5", in: work.root))

        let profiles: [(file: String, name: String, bundleID: String, expires: Date, version: Int)] = [
            ("profiles/appstore/AppStore_io.example.app.mobileprovision", "match AppStore io.example.app", "io.example.app", appStoreExpiry, 2),
            ("profiles/adhoc/AdHoc_io.example.app.adhoc.mobileprovision", "match AdHoc io.example.app.adhoc", "io.example.app.adhoc", adHocExpiry, 1),
            ("profiles/appstore/AppStore_io.example.other.mobileprovision", "match AppStore io.example.other", "io.example.other", adHocExpiry, 2),
        ]
        for profile in profiles {
            let plist: [String: Any] = [
                "Name": profile.name,
                "ExpirationDate": profile.expires,
                "Entitlements": ["application-identifier": "TEAM.\(profile.bundleID)"],
            ]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
                .write(to: work.root.appending(path: "profile.plist"))
            try openssl(["smime", "-sign", "-nodetach", "-binary", "-outform", "DER", "-signer", "cert.pem", "-inkey", "key.pem",
                         "-in", "profile.plist", "-out", "profile.der"], in: work.root)
            let signed = work.root.appending(path: "profile.der")
            let encrypted = profile.version == 2
                ? try encryptV2(Data(contentsOf: signed))
                : try encryptV1(signed, digest: "sha256", in: work.root)
            try repository.write(profile.file, encrypted)
        }

        for command in [["init", "--quiet"], ["add", "."], ["-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "--quiet", "-m", "match"]] {
            let result = try ProcessRunner().run(["git"] + command, input: nil, in: repository.root)
            #expect(result.succeeded, "\(result.transcript)")
        }
        return repository
    }

    static func openssl(_ arguments: [String], in directory: URL) throws {
        let result = try ProcessRunner().run(["/usr/bin/openssl"] + arguments, input: nil, in: directory)
        if !result.succeeded {
            throw CommandFailure(transcript: result.transcript)
        }
    }

    struct CommandFailure: Error {
        var transcript: String
    }

    /// Version 1, as OpenSSL's `enc` writes it: "Salted__", the salt and the
    /// data, with the key and IV from the password and the salt.
    static func encryptV1(_ file: URL, digest: String, in directory: URL) throws -> String {
        let result = try ProcessRunner(environment: ["MATCH_TEST_PASSWORD": password]).run(
            ["/usr/bin/openssl", "enc", "-aes-256-cbc", "-md", digest, "-salt", "-pass", "env:MATCH_TEST_PASSWORD", "-in", file.path],
            input: nil, in: directory
        )
        if !result.succeeded {
            throw CommandFailure(transcript: result.transcript)
        }
        return result.output.base64EncodedString(options: .lineLength64Characters) + "\n"
    }

    /// Version 2, as fastlane's MatchDataEncryption writes it.
    static func encryptV2(_ data: Data) throws -> String {
        let salt = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        var keyIV = Data(count: 68)
        let passwordData = Data(password.utf8)
        _ = keyIV.withUnsafeMutableBytes { keyIVBytes in
            salt.withUnsafeBytes { saltBytes in
                passwordData.withUnsafeBytes { passwordBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.bindMemory(to: CChar.self).baseAddress, passwordData.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 10_000,
                        keyIVBytes.bindMemory(to: UInt8.self).baseAddress, 68
                    )
                }
            }
        }
        let box = try AES.GCM.seal(
            data, using: SymmetricKey(data: keyIV.prefix(32)),
            nonce: AES.GCM.Nonce(data: keyIV.subdata(in: 32..<44)), authenticating: keyIV.subdata(in: 44..<68)
        )
        let stored = Data("match_encrypted_v2__".utf8) + salt + box.tag + box.ciphertext
        return stored.base64EncodedString(options: .lineLength64Characters) + "\n"
    }

    func run(_ arguments: [String], password: String = Self.password) throws -> CommandResult {
        try ProcessRunner(environment: ["MATCH_PASSWORD": password]).run([Self.script] + arguments, input: nil, in: nil)
    }

    @Test func listsTheCertificatesAndTheProfilesForTheBundleIDs() throws {
        let repository = try Self.matchRepository()
        let result = try run([repository.root.path, "io.example.app,io.example.watch", "io.example.app.adhoc"])
        #expect(result.succeeded, "\(result.transcript)")

        let lines = result.text.split(separator: "\n").map { $0.split(separator: "\t").map(String.init) }
        try #require(lines.count == 4)
        #expect(lines.map { $0.last } == [
            "profile match AdHoc io.example.app.adhoc",
            "certificate Apple Distribution: Example (TEAM)",
            "profile match AppStore io.example.app",
            "certificate Apple Development: Example (TEAM)",
        ])
        let formatter = ISO8601DateFormatter()
        #expect(lines[0].first == formatter.string(from: Self.adHocExpiry))
        #expect(lines[2].first == formatter.string(from: Self.appStoreExpiry))
        let expires = try #require(formatter.date(from: lines[1][0]))
        #expect(abs(expires.timeIntervalSinceNow - 30 * 86_400) < 3_600)
    }

    @Test func listsEveryProfileWithoutBundleIDs() throws {
        let repository = try Self.matchRepository()
        let result = try run([repository.root.path])
        #expect(result.succeeded, "\(result.transcript)")
        #expect(result.text.split(separator: "\n").filter { $0.contains("\tprofile ") }.count == 3)
    }

    @Test func aWrongPasswordExits2() throws {
        let repository = try Self.matchRepository()
        let result = try run([repository.root.path], password: "wrong")
        #expect(result.status == 2)
        #expect(result.text.isEmpty)
        // Version 1 has no integrity check: a wrong password can decrypt to
        // garbage, which then cannot be read.
        #expect(result.transcript.hasSuffix("Is MATCH_PASSWORD right?"), "\(result.transcript)")
    }

    @Test func aRepositoryThatCannotBeClonedExits2() throws {
        let directory = try Directory()
        let result = try run([directory.root.appending(path: "missing").path])
        #expect(result.status == 2)
        #expect(result.transcript.contains("Could not clone"), "\(result.transcript)")
    }
}
#endif
