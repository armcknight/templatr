import ArgumentParser
import Foundation
import MatchCertificates

@main
struct ListMatchCertificates: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list-match-certificates",
        abstract: "Lists the certificates and profiles in a fastlane match repository, with their expiry dates.",
        discussion: """
            Prints one line for each certificate in the repository, and for each provisioning profile there for one of \
            the bundle IDs (every profile when none is given): its expiry as an ISO 8601 date and time, a tab, and its \
            name. The password is MATCH_PASSWORD or, without it, the Keychain item superlinear.match.password. Exits 2 \
            when it cannot read the repository.
            """
    )

    @Argument(help: "The match repository's git URL.")
    var gitURL: String

    @Argument(help: "The bundle IDs whose profiles to list. Each argument can have more than one, separated by commas.")
    var bundleIDs: [String] = []

    func run() throws {
        let bundleIDs = Set(bundleIDs
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { BundleID(rawValue: $0) })
        do {
            let expiries = try listExpiries(gitURL: gitURL, bundleIDs: bundleIDs, password: matchPassword())
            for expiry in expiries {
                print(expiry.line)
            }
        } catch {
            FileHandle.standardError.write(Data((error.description + "\n").utf8))
            throw ExitCode(2)
        }
    }
}
