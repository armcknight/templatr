#if os(macOS)
import ComponentManifest
import Foundation
import Testing
@testable import Templatr

/// The linear-workspace component's script, run against a fake Linear API. It
/// is JavaScript for Automation, so these run only on macOS.
@Suite struct LinearWorkspaceTests {
    static let script = repositoryRoot.appending(path: "components/linear-workspace/bin/linear-workspace").path
    static let fixable = ["in-review-state", "triage", "labels", "proposals-view", "onboarding-issues"]
    static let steps = ["linear-key", "todo-state", "initiatives"] + fixable

    /// The step commands' environment: the fake's URL and keys. Both key
    /// variables are given, so that no key from the environment of the tests
    /// is used.
    func environment(_ linear: FakeLinear, key: String, linctlKey: String) -> [String: String] {
        ["LINEAR_API_URL": linear.url, "LINEAR_API_KEY": key, "LINCTL_API_KEY": linctlKey]
    }

    /// The environment with the fake's key in LINEAR_API_KEY.
    func environment(_ linear: FakeLinear) -> [String: String] {
        environment(linear, key: FakeLinear.key, linctlKey: "")
    }

    @discardableResult
    func run(_ action: String, _ step: String, teams: String, environment: [String: String]) throws -> CommandResult {
        let runner = ProcessRunner(environment: environment)
        let result = try runner.run([Self.script, action, step, teams], input: nil, in: nil)
        #expect(!result.transcript.contains(FakeLinear.key), "\(action) \(step) printed the key")
        return result
    }

    @Test func everyCheckPassesOnASetUpWorkspace() throws {
        let linear = try FakeLinear.setUp()
        for step in Self.steps {
            let result = try run("check", step, teams: "", environment: environment(linear))
            #expect(result.succeeded, "\(step): \(result.transcript)")
        }
        #expect(linear.locked { linear.mutations }.isEmpty)
    }

    @Test func everyCheckFailsOnAWorkspaceThatIsNotSetUp() throws {
        let linear = try FakeLinear.notSetUp()
        let expected = [
            "linear-key": "owner@example.com is not an admin of the team OTH, or of the workspace.",
            "in-review-state": "The team TEM has no \"In Review\" state.\nThe team OTH has no \"In Review\" state.",
            "todo-state": "The team TEM has no state of type unstarted, such as Todo.\nThe team OTH has no state of type unstarted, such as Todo.",
            "triage": "Triage is off in the team TEM.\nTriage is off in the team OTH.",
            "labels": #"The team TEM has no label "superlinear: proposed", "superlinear: spec", "superlinear: hands off"."#
                + "\n" + #"The team OTH has no label "superlinear", "superlinear: proposed", "superlinear: spec", "superlinear: hands off"."#,
            "proposals-view": "There is no custom view named \"superlinear proposals\".",
            "onboarding-issues": [
                "TEM-1, \"Get familiar with Linear\", is open.", "TEM-2, \"Set up your teams\", is open.",
                "TEM-3, \"Connect your tools\", is open.", "TEM-4, \"Import your data\", is open.",
                "OTH-1, \"Import your data\", is open.",
            ].joined(separator: "\n"),
            "initiatives": "The workspace has no initiative.",
        ]
        for step in Self.steps {
            let result = try run("check", step, teams: "", environment: environment(linear))
            #expect(result.status == 1, "\(step)")
            #expect(result.transcript == expected[step], "\(step)")
        }
        #expect(linear.locked { linear.mutations }.isEmpty)
    }

