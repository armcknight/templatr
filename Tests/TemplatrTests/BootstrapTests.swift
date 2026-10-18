import ComponentManifest
import Foundation
import Testing
@testable import Templatr

@Suite struct BootstrapTests {
    let templates: Directory
    let project: Directory
    let stubs = Stubs()

    init() throws {
        templates = try makeTemplates()
        project = try makeProject()
        stubs.setKeychain("demo.demo-api.deploy-token", "deploy-token-value", modified: stubs.now)
        stubs.setKeychain("demo.local-token", "local-token-value", modified: stubs.now)
        stubs.onePassword["op://Vault/Signing/key"] = "signing-key-value"
    }

    func bootstrapper(tags: [String]) -> Bootstrapper {
        Bootstrapper(templates: Templates(root: templates.root, tag: "v1", tags: tags), services: stubs.services())
    }

    func bootstrap(setSecret: @escaping @Sendable (Secret) -> Bool) async throws -> BootstrapResult {
        try await bootstrapper(tags: ["v1"]).bootstrap(
            repository: project.root,
            options: BootstrapOptions(answers: [:], links: [Link(title: "Linear", url: "https://linear.app/demo")], setSecret: setSecret)
        )
    }

    @Test func aSecondRunChangesNothing() async throws {
        let first = try await bootstrap(setSecret: setEverySecret)
        #expect(!first.copiedFiles.isEmpty)
        #expect(first.fixedSteps == ["demo/configured"])
        let files = project.snapshot()
        let secrets = stubs.github

        let second = try await bootstrap(setSecret: setEverySecret)
        #expect(project.snapshot() == files)
        #expect(stubs.github == secrets)
        #expect(second.copiedFiles.isEmpty)
        #expect(second.changedFiles.isEmpty)
        #expect(second.fixedSteps.isEmpty)
        #expect(second.secretsSet.isEmpty)
        #expect(second.secretsGenerated.isEmpty)
    }

    @Test func scaffoldFilesAreCopiedWithTheirInputsAndNeverOverwritten() async throws {
        try project.write(".github/workflows/ci.yml", "mine\n")
        let result = try await bootstrap(setSecret: setEverySecret)
        #expect(result.copiedFiles == ["bin/deploy"])
        #expect(project.read(".github/workflows/ci.yml") == "mine\n")
        #expect(project.read("bin/deploy") == "#!/bin/sh\nfly deploy --app demo-api\n")
        let permissions = try FileManager.default.attributesOfItem(atPath: project.root.appending(path: "bin/deploy").path)[.posixPermissions] as? Int
        #expect(permissions == 0o755)
        // The project's README is its own: the scaffold's is not copied over it.
        #expect(project.read("README.md")?.hasPrefix("# Demo\n") == true)
    }

