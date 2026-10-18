import ComponentManifest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Applies a project's components from their manifests: finds them, sets up
/// what can be automated, and reports the rest. Running it again changes
/// nothing that is already done.
///
/// It knows nothing of Linear: callers such as superlinear's `bootstrap` turn
/// its `Report` into issues.
public struct Bootstrapper: Sendable {
    public var templates: Templates
    public var services: Services

    public init(templates: Templates, services: Services) {
        self.templates = templates
        self.services = services
    }

    /// Where a component's CLAUDE.md is copied in a project, for the project's
    /// CLAUDE.md to import.
    public static func vendoredClaudePath(_ component: String) -> String {
        ".templatr/\(component)/CLAUDE.md"
    }

    /// Which components `repository` uses and their inputs, without changing
    /// anything. `answers` are input values by component and input name, which
    /// win over recorded and inferred ones.
    public func resolve(repository: URL, answers: [String: [String: String]]) throws -> Resolution {
        let repository = repository.standardizedFileURL
        let catalog = try templates.components()
        let byName = Dictionary(catalog.map { ($0.name, $0) }) { first, _ in first }
        let files = RepositoryFiles(root: repository)
        let detected = catalog.filter { $0.manifest.detect.matches(files) }.map(\.name)
        let record = try Record.read(in: repository)

        var names = detected
        var resolution = Resolution(recorded: record != nil, components: [], newComponents: [], unknownComponents: [])
        if let record {
            names = record.components.keys.sorted().filter { byName[$0] != nil }
            resolution.unknownComponents = record.components.keys.sorted().filter { byName[$0] == nil }
            resolution.newComponents = detected.filter { record.components[$0] == nil }
        }

        let inferrer = Inferrer(files: files, buildSettings: services.buildSettings)
        resolution.components = names.map { name in
            let component = byName[name]!
            let entry = record?.components[name]
            let known = (entry?.inputs ?? [:]).merging(answers[name] ?? [:]) { $1 }
            let inferred = inferrer.infer(component.manifest.inputs, known: known)
            var values = known.merging(inferred) { first, _ in first }
            var missing: [Input] = []
            for input in component.manifest.inputs where values[input.name] == nil {
                if let value = input.defaultValue {
                    values[input.name] = value
                } else {
                    missing.append(input)
                }
            }
            return ResolvedComponent(
                component: component, tag: entry?.tag ?? templates.tag, values: values, inferred: inferred, missing: missing
            )
        }
        return resolution
    }

    /// Records the components, copies their scaffolds, runs their steps' checks
    /// and fixes, sets missing secrets, and writes the README section and the
    /// CLAUDE.md imports. Returns what it did and what is left.
    public func bootstrap(repository: URL, options: BootstrapOptions) async throws -> BootstrapResult {
        let repository = repository.standardizedFileURL
        let resolution = try resolve(repository: repository, answers: options.answers)
        var result = BootstrapResult()
        var report = Report()
        start(&report, resolution)
        let components = resolution.components

        if components.isEmpty && !resolution.recorded {
            report.errors.append("No component matches this repository.")
            result.report = report
            return result
        }

        let record = Record(components: Dictionary(components.map {
            ($0.component.name, Record.Entry(tag: $0.tag, inputs: $0.values))
        }) { first, _ in first })
        try write(record.toml(), to: Record.fileName, in: repository, result: &result)

        for resolved in components {
            try copyScaffold(resolved, to: repository, result: &result, report: &report)
        }
        for resolved in components {
            for step in resolved.component.manifest.steps {
                run(step, of: resolved, in: repository, fixing: true, result: &result, report: &report)
            }
        }
        secrets(components, in: repository, setting: options.setSecret, result: &result, report: &report)

        let readme = (try? String(contentsOf: repository.appending(path: "README.md"), encoding: .utf8))
            ?? "# \(repository.lastPathComponent)\n"
        let section = Markdown.readmeSection(components, links: options.links)
        try write(MarkedSection.readme.replace(in: readme, with: section), to: "README.md", in: repository, result: &result)

        for resolved in components {
            let source = resolved.component.directory.appending(path: "CLAUDE.md")
            if let text = try? String(contentsOf: source, encoding: .utf8) {
                try write(text, to: Self.vendoredClaudePath(resolved.component.name), in: repository, result: &result)
            }
        }
        let claude = (try? String(contentsOf: repository.appending(path: "CLAUDE.md"), encoding: .utf8)) ?? ""
        try write(
            MarkedSection.claude.replace(in: claude, with: Markdown.claudeSection(components)),
            to: "CLAUDE.md", in: repository, result: &result
        )

        await finish(&report, components, in: repository)
        result.report = report
        return result
    }

