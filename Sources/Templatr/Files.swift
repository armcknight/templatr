import Foundation

/// A path pattern relative to the repository root: `*` matches any characters
/// but `/`, `?` one of them, and a `**` segment any number of directories,
/// none included.
struct Glob {
    let pattern: String
    private let regex: NSRegularExpression?

    init(_ pattern: String) {
        self.pattern = pattern
        var expression = "^"
        let segments = pattern.split(separator: "/", omittingEmptySubsequences: false)
        for (index, segment) in segments.enumerated() {
            let last = index == segments.count - 1
            if segment == "**" {
                expression += last ? ".*" : "(?:[^/]+/)*"
                continue
            }
            for character in segment {
                switch character {
                case "*": expression += "[^/]*"
                case "?": expression += "[^/]"
                default: expression += NSRegularExpression.escapedPattern(for: String(character))
                }
            }
            if !last { expression += "/" }
        }
        regex = try? NSRegularExpression(pattern: expression + "$")
    }

    func matches(_ path: String) -> Bool {
        regex?.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }
}

/// The files and directories of a repository, read one time.
struct RepositoryFiles {
    let root: URL
    /// Relative paths, shallowest first, then in order.
    let paths: [String]
    let directories: Set<String>

    /// Directories that hold no source: version control, build products and
    /// downloaded dependencies. Only a directory walk skips them; git skips
    /// what the repository ignores.
    static let skipped: Set<String> = [".git", ".build", ".swiftpm", "DerivedData", "node_modules", "Pods"]

    /// The files git lists in `root`, tracked and untracked but not ignored,
    /// and their directories. A submodule is one directory, without its
    /// contents. When `root` is not a git checkout, the files of a directory
    /// walk.
    init(root: URL, runner: CommandRunner = ProcessRunner()) {
        self.root = root
        let (paths, directories) = Self.gitFiles(root: root, runner: runner) ?? Self.walk(root: root)
        self.paths = paths.sorted { lhs, rhs in
            let (left, right) = (lhs.split(separator: "/").count, rhs.split(separator: "/").count)
            return left == right ? lhs < rhs : left < right
        }
        self.directories = directories
    }

    /// The paths from `git ls-files`, with the directories that hold them, or
    /// `nil` when git cannot list them.
    private static func gitFiles(root: URL, runner: CommandRunner) -> (Set<String>, Set<String>)? {
        let arguments = ["git", "-C", root.path, "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
        guard let result = try? runner.run(arguments, input: nil, in: nil), result.succeeded else { return nil }
        var paths: Set<String> = []
        var directories: Set<String> = []
        for entry in result.text.split(separator: "\0") {
            // An untracked repository inside this one ends in a slash.
            let path = entry.hasSuffix("/") ? String(entry.dropLast()) : String(entry)
            // A tracked file deleted from the working tree is still listed.
            var isDirectory: ObjCBool = false
            guard !path.isEmpty, FileManager.default.fileExists(atPath: root.appending(path: path).path, isDirectory: &isDirectory)
            else { continue }
            paths.insert(path)
            // A submodule and an untracked repository are directories.
            if isDirectory.boolValue { directories.insert(path) }
            var parent = (path as NSString).deletingLastPathComponent
            while !parent.isEmpty, directories.insert(parent).inserted {
                paths.insert(parent)
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return (paths, directories)
    }

    /// Every path under `root` but those in the skipped directories.
    private static func walk(root: URL) -> (Set<String>, Set<String>) {
        var paths: Set<String> = []
        var directories: Set<String> = []
        if let enumerator = FileManager.default.enumerator(atPath: root.path) {
            while let path = enumerator.nextObject() as? String {
                let type = enumerator.fileAttributes?[.type] as? FileAttributeType
                if type == .typeDirectory {
                    if skipped.contains((path as NSString).lastPathComponent) {
                        enumerator.skipDescendants()
                        continue
                    }
                    directories.insert(path)
                }
                paths.insert(path)
            }
        }
        return (paths, directories)
    }

    /// The paths that match `glob`, files and directories.
    func matching(_ glob: String) -> [String] {
        let glob = Glob(glob)
        return paths.filter(glob.matches)
    }

    /// The files that match `glob`, without the directories.
    func files(matching glob: String) -> [String] {
        matching(glob).filter { !directories.contains($0) }
    }

    func text(of path: String) -> String? {
        try? String(contentsOf: root.appending(path: path), encoding: .utf8)
    }
}

enum Patterns {
    /// The match of `pattern` in `text`, or `nil` when it does not match or does
    /// not compile.
    static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    static func matches(_ pattern: String, _ text: String) -> Bool {
        firstMatch(pattern, in: text) != nil
    }

    /// The first capture group of `pattern` in `text`.
    static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let match = firstMatch(pattern, in: text), match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
