import ArgumentParser
import Foundation
import Templatr

extension TemplatrCommand {
    /// `templatr store-secrets`: the App Store Connect API keys and the Fly
    /// deploy tokens into the Keychain, under the manifests' item names.
    struct StoreSecrets: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "store-secrets",
            abstract: "Store the App Store Connect API keys and the Fly deploy tokens in the Keychain, under the manifests' item names.",
            discussion: """
                Apple has no command line or API that makes a team API key: make each key on the App Store \
                Connect website first (Users and Access, Integrations, App Store Connect API, Team Keys) and \
                download its .p8 file. Fly deploy tokens are made here, with `fly tokens create deploy`, when \
                fly is logged in. It also looks for MATCH_PASSWORD and MATCH_DEPLOY_KEY, and says how to add \
                each one that is missing; it does not make them. A value is never printed, and never in a \
                command's arguments. Running it again replaces the values.

                Exit status: 0 when everything was stored and nothing is missing, 1 when something failed or \
                is missing, 64 for a usage error.
                """
        )

        @Option(help: TemplatrCommand.templatesHelp)
        var templates: String?

        @Option(help: "The tag the manifests are read at. The checkout's newest alias, such as v1, by default.")
        var tag: String?

        @Option(name: .customLong("asc-key"), help: ArgumentHelp("The Uploads key's .p8 file (App Manager role).", valueName: "file"))
        var ascKey: String?
        @Option(name: .customLong("asc-key-id"), help: "The Uploads key's ID.")
        var ascKeyID: String?
        @Option(name: .customLong("asc-issuer-id"), help: "The Uploads key's issuer ID.")
        var ascIssuerID: String?

        @Option(name: .customLong("asc-admin-key"), help: ArgumentHelp("The Admin key's .p8 file, which match uses to make certificates and profiles.", valueName: "file"))
        var ascAdminKey: String?
        @Option(name: .customLong("asc-admin-key-id"), help: "The Admin key's ID.")
        var ascAdminKeyID: String?
        @Option(name: .customLong("asc-admin-issuer-id"), help: "The Admin key's issuer ID.")
        var ascAdminIssuerID: String?

        @Option(name: .customLong("fly-app"), help: "A Fly app to make a deploy token for, stored as its FLY_API_TOKEN. Can be given more than one time.")
        var flyApps: [String] = []

        @Option(name: .customLong("check"), help: ArgumentHelp("A repository to run `templatr check` on at the end. Can be given more than one time.", valueName: "dir"))
        var checks: [String] = []

        @Flag(name: .customLong("dry-run"), help: "Print the item that each value would go in, and store nothing, make no token and run no check.")
        var dryRun = false

        /// A key's three options come together, or not at all.
        static func key(_ file: String?, _ id: String?, _ issuer: String?, label: String) throws -> SecretStorer.APIKey? {
            switch (file, id, issuer) {
            case (nil, nil, nil): return nil
            case (let file?, let id?, let issuer?):
                return SecretStorer.APIKey(file: URL(fileURLWithPath: file), keyID: .init(id), issuerID: .init(issuer))
            default: throw ValidationError("the \(label) key needs its .p8 file, its key ID and its issuer ID")
            }
        }

        func validate() throws {
            _ = try Self.key(ascKey, ascKeyID, ascIssuerID, label: "Uploads")
            _ = try Self.key(ascAdminKey, ascAdminKeyID, ascAdminIssuerID, label: "Admin")
        }

        func run() async throws {
            let services = Services.system()
            let outcome: SecretStorer.Outcome
            let templates: Templates
            do {
                templates = try TemplatrCommand.templates(path: self.templates, tag: tag, runner: services.runner)
                let options = SecretStorer.Options(
                    uploadsKey: try Self.key(ascKey, ascKeyID, ascIssuerID, label: "Uploads"),
                    adminKey: try Self.key(ascAdminKey, ascAdminKeyID, ascAdminIssuerID, label: "Admin"),
                    flyApps: flyApps.map { SecretStorer.FlyApp($0) }, dryRun: dryRun
                )
                outcome = try SecretStorer(templates: templates, services: services).store(options)
            } catch {
                TemplatrCommand.printError("templatr: \(error)")
                throw ExitCode.failure
            }
            for line in outcome.stored { print(line.rawValue) }
            for line in outcome.missing { TemplatrCommand.printError(line.rawValue) }

            // Each repository is checked, even after one that has something
            // left to do.
            var failed = !outcome.isClean
            for repository in checks {
                if dryRun {
                    print("Would run templatr check on \(repository).")
                    continue
                }
                print("templatr check \(repository)")
                do {
                    let report = try await Bootstrapper(templates: templates, services: services).check(repository: URL(fileURLWithPath: repository))
                    print(TemplatrCommand.describe(report))
                    if !report.isClean { failed = true }
                } catch {
                    TemplatrCommand.printError("templatr: \(error)")
                    failed = true
                }
            }
            if failed { throw ExitCode.failure }
        }
    }
}
