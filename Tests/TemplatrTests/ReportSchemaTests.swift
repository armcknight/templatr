import Foundation
import Testing
@testable import Templatr

/// schema/check-report.schema.json and `Report` have the same keys, so the
/// stable format that superlinear reads does not differ from what is written.
@Suite struct ReportSchemaTests {
    /// A report with every field set.
    static var full: Report {
        var report = Report()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let guide = [Link(title: "Builds", url: "https://example.com/builds.md#ci")]
        report.components = [ComponentStatus(name: "demo", tag: "v1", newestTag: "v2")]
        report.newComponents = ["other"]
        report.unknownComponents = ["gone"]
        report.missingInputs = [MissingInput(component: "demo", name: "app", description: "The app.", example: "x")]
        report.failedSteps = [FailedStep(component: "demo", id: "a", description: "A.", output: "no")]
        report.blockedSteps = [BlockedStep(component: "demo", id: "b", description: "B.", missingInputs: ["app"])]
        report.humanSteps = [HumanStep(
            component: "demo", id: "c", description: "C.", text: "Do it.", twoFactor: true,
            manifest: "https://example.com/component.toml", guide: guide
        )]
        report.missingSecrets = [MissingSecret(component: "demo", name: "TOKEN", scope: "app", source: "keychain:x")]
        report.expiries = [Expiry(component: "demo", secret: "TOKEN", rotateEvery: "90d", lastSet: date, due: date)]
        report.certificateExpiries = [CertificateExpiry(
            component: "demo", id: "signing", name: "Apple Distribution", expires: date, text: "Renew it.", twoFactor: true
        )]
        report.oldTags = [OldTag(component: "demo", tag: "v1", newest: "v2")]
        report.brokenLinks = [BrokenLink(file: "README.md", link: "gone.md")]
        report.errors = ["gh failed"]
        return report
    }

    @Test func theReportHasTheSchemasKeys() throws {
        let schema = try JSONSerialization.jsonObject(
            with: Data(contentsOf: repositoryRoot.appending(path: "schema/check-report.schema.json"))
        ) as! [String: Any]
        let report = try JSONSerialization.jsonObject(with: Self.full.json()) as! [String: Any]
        #expect(Self.keys(of: report, at: "") == Self.keys(ofSchema: schema, at: ""))
    }

    @Test func theReportRoundTrips() throws {
        #expect(try Report.decode(json: Self.full.json()) == Self.full)
    }

    /// Every key path in a JSON value, as `humanSteps.guide.url`.
    static func keys(of value: Any, at path: String) -> Set<String> {
        switch value {
        case let object as [String: Any]:
            object.reduce(into: Set<String>()) { keys, entry in
                let child = path.isEmpty ? entry.key : "\(path).\(entry.key)"
                keys.insert(child)
                keys.formUnion(Self.keys(of: entry.value, at: child))
            }
        case let array as [Any]:
            array.reduce(into: Set<String>()) { $0.formUnion(keys(of: $1, at: path)) }
        default:
            []
        }
    }

    /// Every key path that a JSON Schema's `properties` name.
    static func keys(ofSchema schema: [String: Any], at path: String) -> Set<String> {
        if let items = schema["items"] as? [String: Any] {
            return keys(ofSchema: items, at: path)
        }
        guard let properties = schema["properties"] as? [String: Any] else { return [] }
        return properties.reduce(into: Set<String>()) { keys, entry in
            let child = path.isEmpty ? entry.key : "\(path).\(entry.key)"
            keys.insert(child)
            keys.formUnion(Self.keys(ofSchema: entry.value as! [String: Any], at: child))
        }
    }
}