    /// What `repository` still needs, without changing anything: the steps'
    /// checks, missing secrets by name, secrets due for a new value, components
    /// behind the newest tag, and README links that no longer resolve.
    public func check(repository: URL) async throws -> Report {
        let repository = repository.standardizedFileURL
        let resolution = try resolve(repository: repository, answers: [:])
        var report = Report()
        start(&report, resolution)
        if resolution.components.isEmpty && !resolution.recorded {
            report.errors.append("No component matches this repository.")
            return report
        }
        var ignored = BootstrapResult()
        for resolved in resolution.components {
            for step in resolved.component.manifest.steps {
                run(step, of: resolved, in: repository, fixing: false, result: &ignored, report: &report)
            }
        }
        secrets(resolution.components, in: repository, setting: nil, result: &ignored, report: &report)
        await finish(&report, resolution.components, in: repository)
        return report
    }

    // MARK: - Steps of a run

    private func start(_ report: inout Report, _ resolution: Resolution) {
        let newest = Version.newest(of: templates.tags)
        report.components = resolution.components.map {
            ComponentStatus(name: $0.component.name, tag: $0.tag, newestTag: newest)
        }
        report.newComponents = resolution.newComponents
        report.unknownComponents = resolution.unknownComponents
        report.missingInputs = resolution.components.flatMap { resolved in
            resolved.missing.map {
                MissingInput(component: resolved.component.name, name: $0.name, description: $0.description, example: $0.example)
            }
        }
    }

    /// The reports every run ends with: old tags, expiries and broken links.
    private func finish(_ report: inout Report, _ components: [ResolvedComponent], in repository: URL) async {
        if let newest = Version.newest(of: templates.tags) {
            for resolved in components where Version.isOlder(resolved.tag, than: newest) {
                report.oldTags.append(OldTag(component: resolved.component.name, tag: resolved.tag, newest: newest))
            }
        }
        report.brokenLinks = await brokenLinks(in: repository)
    }

    private func copyScaffold(
        _ resolved: ResolvedComponent, to repository: URL, result: inout BootstrapResult, report: inout Report
    ) throws {
        let scaffold = resolved.component.directory.appending(path: "scaffold")
        let values = PlaceholderValues(inputs: resolved.values, templates: templates.root, tag: resolved.tag)
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(atPath: scaffold.path) else { return }
        var paths: [String] = []
        while let path = enumerator.nextObject() as? String {
            if enumerator.fileAttributes?[.type] as? FileAttributeType == .typeRegular {
                paths.append(path)
            }
        }
        for path in paths.sorted() {
            let target = repository.appending(path: path)
            guard !manager.fileExists(atPath: target.path) else { continue }
            let source = scaffold.appending(path: path)
            var data = try Data(contentsOf: source)
            if let text = String(data: data, encoding: .utf8) {
                let rendered = values.render(text, quoted: false)
                if !rendered.missing.isEmpty {
                    report.blockedSteps.append(BlockedStep(
                        component: resolved.component.name, id: "scaffold:\(path)",
                        description: "Copy \(path) from the scaffold.", missingInputs: rendered.missing
                    ))
                    continue
                }
                data = Data(rendered.text.utf8)
            }
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
            if let permissions = try manager.attributesOfItem(atPath: source.path)[.posixPermissions] {
                try manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
            }
            result.copiedFiles.append(path)
        }
    }

