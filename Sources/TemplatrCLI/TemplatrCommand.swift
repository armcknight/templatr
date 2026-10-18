import ComponentManifest
import Foundation
import Templatr

/// `templatr bootstrap` and `templatr check`: a thin command line on the
/// Templatr library.
@main
struct TemplatrCommand {
    static let usage = """
        Usage: templatr bootstrap [<repository>] [--templates DIR] [--tag TAG] [--yes] [--link TITLE=URL]...
               templatr check [<repository>] [--templates DIR] [--tag TAG] [--json] [--offline]

          <repository>     The project's root. The current directory by default.
          --templates DIR  A checkout of armcknight/templatr. This checkout by default.
          --tag TAG        The tag new components are pinned to. The checkout's
                           newest v* tag by default.
          --yes            Accept the inferred inputs and set missing secrets without
                           asking. Without a terminal, nothing is asked: inferred
                           inputs are kept, and secrets are set only with --yes.
          --link T=URL     A link for the README section, such as the project's
                           Linear team. Can be given more than one time.
          --json           Print the report as JSON (schema/check-report.schema.json).
          --offline        Do not check web links in the README.

        Exit status: 0 when nothing is left to do, 1 when the report lists
        something, 2 for a usage error.
        """

    /// This checkout, from this file's path: Sources/TemplatrCLI/<file>.
    static let defaultTemplates = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func main() async {
        var arguments = CommandLine.arguments.dropFirst()[...]
        guard let command = arguments.popFirst(), ["bootstrap", "check"].contains(command) else {
            if let first = CommandLine.arguments.dropFirst().first, ["-h", "--help"].contains(first) {
                print(usage)
                return
            }
            fail("needs bootstrap or check")
        }

        var repository = FileManager.default.currentDirectoryPath
        var templatesRoot = defaultTemplates
        var tag: String?
        var yes = false
        var json = false
        var offline = false
        var links: [Link] = []
        var gotRepository = false
        while let argument = arguments.popFirst() {
            switch argument {
            case "--templates":
                guard let value = arguments.popFirst() else { fail("--templates needs a directory") }
                templatesRoot = URL(fileURLWithPath: value)
            case "--tag":
                guard let value = arguments.popFirst() else { fail("--tag needs a tag") }
                tag = value
            case "--yes" where command == "bootstrap":
                yes = true
            case "--link" where command == "bootstrap":
                guard let value = arguments.popFirst(), let equals = value.firstIndex(of: "=") else {
                    fail("--link needs TITLE=URL")
                }
                links.append(Link(title: String(value[..<equals]), url: String(value[value.index(after: equals)...])))
            case "--json" where command == "check":
                json = true
            case "--offline" where command == "check":
                offline = true
            case "-h", "--help":
                print(usage)
                return
            default:
                guard !argument.hasPrefix("-"), !gotRepository else { fail("unknown argument '\(argument)'") }
                repository = argument
                gotRepository = true
            }
        }

        var services = Services.system()
        if offline {
            services.links = OfflineLinkChecker()
        }
        let repositoryURL = URL(fileURLWithPath: repository)
        do {
            let templates = try Templates.checkout(at: templatesRoot, tag: tag, runner: services.runner)
            let bootstrapper = Bootstrapper(templates: templates, services: services)
            let report: Report
            if command == "check" {
                report = try await bootstrapper.check(repository: repositoryURL)
                if json {
                    print(String(decoding: try report.json(), as: UTF8.self))
                } else {
                    print(describe(report))
                }
            } else {
                report = try await bootstrap(bootstrapper, repository: repositoryURL, yes: yes, links: links)
            }
            exit(report.isClean ? 0 : 1)
        } catch {
            printError("templatr: \(error)")
            exit(1)
        }
    }

