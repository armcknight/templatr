import Foundation
import Testing
@testable import Templatr

/// The files of a git checkout come from `git ls-files`.
@Suite struct RepositoryFilesTests {
    let project: Directory

    /// A checkout with a tracked file, an untracked file, an ignored worktree
    /// and a submodule, each with an Xcode project.
    init() throws {
        project = try Directory()
        try git("init", "--quiet")
        try project.write(".gitignore", "worktrees/\n")
        try project.write("Sources/App.swift", "")
        try project.write("Notes.md", "")
        try project.write("worktrees/feature/Demo.xcodeproj/project.pbxproj", appProject)
        try project.write("Vendor/Kit/Kit.xcodeproj/project.pbxproj", appProject)
        try project.write("Vendor/Kit/Kit.xcconfig", "")
        try git("add", ".gitignore", "Sources/App.swift")
        try git("update-index", "--add", "--cacheinfo", "160000,\(String(repeating: "1", count: 40)),Vendor/Kit")
    }

    let appProject = "productType = \"com.apple.product-type.application\";\n"

    func git(_ arguments: String...) throws {
        let result = try ProcessRunner().run(["git", "-C", project.root.path] + arguments, input: nil, in: nil)
        try #require(result.succeeded, "\(result.transcript)")
    }

    @Test func listsTrackedAndUntrackedFilesShallowestFirst() {
        let files = RepositoryFiles(root: project.root)
        #expect(files.paths == [".gitignore", "Notes.md", "Sources", "Vendor", "Sources/App.swift", "Vendor/Kit"])
        #expect(files.directories == ["Sources", "Vendor", "Vendor/Kit"])
    }

    @Test func skipsTheIgnoredFilesAndTheSubmodulesContents() {
        let files = RepositoryFiles(root: project.root)
        #expect(files.files(matching: "**/*.xcodeproj/project.pbxproj") == [])
        #expect(files.files(matching: "**/*.xcconfig") == [])
    }

    @Test func skipsATrackedFileDeletedFromTheWorkingTree() throws {
        try FileManager.default.removeItem(at: project.root.appending(path: "Sources/App.swift"))
        let files = RepositoryFiles(root: project.root)
        #expect(!files.paths.contains("Sources/App.swift"))
    }

    @Test func doesNotDetectAComponentFromIgnoredFilesOrASubmodule() throws {
        let bootstrapper = Bootstrapper(
            templates: Templates(root: repositoryRoot, tag: "v1", tags: []), services: Stubs().services()
        )
        let resolution = try bootstrapper.resolve(repository: project.root, answers: [:])
        #expect(!resolution.components.map(\.component.name).contains("apple-app"))
    }

    @Test func walksADirectoryThatIsNotACheckout() throws {
        try FileManager.default.removeItem(at: project.root.appending(path: ".git"))
        let files = RepositoryFiles(root: project.root)
        #expect(files.paths.contains("worktrees/feature/Demo.xcodeproj/project.pbxproj"))
    }
}
