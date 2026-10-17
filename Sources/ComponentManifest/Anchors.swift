import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The anchors the superlinear guide's docs/anchors.md lists, each in code as
/// `<page>.md#<id>`.
public enum Anchors {
    /// docs/anchors.md on superlinear's main branch.
    public static let defaultSource = "https://raw.githubusercontent.com/armcknight/superlinear/main/docs/anchors.md"

    /// The anchors listed in the text of docs/anchors.md.
    public static func listed(in markdown: String) -> Set<String> {
        Set(markdown.matches(of: /`([a-z][a-z0-9-]*\.md#[a-z0-9][a-z0-9-]*)`/).map { String($0.1) })
    }

    /// The anchors listed in docs/anchors.md at a path or an `http(s)` URL.
    public static func read(from source: String) async throws -> Set<String> {
        if let url = URL(string: source), let scheme = url.scheme, ["http", "https"].contains(scheme) {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let status = (response as? HTTPURLResponse)?.statusCode, !(200..<300).contains(status) {
                throw AnchorsError.status(status, url)
            }
            guard let text = String(data: data, encoding: .utf8) else { throw AnchorsError.notText(url) }
            return listed(in: text)
        }
        return listed(in: try String(contentsOfFile: source, encoding: .utf8))
    }
}

public enum AnchorsError: Error, CustomStringConvertible {
    case status(Int, URL)
    case notText(URL)

    public var description: String {
        switch self {
        case .status(let status, let url): "\(url) answered \(status)"
        case .notText(let url): "\(url) is not UTF-8 text"
        }
    }
}