    private func run(
        _ step: Step, of resolved: ResolvedComponent, in repository: URL, fixing: Bool,
        result: inout BootstrapResult, report: inout Report
    ) {
        let name = resolved.component.name
        let values = PlaceholderValues(inputs: resolved.values, templates: templates.root, tag: resolved.tag)
        let check = values.render(step.check, quoted: true)
        var fixCommand: (text: String, missing: [String])?
        if case .command(let command) = step.fix {
            fixCommand = values.render(command, quoted: true)
        }
        let missing = check.missing + (fixing ? fixCommand?.missing ?? [] : [])
        guard missing.isEmpty else {
            report.blockedSteps.append(BlockedStep(
                component: name, id: step.id, description: step.description,
                missingInputs: Array(Set(missing.map { $0.replacingOccurrences(of: "inputs.", with: "") })).sorted()
            ))
            return
        }
        let checked = shell(check.text, in: repository)
        if checked.succeeded { return }

        switch step.fix {
        case .human(let human):
            report.humanSteps.append(HumanStep(
                component: name, id: step.id, description: step.description,
                text: values.render(human.text, quoted: false).text, twoFactor: human.twoFactor,
                manifest: resolved.component.manifestLink(tag: resolved.tag), guide: resolved.component.guide
            ))
        case .command:
            var output = checked.transcript
            if fixing, let fixCommand {
                let fixed = shell(fixCommand.text, in: repository)
                let rechecked = shell(check.text, in: repository)
                if rechecked.succeeded {
                    result.fixedSteps.append("\(name)/\(step.id)")
                    return
                }
                output = [fixed.transcript, rechecked.transcript].filter { !$0.isEmpty }.joined(separator: "\n")
            }
            report.failedSteps.append(FailedStep(component: name, id: step.id, description: step.description, output: output))
        }
    }

    private func shell(_ command: String, in repository: URL) -> CommandResult {
        do {
            return try services.runner.shell(command, in: repository)
        } catch {
            return CommandResult(status: -1, output: Data(), error: Data("\(error)".utf8))
        }
    }

    /// Finds the missing secrets and, when `setting` is given and agrees, sets
    /// them from their sources. Values stay in memory: they go only to the
    /// Keychain and to `gh secret set`.
    private func secrets(
        _ components: [ResolvedComponent], in repository: URL, setting: (@Sendable (Secret) -> Bool)?,
        result: inout BootstrapResult, report: inout Report
    ) {
        var github: [String: Date]?
        let needsGitHub = components.contains { $0.component.manifest.secrets.contains { $0.scope != .local } }
        if needsGitHub {
            do {
                github = try services.secrets.list(repository: repository)
            } catch {
                report.errors.append("Could not list the repository's secrets: \(error)")
            }
        }

        var seen: Set<String> = []
        for resolved in components {
            let name = resolved.component.name
            let values = PlaceholderValues(inputs: resolved.values, templates: templates.root, tag: resolved.tag)
            for declared in resolved.component.manifest.secrets where seen.insert(declared.name).inserted {
                // A source with a placeholder that has no value is not read:
                // the input is reported as missing.
                let (secret, unfilled) = declared.filled(values)
                let missing = MissingSecret(component: name, name: secret.name, scope: secret.scope.rawValue, source: secret.source.rawValue)
                let human = secret.human.map {
                    HumanStep(
                        component: name, id: "secret:\(secret.name)", description: "Get the secret \(secret.name).",
                        text: values.render($0.text, quoted: false).text, twoFactor: $0.twoFactor,
                        manifest: resolved.component.manifestLink(tag: resolved.tag), guide: resolved.component.guide
                    )
                }

                if secret.scope == .local {
                    let item = unfilled.isEmpty ? (try? secret.keychainItem.map { try services.keychain.lookup($0) }) ?? nil : nil
                    if let item {
                        expiry(of: secret, in: name, lastSet: item.modified, report: &report)
                    } else {
                        report.missingSecrets.append(missing)
                        human.map { report.humanSteps.append($0) }
                    }
                    continue
                }

                guard let github else { continue }
                if let updated = github[secret.name] {
                    expiry(of: secret, in: name, lastSet: updated, report: &report)
                    continue
                }
                if unfilled.isEmpty, let setting, setting(secret) {
                    do {
                        let (value, generated) = try value(of: secret)
                        if let value {
                            try services.secrets.set(secret.name, value: value, repository: repository)
                            result.secretsSet.append(secret.name)
                            if generated {
                                result.secretsGenerated.append(secret.name)
                                human.map { report.humanSteps.append($0) }
                            }
                            continue
                        }
                    } catch {
                        report.errors.append("Could not set the secret \(secret.name): \(error)")
                    }
                }
                report.missingSecrets.append(missing)
                human.map { report.humanSteps.append($0) }
            }
        }
    }

