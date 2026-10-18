import Foundation
import Testing
@testable import ComponentManifest

@Suite("Decoding")
struct DecodingTests {
    /// The error decoding `toml`, which must not decode.
    func error(decoding toml: String) -> ManifestError? {
        do {
            _ = try Manifest(toml: toml)
            Issue.record("decoded")
            return nil
        } catch let error as ManifestError {
            return error
        } catch {
            Issue.record(error)
            return nil
        }
    }

    @Test func theDemoManifestDecodes() throws {
        let decoded = try Manifest(toml: manifest)
        #expect(decoded.name == "demo")
        #expect(decoded.detect?.all == [DetectRule(glob: "fly.toml", contains: nil, root: false)])
        #expect(decoded.detect?.any == [DetectRule(glob: "Package.swift", contains: "vapor", root: false)])
        #expect(decoded.inputs[0].infer == [InferRule(from: .toml(file: "fly.toml", key: "app"), map: nil, root: false)])
        #expect(decoded.inputs[1].infer?[0].from == .regex(glob: "fly.toml", pattern: #"primary_region = "([a-z]+)""#))
        #expect(decoded.secrets[0].source == .keychain(item: "demo.fly-token"))
        #expect(decoded.secrets[0].scope == .app)
        #expect(decoded.secrets[0].human == Human(text: "Make a deploy token for {{inputs.app}}.", twoFactor: true))
        #expect(decoded.secrets[0].rotateEvery == RotationPeriod(count: 90, unit: .days))
        #expect(decoded.steps[0].scope == .repo)
        #expect(decoded.steps[0].fix == .command("fly apps create {{inputs.app}}"))
        #expect(decoded.steps[1].fix == .human(Human(text: "Point the domain at {{inputs.app}}.", twoFactor: false)))
        #expect(decoded.shared[0].link == ".github/workflows/demo.yml")
        #expect(decoded.docs == [Doc(title: "Builds", anchor: "builds.md#ci")])
        #expect(decoded.certificates == [Certificate(
            id: "tls", description: "The app's TLS certificate.", list: "fly certs list --app {{inputs.app}}",
            renew: Human(text: "Renew the TLS certificate of {{inputs.app}}.", twoFactor: false)
        )])
    }

    @Test func certificatesAreOptional() throws {
        let start = try #require(manifest.range(of: "[[certificates]]"))
        let decoded = try Manifest(toml: String(manifest[..<start.lowerBound]))
        #expect(decoded.certificates.isEmpty)
        #expect(try decoded.toml().contains("certificates") == false)
        #expect(try Manifest(toml: decoded.toml()) == decoded)
    }

    @Test func certificatesNeedAnElement() {
        let start = manifest.range(of: "[[certificates]]")!
        #expect(error(decoding: "certificates = []\n" + manifest[..<start.lowerBound])?.path == "certificates")
    }

    @Test func certificatesNeedRenewText() {
        let error = error(decoding: manifest.replacingOccurrences(
            of: #"renew = { text = "Renew the TLS certificate of {{inputs.app}}." }"#, with: ""
        ))
        #expect(error?.path == "certificates/0")
        #expect(error?.message == "'renew' is required")
    }

    @Test func theManifestRoundTripsThroughToml() throws {
        let decoded = try Manifest(toml: manifest)
        let again = try Manifest(toml: decoded.toml())
        #expect(again == decoded)
    }

    @Test func aRootRuleDecodesAndRoundTrips() throws {
        let toml = manifest
            .replacingOccurrences(
                of: #"{ glob = "Package.swift", contains = "vapor" }"#,
                with: #"{ glob = "server/Package.swift", contains = "vapor", root = true }"#
            )
            .replacingOccurrences(
                of: #"{ from = "toml", file = "fly.toml", key = "app" }"#,
                with: #"{ from = "toml", file = "server/fly.toml", key = "app", root = true }"#
            )
        let decoded = try Manifest(toml: toml)
        #expect(decoded.detect?.any == [DetectRule(glob: "server/Package.swift", contains: "vapor", root: true)])
        #expect(decoded.detect?.all == [DetectRule(glob: "fly.toml", contains: nil, root: false)])
        #expect(decoded.inputs[0].infer == [InferRule(from: .toml(file: "server/fly.toml", key: "app"), map: nil, root: true)])
        #expect(try Manifest(toml: decoded.toml()) == decoded)
    }

    @Test func thisRepositoryDecodesAndRoundTrips() throws {
        let url = repositoryRoot.appending(path: "components/apple-app/component.toml")
        let decoded = try Manifest(contentsOf: url)
        #expect(decoded.name == "apple-app")
        #expect(decoded.inputs.contains {
            $0.name == "platforms" && $0.infer?[0].from == .buildSetting(key: "SUPPORTED_PLATFORMS", separator: " ")
                && $0.infer?[0].map?["iphonesimulator"] == "ios"
        })
        #expect(decoded.shared.contains {
            $0.link == "https://github.com/armcknight/workflows/blob/4/.github/workflows/ios-ci.yml"
        })
        #expect(decoded.certificates.map(\.id) == ["match"])
        #expect(try Manifest(toml: decoded.toml()) == decoded)
    }

    @Test func anUnknownKeyAtTheRootIsAnError() {
        let error = error(decoding: "color = \"red\"\n" + manifest)
        #expect(error?.path == "(root)")
        #expect(error?.message.contains("'color' was unexpected") == true)
    }

    @Test func anUnknownKeyInATableHasItsPath() {
        let error = error(decoding: manifest.replacingOccurrences(of: "rotateEvery", with: "rotate_every"))
        #expect(error?.path == "secrets/0")
        #expect(error?.message.contains("'rotate_every' was unexpected") == true)
    }

    @Test func anUnknownKeyInAnInlineTableHasItsPath() {
        let error = error(decoding: manifest.replacingOccurrences(of: "twoFactor = true", with: "twoFactor = true, mfa = true"))
        #expect(error?.path == "secrets/0/human")
        #expect(error?.message.contains("'mfa' was unexpected") == true)
    }

    @Test func anInferRuleOnlyHasTheKeysOfItsSource() {
        let error = error(decoding: manifest.replacingOccurrences(
            of: #"{ from = "toml", file = "fly.toml", key = "app" }"#,
            with: #"{ from = "toml", file = "fly.toml", key = "app", glob = "*" }"#
        ))
        #expect(error?.path == "inputs/0/infer/0")
        #expect(error?.message.contains("'glob' was unexpected for from = \"toml\"") == true)
    }

    @Test func anUnknownSourceIsAnError() {
        let error = error(decoding: manifest.replacingOccurrences(of: #"from = "toml""#, with: #"from = "json""#))
        #expect(error?.path == "inputs/0/infer/0/from")
        #expect(error?.message == "'json' is not one of build-setting, fastlane-config, toml, yaml, glob, regex")
    }

    @Test func aMissingKeyIsAnError() {
        let error = error(decoding: manifest.replacingOccurrences(of: "example = \"sjc\"\n", with: ""))
        #expect(error?.path == "inputs/1")
        #expect(error?.message == "'example' is required")
    }

    @Test func anEmptyTextIsAnError() {
        let error = error(decoding: manifest.replacingOccurrences(of: #"title = "Builds""#, with: #"title = """#))
        #expect(error?.path == "docs/0/title")
        #expect(error?.message == "is empty")
    }

    @Test func detectNeedsRules() {
        #expect(error(decoding: manifest.replacingOccurrences(
            of: "all = [{ glob = \"fly.toml\" }]\nany = [{ glob = \"Package.swift\", contains = \"vapor\" }]", with: ""
        ))?.path == "detect")
        #expect(error(decoding: manifest.replacingOccurrences(
            of: "all = [{ glob = \"fly.toml\" }]", with: "all = []"
        ))?.path == "detect/all")
    }

    @Test func docsNeedsAnElement() {
        let error = error(decoding: "docs = []\n" + manifest.replacingOccurrences(
            of: "[[docs]]\ntitle = \"Builds\"\nanchor = \"builds.md#ci\"", with: ""
        ))
        #expect(error?.path == "docs")
    }

    @Test func aStepFixIsACommandOrAHumanStep() {
        let error = error(decoding: manifest.replacingOccurrences(
            of: #"fix = { human = { text = "Point the domain at {{inputs.app}}." } }"#,
            with: #"fix = { script = "point-domain" }"#
        ))
        #expect(error?.path == "steps/1/fix")
        #expect(error?.message.contains("'script' was unexpected") == true)
    }

    @Test func tomlThatDoesNotParseIsAnError() {
        let error = error(decoding: "name = \n")
        #expect(error?.path == nil)
        #expect(error?.message.contains("line 1") == true)
    }

    @Test func secretSourcesAndRotationPeriodsHaveRawValues() {
        #expect(Secret.Source(rawValue: "1password:op://vault/item/field") == .onePassword(reference: "op://vault/item/field"))
        #expect(Secret.Source(rawValue: "generate:ssh-key") == .generate(.sshKey))
        #expect(Secret.Source(rawValue: "generate:rsa") == nil)
        #expect(Secret.Source.generate(.hex32).rawValue == "generate:hex32")
        #expect(RotationPeriod(rawValue: "1y") == RotationPeriod(count: 1, unit: .years))
        #expect(RotationPeriod(rawValue: "0d") == nil)
        #expect(RotationPeriod(count: 12, unit: .weeks).rawValue == "12w")
    }
}