    @Test func theRecordHasTheComponentsTagAndInputs() async throws {
        _ = try await bootstrap(setSecret: setEverySecret)
        let record = try #require(try Record.read(in: project.root))
        #expect(record.components == [
            "demo": Record.Entry(tag: "v1", inputs: ["app": "demo-api", "region": "sjc", "team": "core"]),
        ])
    }

    @Test func aMissingSecretIsSetFromItsSource() async throws {
        let result = try await bootstrap(setSecret: setEverySecret)
        #expect(Set(result.secretsSet) == ["DEPLOY_TOKEN", "SIGNING_KEY", "WEBHOOK_SECRET"])
        #expect(stubs.github["DEPLOY_TOKEN"] == "deploy-token-value")
        #expect(stubs.github["SIGNING_KEY"] == "signing-key-value")
        #expect(result.report.missingSecrets.isEmpty)

        // A generated secret is made and kept in the Keychain first.
        #expect(result.secretsGenerated == ["WEBHOOK_SECRET"])
        let generated = try #require(stubs.keychain["superlinear.webhook-secret"])
        #expect(generated.count == 64)
        #expect(stubs.github["WEBHOOK_SECRET"] == generated)

        // A local secret is never set in GitHub.
        #expect(stubs.github["LOCAL_TOKEN"] == nil)

        // No value is in the report, the README or the record.
        let json = String(decoding: try result.report.json(), as: UTF8.self)
        for text in [json, project.read("README.md") ?? "", project.read(Record.fileName) ?? ""] {
            for value in ["deploy-token-value", "signing-key-value", "local-token-value", generated] {
                #expect(!text.contains(value))
            }
        }
    }

    @Test func aSecretIsNotSetWithoutConfirmation() async throws {
        let result = try await bootstrap(setSecret: { _ in false })
        #expect(stubs.github.isEmpty)
        #expect(stubs.keychain["superlinear.webhook-secret"] == nil)
        #expect(result.report.missingSecrets.map(\.name) == ["DEPLOY_TOKEN", "SIGNING_KEY", "WEBHOOK_SECRET"])
        let human = try #require(result.report.humanSteps.first { $0.id == "secret:SIGNING_KEY" })
        #expect(human.text == "Make a signing key for demo-api.")
    }

    @Test func aLocalSecretIsOnlyCheckedInTheKeychain() async throws {
        let empty = Stubs()
        let bootstrapper = Bootstrapper(templates: Templates(root: templates.root, tag: "v1", tags: []), services: empty.services())
        let report = try await bootstrapper.check(repository: project.root)
        let local = try #require(report.missingSecrets.first { $0.name == "LOCAL_TOKEN" })
        #expect(local.scope == "local")
        #expect(report.humanSteps.filter { $0.id == "secret:LOCAL_TOKEN" }.map(\.twoFactor) == [true])
    }

    @Test func aFailedHumanStepIsReportedOnceWithItsText() async throws {
        let result = try await bootstrap(setSecret: setEverySecret)
        let steps = result.report.humanSteps.filter { $0.id == "dns" }
        #expect(steps.count == 1)
        let step = try #require(steps.first)
        #expect(step.text == "Point the domain at demo-api in sjc.")
        #expect(step.twoFactor)
        #expect(step.manifest == "https://github.com/armcknight/templatr/blob/v1/components/demo/component.toml")
        #expect(step.guide == [Link(title: "Builds", url: "https://github.com/armcknight/superlinear/blob/main/docs/builds.md#ci")])
        #expect(result.report.failedSteps.isEmpty)

        try project.write(".dns-done", "")
        let after = try await bootstrap(setSecret: setEverySecret)
        #expect(after.report.humanSteps.isEmpty)
    }

    @Test func theReadmeSectionChangesOnlyBetweenItsMarkers() async throws {
        _ = try await bootstrap(setSecret: setEverySecret)
        let readme = try #require(project.read("README.md"))
        let begin = try #require(readme.range(of: Validator.beginMarker))
        let end = try #require(readme.range(of: Validator.endMarker))
        #expect(readme[..<begin.lowerBound] == "# Demo\n\nIntro text.\n\n")
        #expect(readme[end.upperBound...] == "\n\nFooter.\n")

        let section = readme[begin.upperBound..<end.lowerBound]
        #expect(!section.contains("Old text."))
        #expect(section.contains("## How this project is built"))
        #expect(section.contains("[demo](https://github.com/armcknight/templatr/tree/v1/components/demo) at `v1`"))
        #expect(section.contains("[make/demo.mk](https://github.com/armcknight/templatr/blob/v1/make/demo.mk)"))
        #expect(section.contains("`DEPLOY_TOKEN` (app)"))
        #expect(section.contains("From the Keychain item `demo.demo-api.deploy-token`."))
        #expect(section.contains("Point the domain at demo-api in sjc."))
        #expect(section.contains("[Linear](https://linear.app/demo)"))
        #expect(section.contains("https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#overview"))
    }

    @Test func aReadmeWithoutMarkersGetsTheSectionAtItsEnd() async throws {
        try project.write("README.md", "# Demo\n\nMine.\n")
        _ = try await bootstrap(setSecret: setEverySecret)
        let readme = try #require(project.read("README.md"))
        #expect(readme.hasPrefix("# Demo\n\nMine.\n\n\(Validator.beginMarker)\n"))
        #expect(readme.hasSuffix("\(Validator.endMarker)\n"))
    }

    @Test func claudeMdImportsTheComponentsConventions() async throws {
        try project.write("CLAUDE.md", "# Mine\n")
        _ = try await bootstrap(setSecret: setEverySecret)
        #expect(project.read("CLAUDE.md") == """
            # Mine

            <!-- templatr:begin components -->
            @.templatr/demo/CLAUDE.md
            <!-- templatr:end -->

            """)
        #expect(project.read(".templatr/demo/CLAUDE.md") == "# demo\n\nConventions.\n")
    }

    @Test func checkChangesNothing() async throws {
        let files = project.snapshot()
        let report = try await bootstrapper(tags: ["v1"]).check(repository: project.root)
        #expect(project.snapshot() == files)
        #expect(stubs.github.isEmpty)
        #expect(report.failedSteps.map(\.id) == ["configured"])
        #expect(report.humanSteps.map(\.id).contains("dns"))
        #expect(report.missingSecrets.map(\.name) == ["DEPLOY_TOKEN", "SIGNING_KEY", "WEBHOOK_SECRET"])
        #expect(report.components == [ComponentStatus(name: "demo", tag: "v1", newestTag: "v1")])
        #expect(!report.isClean)
    }

    @Test func checkReportsExpiriesOldTagsAndBrokenLinks() async throws {
        _ = try await bootstrap(setSecret: setEverySecret)
        // The local token was set 80 days ago and is made again every 90.
        let lastSet = stubs.now.addingTimeInterval(-80 * 86_400)
        stubs.setKeychain("demo.local-token", "local-token-value", modified: lastSet)
        try project.write("README.md", (project.read("README.md") ?? "") + "\n[gone](docs/gone.md) [here](fly.toml)\n")

        let report = try await bootstrapper(tags: ["v1", "v1.1", "v2"]).check(repository: project.root)
        #expect(report.expiries.map(\.secret) == ["LOCAL_TOKEN"])
        #expect(report.expiries.first?.lastSet == lastSet)
        #expect(report.oldTags == [OldTag(component: "demo", tag: "v1", newest: "v2")])
        #expect(report.brokenLinks == [BrokenLink(file: "README.md", link: "docs/gone.md")])
    }

    @Test func aFullTagInTheSameMajorIsNotAnOldTag() async throws {
        _ = try await bootstrap(setSecret: setEverySecret)
        let tags = TagList("v1\nv1.0.0\nv1.0.1\nv2.0.0-RC1\n0.1.0\n")
        let checkout = try Templates.checkout(at: templates.root, tag: nil, runner: tags)
        #expect(checkout.tag == "v1")
        #expect(checkout.tags == ["v1"])
        #expect(try Templates.checkout(at: templates.root, tag: "v1.0.1", runner: tags).tag == "v1.0.1")

        let report = try await Bootstrapper(templates: checkout, services: stubs.services()).check(repository: project.root)
        #expect(report.oldTags.isEmpty)
        #expect(report.components == [ComponentStatus(name: "demo", tag: "v1", newestTag: "v1")])
    }

    @Test func aCheckoutWithoutAnAliasNeedsATag() throws {
        #expect(throws: TemplatrError.self) {
            try Templates.checkout(at: templates.root, tag: nil, runner: TagList("v1.0.0\n"))
        }
    }

    @Test func checkReportsCertificatesThatExpireWithin30Days() async throws {
        let formatter = ISO8601DateFormatter()
        func date(days: Double) -> String { formatter.string(from: stubs.now.addingTimeInterval(days * 86_400)) }
        try project.write("certs.tsv", """
            \(date(days: 90))\tApple Distribution: Demo (TEAM)
            \(date(days: 29))\tmatch AppStore io.demo.app

            \(date(days: -1))\tmatch AdHoc io.demo.app.adhoc
            """)
        let report = try await bootstrapper(tags: ["v1"]).check(repository: project.root)
        #expect(report.certificateExpiries.map(\.name) == ["match AppStore io.demo.app", "match AdHoc io.demo.app.adhoc"])
        let expiry = try #require(report.certificateExpiries.first)
        #expect(expiry.component == "demo")
        #expect(expiry.id == "signing")
        #expect(formatter.string(from: expiry.expires) == date(days: 29))
        #expect(expiry.text == "Renew the signing certificates of demo-api.")
        #expect(expiry.twoFactor)
        #expect(report.errors.isEmpty)
    }

    @Test func certificatesThatCannotBeListedAreAnError() async throws {
        try project.write("certs.fail", "")
        let report = try await bootstrapper(tags: ["v1"]).check(repository: project.root)
        #expect(report.certificateExpiries.isEmpty)
        #expect(report.errors == ["Could not list demo/signing: Could not read the certificates of demo-api."])

        try project.delete("certs.fail")
        try project.write("certs.tsv", "next week\tA certificate\n")
        let unreadable = try await bootstrapper(tags: ["v1"]).check(repository: project.root)
        #expect(unreadable.errors == [
            "demo/signing printed a line that is not <ISO 8601 date>\t<name>: next week\tA certificate",
        ])
    }

    @Test func certificatesThatNeedAMissingInputAreNotListed() async throws {
        try project.write("fly.toml", "primary_region = \"sjc\"\n")
        try project.write("certs.fail", "")
        let report = try await bootstrapper(tags: ["v1"]).check(repository: project.root)
        #expect(report.errors.isEmpty)
        #expect(report.blockedSteps.contains(BlockedStep(
            component: "demo", id: "certificates:signing", description: "The signing certificates.", missingInputs: ["app"]
        )))
    }

    @Test func aHandWrittenRecordWinsAndNewComponentsAreOnlyReported() async throws {
        try project.write(Record.fileName, """
            [components.demo]
            tag = "v1"

            [components.demo.inputs]
            app = "by-hand"

            """)
        try project.write("OTHER", "")
        let result = try await bootstrap(setSecret: setEverySecret)
        #expect(result.report.newComponents == ["other"])
        let record = try #require(try Record.read(in: project.root))
        #expect(record.components.keys.sorted() == ["demo"])
        #expect(record.components["demo"]?.inputs["app"] == "by-hand")
        #expect(FileManager.default.fileExists(atPath: project.root.appending(path: "config/by-hand.conf").path))
    }

    @Test func stepsThatNeedAMissingInputAreNotRun() async throws {
        try project.write("fly.toml", "app = \"demo-api\"\n")
        let result = try await bootstrap(setSecret: setEverySecret)
        #expect(result.report.missingInputs.map(\.name) == ["region"])
        // The dns step's check does not use the region, so it runs; its human
        // text keeps the placeholder.
        #expect(result.report.humanSteps.first { $0.id == "dns" }?.text == "Point the domain at demo-api in {{inputs.region}}.")
        #expect(result.fixedSteps == ["demo/configured"])

        let answered = try await bootstrapper(tags: []).bootstrap(
            repository: project.root,
            options: BootstrapOptions(answers: ["demo": ["region": "ams"]], links: [], setSecret: setEverySecret)
        )
        #expect(answered.report.missingInputs.isEmpty)
        #expect(try Record.read(in: project.root)?.components["demo"]?.inputs["region"] == "ams")
    }

    @Test func aSecretWhoseSourceNeedsAMissingInputIsNotRead() async throws {
        try project.write("fly.toml", "primary_region = \"sjc\"\n")
        stubs.setKeychain("demo.{{inputs.app}}.deploy-token", "wrong-value", modified: stubs.now)
        let result = try await bootstrap(setSecret: setEverySecret)
        #expect(result.report.missingInputs.map(\.name) == ["app"])
        #expect(stubs.github["DEPLOY_TOKEN"] == nil)
        let missing = try #require(result.report.missingSecrets.first { $0.name == "DEPLOY_TOKEN" })
        #expect(missing.source == "keychain:demo.{{inputs.app}}.deploy-token")
    }

    @Test func aRepositoryWithNoComponentIsReported() async throws {
        let empty = try Directory()
        let result = try await bootstrapper(tags: []).bootstrap(
            repository: empty.root, options: BootstrapOptions(answers: [:], links: [], setSecret: setEverySecret)
        )
        #expect(result.report.errors == ["No component matches this repository."])
        #expect(empty.snapshot().isEmpty)
    }
}

/// Answers `git tag --list` with `tags`.
struct TagList: CommandRunner {
    var tags: String

    init(_ tags: String) {
        self.tags = tags
    }

    func run(_ arguments: [String], input: Data?, in directory: URL?) throws -> CommandResult {
        CommandResult(status: 0, output: Data(tags.utf8), error: Data())
    }
}
