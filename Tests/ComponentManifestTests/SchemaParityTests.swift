import Foundation
import Testing
@testable import ComponentManifest

/// schema/component.schema.json is for editors only: the Swift types are the
/// format. These tests keep the two the same.
@Suite("Schema parity")
struct SchemaParityTests {
    let schema: [String: Any]
    let definitions: [String: Any]

    init() throws {
        let data = try Data(contentsOf: repositoryRoot.appending(path: "schema/component.schema.json"))
        schema = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        definitions = try #require(schema["$defs"] as? [String: Any])
    }

    func definition(_ name: String) throws -> [String: Any] {
        try #require(definitions[name] as? [String: Any], "no definition \(name)")
    }

    func properties(of object: [String: Any]) throws -> Set<String> {
        Set(try #require(object["properties"] as? [String: Any], "no properties in \(object)").keys)
    }

    func property(_ name: String, of object: [String: Any]) throws -> [String: Any] {
        try #require((object["properties"] as? [String: Any])?[name] as? [String: Any], "no property \(name)")
    }

    func keys<K: CodingKey & CaseIterable>(_ keys: K.Type) -> Set<String> {
        Set(K.allCases.map(\.stringValue))
    }

    func values<T: RawRepresentable & CaseIterable>(_ type: T.Type) -> Set<String> where T.RawValue == String {
        Set(T.allCases.map(\.rawValue))
    }

    @Test func everyTableHasTheSchemasKeys() throws {
        #expect(try properties(of: schema) == keys(Manifest.CodingKeys.self))
        #expect(try properties(of: property("detect", of: schema)) == keys(Detect.CodingKeys.self))
        #expect(try properties(of: definition("detectRule")) == keys(DetectRule.CodingKeys.self))
        #expect(try properties(of: definition("input")) == keys(Input.CodingKeys.self))
        #expect(try properties(of: definition("human")) == keys(Human.CodingKeys.self))
        #expect(try properties(of: definition("secret")) == keys(Secret.CodingKeys.self))
        #expect(try properties(of: definition("step")) == keys(Step.CodingKeys.self))
        #expect(try properties(of: definition("shared")) == keys(Shared.CodingKeys.self))
        #expect(try properties(of: definition("doc")) == keys(Doc.CodingKeys.self))
    }

    @Test func everyTableRejectsUnknownKeysLikeTheSchema() throws {
        for name in ["detectRule", "input", "human", "secret", "step", "shared", "doc"] {
            #expect(try definition(name)["additionalProperties"] as? Bool == false, Comment(rawValue: name))
        }
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(try property("detect", of: schema)["additionalProperties"] as? Bool == false)
    }

    @Test func everyInferRuleSourceHasTheSchemasKeys() throws {
        let rule = try definition("inferRule")
        #expect(try properties(of: rule) == InferRule.commonKeys)
        let branches = try #require(rule["oneOf"] as? [[String: Any]])
        var sources: Set<String> = []
        var allKeys = InferRule.commonKeys
        for branch in branches {
            let from = try #require(try property("from", of: branch)["const"] as? String)
            let source = try #require(InferRule.Source(rawValue: from), "no source \(from)")
            sources.insert(from)
            #expect(branch["additionalProperties"] as? Bool == false, Comment(rawValue: from))
            let keys = try properties(of: branch)
            #expect(keys == source.keys.union(InferRule.commonKeys), Comment(rawValue: from))
            allKeys.formUnion(keys)
        }
        #expect(sources == values(InferRule.Source.self))
        #expect(allKeys == keys(InferRule.CodingKeys.self))
        #expect(try property("from", of: rule)["enum"] as? [String] == InferRule.Source.allCases.map(\.rawValue))
    }

    @Test func aStepFixIsACommandOrAHumanTable() throws {
        let fix = try property("fix", of: definition("step"))
        let branches = try #require(fix["oneOf"] as? [[String: Any]])
        #expect(branches.count == 2)
        #expect(branches[0]["type"] as? String == "string")
        #expect(try properties(of: branches[1]) == keys(Step.Fix.CodingKeys.self))
        #expect(branches[1]["additionalProperties"] as? Bool == false)
    }

    @Test func everyEnumerationHasTheSchemasValues() throws {
        #expect(try property("scope", of: definition("secret"))["enum"] as? [String] == Secret.Scope.allCases.map(\.rawValue))
        #expect(try property("scope", of: definition("step"))["enum"] as? [String] == Step.Scope.allCases.map(\.rawValue))
        #expect(try property("kind", of: definition("shared"))["enum"] as? [String] == Shared.Kind.allCases.map(\.rawValue))
        let generated = Secret.Source.Generated.allCases.map(\.rawValue).joined(separator: "|")
        #expect(Format.secretSource.pattern.contains("generate:(\(generated))"))
        let units = RotationPeriod.Unit.allCases.map(\.rawValue).joined()
        #expect(Format.rotationPeriod.pattern.hasSuffix("[\(units)]$"))
    }

    @Test func everyPatternIsTheSchemas() throws {
        func pattern(_ object: [String: Any]) throws -> String {
            try #require(object["pattern"] as? String, "no pattern in \(object)")
        }
        #expect(try pattern(definition("slug")) == Format.slug.pattern)
        #expect(try property("directory", of: schema)["$ref"] as? String == "#/$defs/slug")
        #expect(try pattern(definition("identifier")) == Format.identifier.pattern)
        #expect(try pattern(property("name", of: definition("secret"))) == Format.constant.pattern)
        #expect(try pattern(property("source", of: definition("secret"))) == Format.secretSource.pattern)
        #expect(try pattern(property("rotateEvery", of: definition("secret"))) == Format.rotationPeriod.pattern)
        #expect(try pattern(property("repo", of: definition("shared"))) == Format.repository.pattern)
        #expect(try pattern(property("anchor", of: definition("doc"))) == Format.anchor.pattern)

        let shared = try definition("shared")
        let then = try #require(shared["then"] as? [String: Any])
        let otherwise = try #require(shared["else"] as? [String: Any])
        #expect(try pattern(property("version", of: then)) == Format.localVersion.pattern)
        #expect(try pattern(property("version", of: otherwise)) == Format.externalVersion.pattern)

        let branches = try #require(try definition("inferRule")["oneOf"] as? [[String: Any]])
        for branch in branches {
            switch try property("from", of: branch)["const"] as? String {
            case "build-setting": #expect(try pattern(property("key", of: branch)) == Format.constant.pattern)
            case "fastlane-config": #expect(try pattern(property("key", of: branch)) == Format.fastlaneKey.pattern)
            default: break
            }
        }
    }

    @Test func everyRequiredKeyIsRequiredInSwift() throws {
        func required(_ object: [String: Any]) -> Set<String> { Set(object["required"] as? [String] ?? []) }
        // detect is required unless base is true; base, directory and blurb
        // are optional.
        #expect(required(schema) == keys(Manifest.CodingKeys.self).subtracting(["base", "directory", "blurb", "detect"]))
        #expect(required(try #require(schema["else"] as? [String: Any])) == ["detect"])
        #expect(try required(definition("detectRule")) == ["glob"])
        #expect(try required(definition("input")) == ["name", "description", "example"])
        #expect(try required(definition("human")) == ["text"])
        #expect(try required(definition("secret")) == ["name", "description", "source", "scope"])
        #expect(try required(definition("step")) == ["id", "description", "check", "fix"])
        #expect(try required(definition("shared")) == ["kind", "path", "version", "description"])
        #expect(try required(definition("doc")) == ["title", "anchor"])
        let branches = try #require(try definition("inferRule")["oneOf"] as? [[String: Any]])
        let requiredBySource = Dictionary(uniqueKeysWithValues: try branches.map {
            (try #require(try property("from", of: $0)["const"] as? String), required($0))
        })
        #expect(requiredBySource == [
            "build-setting": ["key"], "fastlane-config": ["file", "key"], "toml": ["file", "key"],
            "yaml": ["file", "key"], "glob": ["glob"], "regex": ["glob", "pattern"],
        ])
    }
}
