import ComponentManifest
import Foundation

/// A checkout of the templatr repository: its components, the tag that new
/// projects are pinned to, and the major-version aliases it has.
public struct Templates: Sendable {
    /// The checkout's root, which `{{templates}}` stands for.
    public var root: URL
    /// The tag that a component is pinned to when it is first recorded.
    public var tag: String
    /// The major-version aliases, such as `v1` and `v2`, to find components
    /// behind the newest one. The full tags, such as `v1.0.1`, are not here:
    /// a project pinned to `v1` gets them through the alias.
    public var tags: [String]

    public static let repository = "armcknight/templatr"
    public static let url = "https://github.com/\(repository)"

    public init(root: URL, tag: String, tags: [String]) {
        self.root = root.standardizedFileURL
        self.tag = tag
        self.tags = tags
    }

    /// The checkout at `root`, with its aliases from git. `tag` defaults to
    /// its newest alias; a full tag, such as `v1.0.1`, may be given.
    /// - Throws: `TemplatrError` when there is no alias and no tag is given.
    public static func checkout(at root: URL, tag: String?, runner: any CommandRunner) throws -> Templates {
        let result = try? runner.run(["git", "-C", root.path, "tag", "--list", "v*"], input: nil, in: nil)
        let tags = (result?.succeeded ?? false)
            ? result!.text.split(whereSeparator: \.isNewline).map(String.init).filter(Version.isAlias) : []
        guard let tag = tag ?? Version.newest(of: tags) else {
            throw TemplatrError("\(root.path) has no v<major> tag, such as v1, to pin components to; give one with --tag")
        }
        return Templates(root: root, tag: tag, tags: tags)
    }

    /// Every component, by name.
    public func components() throws -> [Component] {
        let directory = root.appending(path: "components")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        return try names.compactMap { name in
            let manifest = directory.appending(path: "\(name)/component.toml")
            guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
            do {
                return Component(manifest: try Manifest(contentsOf: manifest), directory: directory.appending(path: name))
            } catch {
                throw TemplatrError("components/\(name)/component.toml: \(error)")
            }
        }
    }
}

/// A component in the templatr checkout.
public struct Component: Sendable {
    public var manifest: Manifest
    public var directory: URL

    public var name: String { manifest.name }

    /// The files copied into a project, at the paths they have there.
    public var scaffold: URL { directory.appending(path: "scaffold") }

    /// Where the component's files are in `repository`: its `directory`, or
    /// the root.
    public func root(in repository: URL) -> URL {
        manifest.directory.map { repository.appending(path: $0) } ?? repository
    }

    /// The manifest on GitHub at `tag`.
    public func manifestLink(tag: String) -> String {
        "\(Templates.url)/blob/\(tag)/components/\(name)/component.toml"
    }

    /// The component's directory on GitHub at `tag`.
    public func link(tag: String) -> String {
        "\(Templates.url)/tree/\(tag)/components/\(name)"
    }

    /// The guide sections that the manifest's `docs` names.
    public var guide: [Link] {
        manifest.docs.map { Link(title: $0.title, url: Guide.url($0.anchor)) }
    }
}

/// The superlinear guide.
enum Guide {
    static func url(_ anchor: String) -> String {
        "https://github.com/armcknight/superlinear/blob/main/docs/\(anchor)"
    }

    /// The sections every project's README links to.
    static let sections: [Link] = [
        Link(title: "The life of an issue", url: url("lifecycle.md#overview")),
        Link(title: "Planning", url: url("planning.md#proposals")),
        Link(title: "Bootstrap", url: url("bootstrap.md#components")),
        Link(title: "Builds", url: url("builds.md#ci")),
    ]
}

/// A titled URL.
public struct Link: Codable, Equatable, Sendable {
    public var title: String
    public var url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }
}

/// A problem that stops a command, such as a manifest that does not decode.
public struct TemplatrError: Error, CustomStringConvertible, Sendable {
    public var description: String

    public init(_ description: String) {
        self.description = description
    }
}

/// Release tags: the full tags, as `v1.0.0` or `v1.1.0-RC1`, and the
/// major-version aliases that projects are pinned to, as `v1`.
enum Version {
    /// The numbers in `tag`, or `nil` when it is not a `v` tag. A prerelease
    /// suffix, as in `v1.1.0-RC1`, is not a version.
    static func parts(_ tag: String) -> [Int]? {
        guard tag.hasPrefix("v") else { return nil }
        let parts = tag.dropFirst().split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }

    /// Whether `tag` is a major-version alias, such as `v1`.
    static func isAlias(_ tag: String) -> Bool {
        parts(tag)?.count == 1
    }

    /// Whether a component pinned to `tag` is behind the alias `newest`: its
    /// major version is older. `v1` and `v1.0.1` are both behind `v2`, and
    /// neither is behind `v1`.
    static func isBehind(_ tag: String, _ newest: String) -> Bool {
        guard let pinned = parts(tag)?.first, let alias = parts(newest)?.first else { return false }
        return pinned < alias
    }

    /// The newest alias in `tags`.
    static func newest(of tags: [String]) -> String? {
        tags.filter(isAlias).max { parts($0)![0] < parts($1)![0] }
    }
}
