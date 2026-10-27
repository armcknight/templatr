import Foundation
import Tagged

/// The password from MATCH_PASSWORD or, without it, from the Keychain item
/// templatr.match.password.
public func matchPassword(environment: [String: String] = ProcessInfo.processInfo.environment) throws(MatchError) -> MatchPassword {
    if let password = environment["MATCH_PASSWORD"], !password.isEmpty {
        return MatchPassword(password)
    }
    let keychain = try run(["security", "find-generic-password", "-s", "templatr.match.password", "-w"])
    let password = keychain.output.trimmingCharacters(in: .newlines)
    guard keychain.status == 0, !password.isEmpty else {
        throw MatchError("MATCH_PASSWORD is not set, and the Keychain has no item templatr.match.password.")
    }
    return MatchPassword(password)
}

/// Each certificate in the fastlane match repository at `gitURL`, and each
/// provisioning profile there for one of `bundleIDs` (every profile when it is
/// empty), sorted by expiry.
///
/// It clones the repository's default branch into a temporary directory and
/// decrypts each file in memory. Nothing decrypted is written to a file.
public func listExpiries(gitURL: String, bundleIDs: Set<BundleID>, password: MatchPassword) throws(MatchError) -> [Expiry] {
    let directory = FileManager.default.temporaryDirectory.appending(path: "match-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let clone = try run(["git", "clone", "--quiet", "--depth", "1", gitURL, directory.path])
    guard clone.status == 0 else {
        throw MatchError("Could not clone \(gitURL): \(clone.error.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
    let repository = Clone(directory: directory, password: password)

    var expiries: [Expiry] = []
    for file in repository.files(in: "certs", extensions: ["cer"]) {
        guard let certificate = try repository.read(file, readCertificate) else {
            throw MatchError("Could not read the certificate \(repository.relative(file)). Is MATCH_PASSWORD right?")
        }
        expiries.append(Expiry(expires: certificate.expires, name: "certificate \(certificate.name ?? file.deletingPathExtension().lastPathComponent)"))
    }
    for file in repository.files(in: "profiles", extensions: ["mobileprovision", "provisionprofile"]) {
        let profile = try repository.read(file) { data in
            readProfile(data).flatMap { profile in profile["ExpirationDate"] is Date ? profile : nil }
        }
        guard let profile, let expires = profile["ExpirationDate"] as? Date else {
            throw MatchError("Could not read the profile \(repository.relative(file)). Is MATCH_PASSWORD right?")
        }
        guard bundleIDs.isEmpty || bundleIDs.contains(bundleID(of: profile)) else { continue }
        expiries.append(Expiry(expires: expires, name: "profile \(profile["Name"] as? String ?? file.lastPathComponent)"))
    }
    return expiries.sorted { $0.expires < $1.expires }
}

/// A clone of the match repository.
private struct Clone {
    var directory: URL
    var password: MatchPassword

    /// The files under a directory of the clone whose extensions are one of
    /// these, sorted by path.
    func files(in path: String, extensions: Set<String>) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory.appending(path: path), includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }
            .filter { extensions.contains($0.pathExtension) }
            .sorted { $0.path < $1.path }
    }

    /// The path of a file in the clone, for messages.
    func relative(_ file: URL) -> String {
        String(file.standardizedFileURL.path.dropFirst(directory.standardizedFileURL.path.count + 1))
    }

    /// The first value that `read` reads from what the file decrypts to.
    func read<Value>(_ file: URL, _ read: (Data) -> Value?) throws(MatchError) -> Value? {
        guard let contents = try? Data(contentsOf: file) else { throw MatchError("Could not read \(relative(file)).") }
        do {
            return try decrypt(contents, password: password).lazy.compactMap(read).first
        } catch {
            throw MatchError("Could not decrypt \(relative(file)). Is MATCH_PASSWORD right?")
        }
    }
}
