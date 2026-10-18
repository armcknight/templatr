import CommonCrypto
import CryptoKit
import Foundation
import Testing
@testable import MatchCertificates

/// listExpiries, run against a fake match repository.
@Suite struct MatchCertificatesTests {
    static let password = MatchPassword("correct horse")
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
        try command(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "30", "-subj", "/CN=Apple Distribution: Example (TEAM)",
                     "-keyout", "key.pem", "-out", "cert.pem"], in: work.root)
        try command(["openssl", "x509", "-in", "cert.pem", "-outform", "DER", "-out", "cert.cer"], in: work.root)
        try command(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "400", "-subj", "/CN=Apple Development: Example (TEAM)",
                     "-keyout", "old-key.pem", "-out", "old-cert.pem"], in: work.root)
        try command(["openssl", "x509", "-in", "old-cert.pem", "-outform", "DER", "-out", "old-cert.cer"], in: work.root)

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
            try command(["openssl", "smime", "-sign", "-nodetach", "-binary", "-outform", "DER", "-signer", "cert.pem", "-inkey", "key.pem",
                         "-in", "profile.plist", "-out", "profile.der"], in: work.root)
            let signed = work.root.appending(path: "profile.der")
            let encrypted = profile.version == 2
                ? try encryptV2(Data(contentsOf: signed))
                : try encryptV1(signed, digest: "sha256", in: work.root)
            try repository.write(profile.file, encrypted)
        }

        try command(["git", "init", "--quiet"], in: repository.root)
        try command(["git", "add", "."], in: repository.root)
        try command(["git", "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "--quiet", "-m", "match"], in: repository.root)
        return repository
    }

    struct CommandFailure: Error {
        var transcript: String
    }

    /// Runs a command, with /usr/bin/openssl for openssl, and returns its
    /// standard output.
    @discardableResult
    static func command(_ arguments: [String], environment: [String: String] = [:], in directory: URL) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: arguments[0] == "openssl" ? "/usr/bin/openssl" : "/usr/bin/env")
        process.arguments = arguments[0] == "openssl" ? Array(arguments.dropFirst()) : arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        // The outputs are small, so reading one after the other cannot block.
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CommandFailure(transcript: String(decoding: errorData, as: UTF8.self))
        }
        return outputData
    }

    /// Version 1, as OpenSSL's `enc` writes it: "Salted__", the salt and the
    /// data, with the key and IV from the password and the salt.
    static func encryptV1(_ file: URL, digest: String, in directory: URL) throws -> String {
        let output = try command(
            ["openssl", "enc", "-aes-256-cbc", "-md", digest, "-salt", "-pass", "env:MATCH_TEST_PASSWORD", "-in", file.path],
            environment: ["MATCH_TEST_PASSWORD": password.rawValue], in: directory
        )
        return output.base64EncodedString(options: .lineLength64Characters) + "\n"
    }

    /// Version 2, as fastlane's MatchDataEncryption writes it.
    static func encryptV2(_ data: Data) throws -> String {
        let salt = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        var keyIV = Data(count: 68)
        let passwordData = Data(password.rawValue.utf8)
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

    @Test func listsTheCertificatesAndTheProfilesForTheBundleIDs() throws {
        let repository = try Self.matchRepository()
        let expiries = try listExpiries(
            gitURL: repository.root.path,
            bundleIDs: ["io.example.app", "io.example.watch", "io.example.app.adhoc"],
            password: Self.password
        )
        try #require(expiries.count == 4)
        #expect(expiries.map(\.name) == [
            "profile match AdHoc io.example.app.adhoc",
            "certificate Apple Distribution: Example (TEAM)",
            "profile match AppStore io.example.app",
            "certificate Apple Development: Example (TEAM)",
        ])
        #expect(expiries[0].expires == Self.adHocExpiry)
        #expect(expiries[2].expires == Self.appStoreExpiry)
        #expect(abs(expiries[1].expires.timeIntervalSinceNow - 30 * 86_400) < 3_600)
    }

    @Test func listsEveryProfileWithoutBundleIDs() throws {
        let repository = try Self.matchRepository()
        let expiries = try listExpiries(gitURL: repository.root.path, bundleIDs: [], password: Self.password)
        #expect(expiries.filter { $0.name.hasPrefix("profile ") }.count == 3)
    }

    @Test func aWrongPasswordFails() throws {
        let repository = try Self.matchRepository()
        // Version 1 has no integrity check: a wrong password can decrypt to
        // garbage, which then cannot be read.
        let error = #expect(throws: MatchError.self) {
            try listExpiries(gitURL: repository.root.path, bundleIDs: [], password: "wrong")
        }
        #expect(error?.description.hasSuffix("Is MATCH_PASSWORD right?") == true, "\(String(describing: error))")
    }

    @Test func aRepositoryThatCannotBeClonedFails() throws {
        let directory = try Directory()
        let error = #expect(throws: MatchError.self) {
            try listExpiries(gitURL: directory.root.appending(path: "missing").path, bundleIDs: [], password: Self.password)
        }
        #expect(error?.description.hasPrefix("Could not clone") == true, "\(String(describing: error))")
    }

    @Test func thePasswordComesFromMatchPassword() throws {
        #expect(try matchPassword(environment: ["MATCH_PASSWORD": "secret"]) == "secret")
    }

    @Test func aLineIsTheExpiryATabAndTheName() {
        let expiry = Expiry(expires: Date(timeIntervalSince1970: 1_803_643_200), name: "profile match AppStore io.example.app")
        #expect(expiry.line == "2027-02-26T12:00:00Z\tprofile match AppStore io.example.app")
    }
}

/// A temporary directory, deleted when the value goes away.
final class Directory {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "match-certificates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ path: String, _ text: String) throws {
        let url = root.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