    @Test func eachFixSetsUpItsStepAndASecondRunChangesNothing() throws {
        let linear = try FakeLinear.notSetUp()
        for step in Self.fixable {
            let fixed = try run("fix", step, teams: "", environment: environment(linear))
            #expect(fixed.succeeded, "\(step): \(fixed.transcript)")
            let checked = try run("check", step, teams: "", environment: environment(linear))
            #expect(checked.succeeded, "\(step): \(checked.transcript)")

            let mutations = linear.locked { linear.mutations }
            try run("fix", step, teams: "", environment: environment(linear))
            #expect(linear.locked { linear.mutations } == mutations, "\(step)")
        }

        linear.locked {
            for key in ["TEM", "OTH"] {
                let review = linear.states(of: key).first { $0.name == "In Review" }
                #expect(review?.type == "started")
                #expect(review?.position == 2.5)
                #expect(linear.team(key).triageEnabled)
            }
            // "needs human" is a workspace label already: it is not made again.
            #expect(!linear.labels.contains { $0.name == "Needs human" })
            #expect(linear.labels.filter { $0.name == "superlinear: spec" }.count == 2)
            #expect(linear.views.count == 1)
            #expect(linear.favorites == linear.views.map(\.id))
        }
    }

    @Test func theOnboardingFixCancelsOnlyTheFourExactTitlesInTheTeamsChecked() throws {
        let linear = try FakeLinear.notSetUp()
        let fixed = try run("fix", "onboarding-issues", teams: "TEM", environment: environment(linear))
        #expect(fixed.succeeded, "\(fixed.transcript)")
        linear.locked {
            let canceled = linear.issues.filter { linear.stateType(of: $0) == "canceled" }.map(\.identifier)
            #expect(canceled == ["TEM-1", "TEM-2", "TEM-3", "TEM-4"])
            #expect(linear.mutations == Array(repeating: "CancelIssue", count: 4))
        }
        #expect(try run("check", "onboarding-issues", teams: "TEM", environment: environment(linear)).succeeded)
        #expect(try !run("check", "onboarding-issues", teams: "", environment: environment(linear)).succeeded)
    }

    @Test func onlyTheTeamsGivenAreCheckedAndChanged() throws {
        let linear = try FakeLinear.notSetUp()
        #expect(try run("check", "linear-key", teams: "TEM", environment: environment(linear)).succeeded)
        try run("fix", "triage", teams: " TEM ", environment: environment(linear))
        linear.locked {
            #expect(linear.team("TEM").triageEnabled)
            #expect(!linear.team("OTH").triageEnabled)
        }
        let unknown = try run("check", "triage", teams: "TEM NOPE", environment: environment(linear))
        #expect(unknown.status == 1)
        #expect(unknown.transcript == "The key cannot see the team NOPE.")
    }

    @Test func aMisplacedInReviewStateIsMoved() throws {
        let linear = try FakeLinear.setUp()
        linear.locked {
            let index = linear.states.firstIndex { $0.name == "In Review" }!
            linear.states[index].position = 1
        }
        let checked = try run("check", "in-review-state", teams: "", environment: environment(linear))
        #expect(checked.transcript == "The team TEM's \"In Review\" state is not after \"In Progress\".")
        try run("fix", "in-review-state", teams: "", environment: environment(linear))
        #expect(try run("check", "in-review-state", teams: "", environment: environment(linear)).succeeded)
        linear.locked {
            #expect(linear.mutations == ["UpdateState"])
            // Between In Progress, 2, and Done, 3.
            #expect(linear.states.first { $0.name == "In Review" }?.position == 2.5)
        }
    }

    @Test func inReviewGoesAfterTheLastStartedStateWhenDoneIsBeforeIt() throws {
        let linear = try FakeLinear.setUp()
        linear.locked {
            linear.states.removeAll { $0.name == "In Review" }
            let index = linear.states.firstIndex { $0.name == "In Progress" }!
            linear.states[index].position = 5
        }
        try run("fix", "in-review-state", teams: "", environment: environment(linear))
        #expect(try run("check", "in-review-state", teams: "", environment: environment(linear)).succeeded)
        linear.locked {
            #expect(linear.mutations == ["CreateState"])
            #expect(linear.states.first { $0.name == "In Review" }?.position == 6)
        }
    }

    @Test func anInReviewStateOfAnotherTypeIsNotFixed() throws {
        let linear = try FakeLinear.setUp()
        linear.locked {
            let index = linear.states.firstIndex { $0.name == "In Review" }!
            linear.states[index].type = "unstarted"
        }
        let fixed = try run("fix", "in-review-state", teams: "", environment: environment(linear))
        #expect(fixed.status == 1)
        #expect(fixed.transcript.contains("Linear cannot change the type of a state"))
        #expect(linear.locked { linear.mutations }.isEmpty)
    }