    /// The secret's value from its source, and whether it was generated now.
    private func value(of secret: Secret) throws -> (String?, Bool) {
        switch secret.source {
        case .keychain(let item):
            return (try services.keychain.read(item), false)
        case .onePassword(let reference):
            return (try services.passwordManager.read(reference: reference), false)
        case .generate(let kind):
            let item = secret.keychainItem!
            if let value = try services.keychain.read(item) {
                return (value, false)
            }
            let (value, publicHalf) = try Generator.generate(kind, comment: item, runner: services.runner)
            try services.keychain.store(item, value: value)
            if let publicHalf {
                try services.keychain.store(item + ".pub", value: publicHalf)
            }
            return (value, true)
        }
    }

    private func expiry(of secret: Secret, in component: String, lastSet: Date?, report: inout Report) {
        guard let period = secret.rotateEvery, let lastSet,
              let due = period.date(after: lastSet)
        else { return }
        let warning = Calendar(identifier: .gregorian).date(byAdding: .day, value: 30, to: services.now())!
        if due <= warning {
            report.expiries.append(Expiry(
                component: component, secret: secret.name, rotateEvery: period.rawValue, lastSet: lastSet, due: due
            ))
        }
    }

    /// The links in README.md that do not resolve: relative paths that do not
    /// exist, and web links the link checker cannot open.
    private func brokenLinks(in repository: URL) async -> [BrokenLink] {
        guard let text = try? String(contentsOf: repository.appending(path: "README.md"), encoding: .utf8) else {
            return []
        }
        var web: [URL] = []
        var broken: [String] = []
        for link in Markdown.links(in: text) where !link.hasPrefix("#") && !link.hasPrefix("mailto:") {
            if link.hasPrefix("http://") || link.hasPrefix("https://") {
                if let url = URL(string: link) { web.append(url) } else { broken.append(link) }
                continue
            }
            let path = String(link.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
            let decoded = path.removingPercentEncoding ?? path
            if !FileManager.default.fileExists(atPath: repository.appending(path: decoded).path) {
                broken.append(link)
            }
        }
        let checker = services.links
        let unresolved = await withTaskGroup(of: String?.self) { group in
            for url in Set(web) {
                group.addTask { await checker.resolves(url) ? nil : url.absoluteString }
            }
            var unresolved: [String] = []
            for await link in group {
                if let link { unresolved.append(link) }
            }
            return unresolved
        }
        return (broken + unresolved.sorted()).map { BrokenLink(file: "README.md", link: $0) }
    }

    /// Writes `text` to `path` when it differs, and notes the change.
    private func write(_ text: String, to path: String, in repository: URL, result: inout BootstrapResult) throws {
        let url = repository.appending(path: path)
        if (try? String(contentsOf: url, encoding: .utf8)) == text { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
        result.changedFiles.append(path)
    }
}

/// Which components a repository uses, and their inputs.
public struct Resolution: Sendable {
    /// Whether the repository has a `.templatr.toml`, so this is not its first
    /// run.
    public var recorded: Bool
    public var components: [ResolvedComponent]
    /// Detected, but not in the record.
    public var newComponents: [String]
    /// In the record, but not in the templatr checkout.
    public var unknownComponents: [String]
}

/// A component that a repository uses, and its inputs.
public struct ResolvedComponent: Sendable {
    public var component: Component
    /// The tag the component is pinned to.
    public var tag: String
    /// Every input with a value: given, recorded, inferred or default.
    public var values: [String: String]
    /// The values found in the repository on this run, which the CLI shows to
    /// confirm on a first run.
    public var inferred: [String: String]
    /// Inputs with no value, to ask for.
    public var missing: [Input]
}

public struct BootstrapOptions: Sendable {
    /// Input values by component and input name. They win over recorded and
    /// inferred values, and are recorded.
    public var answers: [String: [String: String]]
    /// Links for the README section that templatr does not know, such as the
    /// project's Linear team and spec document.
    public var links: [Link]
    /// Whether to set a secret that is missing from GitHub. Called before its
    /// value is read.
    public var setSecret: @Sendable (Secret) -> Bool

    public init(answers: [String: [String: String]], links: [Link], setSecret: @escaping @Sendable (Secret) -> Bool) {
        self.answers = answers
        self.links = links
        self.setSecret = setSecret
    }
}

/// What `bootstrap` did, and its report of what is left.
public struct BootstrapResult: Sendable {
    public var report = Report()
    /// Scaffold files copied into the repository.
    public var copiedFiles: [String] = []
    /// Files written or updated: the record, README.md, CLAUDE.md and the
    /// components' CLAUDE.md copies.
    public var changedFiles: [String] = []
    /// Steps whose fix made their check pass, as `<component>/<id>`.
    public var fixedSteps: [String] = []
    /// GitHub secrets set, by name.
    public var secretsSet: [String] = []
    /// Secrets generated and stored in the Keychain, by name.
    public var secretsGenerated: [String] = []

    public init() {}
}

/// The programs and services a run uses.
public struct Services: Sendable {
    public var runner: any CommandRunner
    public var buildSettings: any BuildSettingsProvider
    public var keychain: any Keychain
    public var passwordManager: any PasswordManager
    public var secrets: any SecretStore
    public var links: any LinkChecker
    public var now: @Sendable () -> Date

    public init(
        runner: any CommandRunner, buildSettings: any BuildSettingsProvider, keychain: any Keychain,
        passwordManager: any PasswordManager, secrets: any SecretStore, links: any LinkChecker,
        now: @escaping @Sendable () -> Date
    ) {
        self.runner = runner
        self.buildSettings = buildSettings
        self.keychain = keychain
        self.passwordManager = passwordManager
        self.secrets = secrets
        self.links = links
        self.now = now
    }

    /// `xcodebuild`, `security`, `op` and `gh`, and web requests for links.
    public static func system() -> Services {
        let runner = ProcessRunner()
        return Services(
            runner: runner, buildSettings: XcodeBuildSettings(runner: runner), keychain: SystemKeychain(runner: runner),
            passwordManager: OnePasswordCLI(runner: runner), secrets: GitHubCLI(runner: runner), links: HTTPLinkChecker(),
            now: { Date() }
        )
    }
}

/// Whether a web link still opens.
public protocol LinkChecker: Sendable {
    func resolves(_ url: URL) async -> Bool
}

/// Requests each link: a status below 400 resolves.
public struct HTTPLinkChecker: LinkChecker {
    public init() {}

    public func resolves(_ url: URL) async -> Bool {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        guard let target = components?.url else { return false }
        for method in ["HEAD", "GET"] {
            var request = URLRequest(url: target, timeoutInterval: 20)
            request.httpMethod = method
            let status: Int? = await withCheckedContinuation { continuation in
                URLSession.shared.dataTask(with: request) { _, response, _ in
                    continuation.resume(returning: (response as? HTTPURLResponse)?.statusCode)
                }.resume()
            }
            guard let status else { return false }
            if status < 400 { return true }
            // Some servers refuse HEAD; ask again with GET.
            if status != 405 && status != 403 { return false }
        }
        return false
    }
}

/// Every link resolves, for runs without the network.
public struct OfflineLinkChecker: LinkChecker {
    public init() {}

    public func resolves(_ url: URL) async -> Bool { true }
}

extension RotationPeriod {
    /// When a value set at `date` is due for a new one.
    func date(after date: Date) -> Date? {
        let component: Calendar.Component = switch unit {
        case .days: .day
        case .weeks: .weekOfYear
        case .months: .month
        case .years: .year
        }
        return Calendar(identifier: .gregorian).date(byAdding: component, value: count, to: date)
    }
}
