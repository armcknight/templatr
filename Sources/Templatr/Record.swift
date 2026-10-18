import Foundation
import TOMLKit

/// `.templatr.toml` at a repository's root: the components the project uses,
/// the tag each is pinned to, and its inputs. Later runs read it instead of
/// detecting again, and a file written by hand wins over detection.
///
/// ```toml
/// [components.apple-app]
/// tag = "v1"
///
/// [components.apple-app.inputs]
/// bundle_id = "io.mcknight.babysittr"
/// ```
public struct Record: Equatable, Sendable {
    public static let fileName = ".templatr.toml"

    public var components: [String: Entry]

    public struct Entry: Codable, Equatable, Sendable {
        public var tag: String
        public var inputs: [String: String]

        public init(tag: String, inputs: [String: String]) {
            self.tag = tag
            self.inputs = inputs
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            tag = try container.decode(String.self, forKey: .tag)
            inputs = try container.decodeIfPresent([String: String].self, forKey: .inputs) ?? [:]
        }
    }

    private struct File: Decodable {
        var components: [String: Entry]?
    }

    public init(components: [String: Entry]) {
        self.components = components
    }

    public init(toml: String) throws {
        do {
            components = try TOMLDecoder().decode(File.self, from: toml).components ?? [:]
        } catch {
            throw TemplatrError("\(Self.fileName): \(error)")
        }
    }

    /// The record in `repository`, or `nil` when it has none.
    public static func read(in repository: URL) throws -> Record? {
        let url = repository.appending(path: fileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return try Record(toml: text)
    }

    /// The record as TOML, the same text for the same record.
    public func toml() -> String {
        var lines = [
            "# The armcknight/templatr components this project uses. `templatr bootstrap`",
            "# writes it; a change made by hand wins over detection.",
        ]
        for name in components.keys.sorted() {
            let entry = components[name]!
            lines += ["", "[components.\(Self.key(name))]", "tag = \(Self.string(entry.tag))"]
            if !entry.inputs.isEmpty {
                lines += ["", "[components.\(Self.key(name)).inputs]"]
                for input in entry.inputs.keys.sorted() {
                    lines.append("\(Self.key(input)) = \(Self.string(entry.inputs[input]!))")
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func key(_ key: String) -> String {
        key.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil ? key : string(key)
    }

    /// A TOML basic string.
    private static func string(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\t": result += "\\t"
            case "\r": result += "\\r"
            case _ where scalar.value < 0x20 || scalar.value == 0x7F:
                result += String(format: "\\u%04X", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