    @Test func theProposalsViewsFilterIsCorrectedAndItIsAddedToTheFavorites() throws {
        let linear = try FakeLinear.setUp()
        linear.locked {
            linear.views[0].filterData = ["labels": ["some": ["name": ["eq": "superlinear"]]]]
            linear.favorites = []
        }
        let checked = try run("check", "proposals-view", teams: "", environment: environment(linear))
        #expect(checked.transcript == """
            The view "superlinear proposals" does not show only the open issues labeled "superlinear: proposed".
            The view "superlinear proposals" is not in the key's user's favorites.
            """)
        try run("fix", "proposals-view", teams: "", environment: environment(linear))
        #expect(try run("check", "proposals-view", teams: "", environment: environment(linear)).succeeded)
        linear.locked {
            #expect(linear.mutations == ["UpdateView", "FavoriteView"])
            #expect(linear.views.count == 1)
            #expect(linear.favorites == ["view-1"])
        }
    }

    @Test func theKeyComesFromLinearAPIKeyElseLinctlAPIKey() throws {
        let linear = try FakeLinear.setUp()
        let fromLinctl = try run("check", "linear-key", teams: "", environment: environment(linear, key: "", linctlKey: FakeLinear.key))
        #expect(fromLinctl.succeeded, "\(fromLinctl.transcript)")

        let none = try run("check", "linear-key", teams: "", environment: environment(linear, key: "", linctlKey: ""))
        #expect(none.status == 1)
        #expect(none.transcript == "Neither LINEAR_API_KEY nor LINCTL_API_KEY is set.")

        let wrong = try run("check", "linear-key", teams: "", environment: environment(linear, key: "lin_api_wrong", linctlKey: ""))
        #expect(wrong.status == 1)
        #expect(wrong.transcript == "The Linear API answered: Authentication required, not authenticated")
    }

    @Test func anUnknownStepIsAUsageError() throws {
        let linear = try FakeLinear.setUp()
        #expect(try run("fix", "todo-state", teams: "", environment: environment(linear)).status == 64)
        #expect(try run("check", "nothing", teams: "", environment: environment(linear)).status == 64)
    }

    /// The component's steps, run by the Bootstrapper with the key added to
    /// the environment of its command runner, as superlinear's daemon does.
    @Test func bootstrapSetsUpTheWorkspaceAndCheckReportsWhatIsLeft() async throws {
        let linear = try FakeLinear.notSetUp()
        let project = try Directory()
        try project.write(".envrc", "export LINCTL_API_KEY=$(op read op://Private/Linear/key)\n")
        try project.write(".gitignore", ".build")
        _ = try ProcessRunner().run(["git", "init", "-q"], input: nil, in: project.root)
        try project.write(Record.fileName, """
            [components.linear-workspace]
            tag = "v1"

            [components.linear-workspace.inputs]
            linear_teams = "TEM"

            """)

        let stubs = Stubs()
        var services = stubs.services()
        services.runner = ProcessRunner(environment: environment(linear))
        let bootstrapper = Bootstrapper(templates: Templates(root: repositoryRoot, tag: "v1", tags: ["v1"]), services: services)

        let before = try await bootstrapper.check(repository: project.root)
        #expect(before.failedSteps.map(\.id) == ["envrc-ignored"] + Self.fixable)
        #expect(before.humanSteps.map(\.id) == ["todo-state"])

        let result = try await bootstrapper.bootstrap(
            repository: project.root, options: BootstrapOptions(answers: [:], links: [], setSecret: setEverySecret)
        )
        #expect(result.fixedSteps == (["envrc-ignored"] + Self.fixable).map { "linear-workspace/\($0)" })
        #expect(project.read(".gitignore") == ".build\n.envrc\n")

        let after = try await bootstrapper.check(repository: project.root)
        #expect(after.failedSteps.isEmpty)
        #expect(after.humanSteps.map(\.id) == ["todo-state"])
        linear.locked {
            #expect(!linear.team("OTH").triageEnabled)
        }
    }
}
#endif