    static func bootstrap(_ bootstrapper: Bootstrapper, repository: URL, yes: Bool, links: [Link]) async throws -> Report {
        let interactive = isatty(STDIN_FILENO) == 1 && !yes
        let resolution = try bootstrapper.resolve(repository: repository, answers: [:])
        var answers: [String: [String: String]] = [:]

        for resolved in resolution.components where interactive {
            let name = resolved.component.name
            // On the first run, show what was found, to confirm or change.
            if !resolution.recorded && !resolved.inferred.isEmpty {
                print("\(name): inputs found in the repository. Press Return to keep each one, or type a new value.")
                for input in resolved.component.manifest.inputs {
                    guard let value = resolved.inferred[input.name] else { continue }
                    if let answer = ask("  \(input.name) [\(value)]: "), !answer.isEmpty {
                        answers[name, default: [:]][input.name] = answer
                    }
                }
            }
            if !resolved.missing.isEmpty {
                print("\(name): inputs not found. Leave one empty to skip it for now.")
                for input in resolved.missing {
                    print("  \(input.name): \(input.description) For example: \(input.example)")
                    if let answer = ask("  \(input.name): "), !answer.isEmpty {
                        answers[name, default: [:]][input.name] = answer
                    }
                }
            }
        }

        let setSecret: @Sendable (Secret) -> Bool = { secret in
            if yes { return true }
            guard interactive else { return false }
            let answer = ask("Set the GitHub secret \(secret.name) from \(secret.source.rawValue)? [y/N] ")
            return ["y", "yes"].contains(answer?.lowercased() ?? "")
        }
        let result = try await bootstrapper.bootstrap(
            repository: repository, options: BootstrapOptions(answers: answers, links: links, setSecret: setSecret)
        )

        for path in result.copiedFiles { print("Copied \(path)") }
        for path in result.changedFiles { print("Wrote \(path)") }
        for step in result.fixedSteps { print("Fixed \(step)") }
        for name in result.secretsGenerated { print("Generated \(name) and stored it in the Keychain") }
        for name in result.secretsSet { print("Set the GitHub secret \(name)") }
        print(describe(result.report))
        return result.report
    }

    /// The report for people.
    static func describe(_ report: Report) -> String {
        var lines: [String] = []
        for component in report.components {
            lines.append("Component \(component.name) at \(component.tag)")
        }
        func section(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            lines += ["", title] + items.map { "  " + $0 }
        }
        section("New components detected, not recorded (add them to .templatr.toml to use them):", report.newComponents)
        section("Components in .templatr.toml that the templatr checkout does not have:", report.unknownComponents)
        section("Missing inputs:", report.missingInputs.map { "\($0.component).\($0.name): \($0.description)" })
        section("Failed steps:", report.failedSteps.map {
            "\($0.component)/\($0.id): \($0.description)" + ($0.output.isEmpty ? "" : "\n    " + $0.output.replacingOccurrences(of: "\n", with: "\n    "))
        })
        section("Steps not run, for missing inputs:", report.blockedSteps.map {
            "\($0.component)/\($0.id): needs \($0.missingInputs.joined(separator: ", "))"
        })
        section("Steps a person must do:", report.humanSteps.map { step in
            var text = "\(step.component)/\(step.id): \(step.description)\(step.twoFactor ? " (needs two-factor)" : "")\n    \(step.text)\n    Manifest: \(step.manifest)"
            for link in step.guide { text += "\n    Guide: \(link.title), \(link.url)" }
            return text
        })
        section("Missing secrets:", report.missingSecrets.map { "\($0.name) (\($0.scope)), from \($0.source)" })
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withFullDate]
        section("Secrets due for a new value:", report.expiries.map {
            "\($0.secret): every \($0.rotateEvery), last set \(dates.string(from: $0.lastSet)), due \(dates.string(from: $0.due))"
        })
        section("Components behind the newest tag:", report.oldTags.map { "\($0.component) at \($0.tag); the newest is \($0.newest)" })
        section("Broken links:", report.brokenLinks.map { "\($0.file): \($0.link)" })
        section("Errors:", report.errors)
        if report.isClean {
            lines += ["", "Nothing is left to do."]
        }
        return lines.joined(separator: "\n")
    }

    static func ask(_ prompt: String) -> String? {
        FileHandle.standardOutput.write(Data(prompt.utf8))
        return readLine()?.trimmingCharacters(in: .whitespaces)
    }

    static func fail(_ message: String) -> Never {
        printError("templatr: \(message)\n\(usage)")
        exit(2)
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
