import Foundation
import Testing
@testable import Templatr

// The parts of mcknight.io's and no-cookie-for-you's files that the static-site
// rules read, cut down, as they would be in site/.

let travelConfig = """
    title: Travel
    description: Where I have been.
    url: https://travel.mcknight.io
    exclude:
      - scripts
      - lib

    """

let noCookieIndex = """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>No Cookies for You</title>
        <link rel="canonical" href="https://nocookies.fun/" />
        <meta property="og:url" content="https://nocookies.fun/" />
      </head>
      <body></body>
    </html>

    """

let siteComponentMk = """
    STATIC_SITE_DIR = site
    STATIC_SITE_NAME = site
    STATIC_SITE_DOMAIN = nocookies.fun
    STATIC_SITE_WITH_WWW = true
    STATIC_SITE_BUILD = npm run build
    STATIC_SITE_OUTPUT = dist
    STATIC_SITE_IMMUTABLE = assets
    STATIC_SITE_PORT = 5199
    STATIC_SITE_PROFILE = armcknight
    STATIC_SITE_PRICE_CLASS = PriceClass_All
    STATIC_SITE_REDIRECT_FROM = armcknight.com tworingsoft.com

    NAMESPACES += site
    TEMPLATES_FRAGMENTS += $(TEMPLATES_MAKE)/static-site.mk

    include $(TEMPLATES_MAKE)/static-site.mk

    """

/// Detection and inference with this repository's static-site manifest, as
/// bootstrap runs them.
@Suite("static-site")
struct StaticSiteTests {
    let repository: Directory

    init() throws {
        repository = try Directory()
    }

    var staticSite: ResolvedComponent? {
        get throws { try resolve("static-site", in: repository.root) }
    }

    @Test func readsTheFilesInItsDirectory() throws {
        // mcknight.io's main site, at the root, is not in site/.
        try repository.write("_config.yml", travelConfig)
        #expect(try staticSite == nil)
    }

    @Test func jekyllSite() throws {
        try repository.write("site/_config.yml", travelConfig)
        try repository.write("site/index.html", "<html></html>\n")
        #expect(try #require(try staticSite).inputs == [
            "domain": "travel.mcknight.io",
            "with_www": "false",
            "build": "bundle exec jekyll build",
            "output": "_site",
            "port": "4000",
            "aws_profile": "default",
            "price_class": "PriceClass_100",
            "redirect_from": "",
        ])
    }

    @Test func viteSiteReadsTheCanonicalLink() throws {
        try repository.write("site/vite.config.ts", "export default { base: './' }\n")
        try repository.write("site/index.html", noCookieIndex)
        let inputs = try #require(try staticSite).inputs
        #expect(inputs["domain"] == "nocookies.fun")
        #expect(inputs["build"] == "npm run build")
        #expect(inputs["output"] == "dist")
    }

    @Test func hugoSite() throws {
        try repository.write("site/hugo.toml", "baseURL = 'https://books.mcknight.io/'\ntitle = 'Books'\n")
        let inputs = try #require(try staticSite).inputs
        #expect(inputs["domain"] == "books.mcknight.io")
        #expect(inputs["build"] == "hugo --minify")
        #expect(inputs["output"] == "public")
    }

    @Test func filesUploadedAsTheyAre() throws {
        try repository.write("site/CNAME", "static.example.com\n")
        let inputs = try #require(try staticSite).inputs
        #expect(inputs["domain"] == "static.example.com")
        #expect(inputs["build"] == "")
        #expect(inputs["output"] == "public")
    }

    @Test func bootstrappedSiteReadsItsComponentMk() throws {
        try repository.write("site/component.mk", siteComponentMk)
        // The generator's own files say _site; component.mk, written by a
        // bootstrap, comes first.
        try repository.write("site/_config.yml", travelConfig)
        #expect(try #require(try staticSite).inputs == [
            "domain": "nocookies.fun",
            "with_www": "true",
            "build": "npm run build",
            "output": "dist",
            "port": "5199",
            "aws_profile": "armcknight",
            "price_class": "PriceClass_All",
            "redirect_from": "armcknight.com tworingsoft.com",
        ])
    }

    @Test func siteWithoutAnAddressIsAskedForItsDomain() throws {
        try repository.write("site/DEPLOYED", "0123456789abcdef0123456789abcdef01234567\n2026-11-04T00:00:00Z\n")
        let inputs = try #require(try staticSite).inputs
        #expect(inputs["domain"] == .some(nil))
    }
}

/// The deploy-site script, with a stand-in `aws` that logs each call, in a
/// repository whose built site is in site/_site.
@Suite("static-site deploy-site")
struct StaticSiteDeployTests {
    let repository: Directory
    let bin: Directory

    init() throws {
        repository = try Directory()
        bin = try Directory()
        try repository.write(".gitignore", "/site/_site/\n")
        try repository.write("site/index.md", "# Home\n")
        try repository.write("site/_site/index.html", "<html></html>\n")
        try repository.write("site/_site/assets/app-1a2b3c.js", "console.log(1)\n")
        try git("init", "-q", "-b", "main")
        try git("add", ".")
        try git("-c", "user.name=Test", "-c", "user.email=test@example.com", "commit", "-q", "-m", "site")
    }

    /// Writes an `aws` that logs its arguments to aws.log, answers the stack's
    /// outputs, and exits with `syncStatus` for `s3 sync`.
    func stubAWS(syncStatus: Int = 0) throws {
        try bin.writeExecutable("aws", """
            #!/bin/sh
            echo "$*" >> "\(bin.root.path)/aws.log"
            case "$*" in
              "cloudformation describe-stacks"*"BucketName"*) echo "the-bucket" ;;
              "cloudformation describe-stacks"*"DistributionId"*) echo "E1DIST" ;;
              "s3 sync"*) exit \(syncStatus) ;;
              "cloudfront create-invalidation"*) echo "I1" ;;
              *) echo "unexpected: $*" >&2; exit 1 ;;
            esac
            """)
    }

    @discardableResult
    func git(_ arguments: String...) throws -> String {
        try run("/usr/bin/git", arguments, environment: [:]).output
    }

    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = repository.root
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = bin.root.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["GIT_AUTHOR_NAME"] = "Test"
        env["GIT_AUTHOR_EMAIL"] = "test@example.com"
        env["GIT_COMMITTER_NAME"] = "Test"
        env["GIT_COMMITTER_EMAIL"] = "test@example.com"
        for (key, value) in environment { env[key] = value }
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Runs deploy-site as `make site deploy` does, with `immutable` as
    /// STATIC_SITE_IMMUTABLE.
    func deploy(immutable: String = "") throws -> (status: Int32, output: String) {
        try run(repositoryRoot.appending(path: "components/static-site/bin/deploy-site").path, [], environment: [
            "STATIC_SITE_NAME": "site",
            "STATIC_SITE_DOMAIN": "travel.mcknight.io",
            "STATIC_SITE_OUTPUT": "site/_site",
            "STATIC_SITE_STAMP": "site/DEPLOYED",
            "STATIC_SITE_PROFILE": "test",
            "STATIC_SITE_IMMUTABLE": immutable,
            "STATIC_SITE_INVALIDATE": "/*",
        ])
    }

    var calls: [String] {
        (bin.read("aws.log") ?? "").split(separator: "\n").map(String.init)
    }

    @Test func uploadsStampsAndCommits() throws {
        try stubAWS()
        let before = try git("rev-parse", "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try deploy()
        #expect(result.status == 0, Comment(rawValue: result.output))

        // The stack names the bucket and the distribution.
        #expect(calls.contains { $0.hasPrefix("cloudformation describe-stacks --stack-name site-travel-mcknight-io") })
        // Everything is uploaded, checked on each request, and what is gone is deleted.
        #expect(calls.contains("s3 sync site/_site s3://the-bucket --cache-control no-cache --delete --profile test --no-cli-pager"))
        #expect(calls.contains { $0.hasPrefix("cloudfront create-invalidation --distribution-id E1DIST --paths /*") })

        // The stamp is in the upload and in the repository, and names the
        // commit that was uploaded.
        #expect(repository.read("site/_site/DEPLOYED")?.hasPrefix(before + "\n") == true)
        #expect(repository.read("site/DEPLOYED") == repository.read("site/_site/DEPLOYED"))
        #expect(try git("log", "-1", "--format=%s").trimmingCharacters(in: .whitespacesAndNewlines) == "deploy(site): " + String(before.prefix(12)))
        #expect(try git("status", "--porcelain").isEmpty)
    }

    @Test func immutableDirectoriesAreUploadedFirstAndCachedForAYear() throws {
        try stubAWS()
        let result = try deploy(immutable: "assets")
        #expect(result.status == 0, Comment(rawValue: result.output))
        let syncs = calls.filter { $0.hasPrefix("s3 sync") }
        #expect(syncs == [
            "s3 sync site/_site/assets s3://the-bucket/assets --cache-control public, max-age=31536000, immutable --profile test --no-cli-pager",
            "s3 sync site/_site s3://the-bucket --exclude assets/* --cache-control no-cache --delete --profile test --no-cli-pager",
            "s3 sync site/_site/assets s3://the-bucket/assets --cache-control public, max-age=31536000, immutable --delete --profile test --no-cli-pager",
        ])
    }

    @Test func aFailedUploadNeverStamps() throws {
        try stubAWS(syncStatus: 1)
        let result = try deploy()
        #expect(result.status != 0)
        #expect(repository.read("site/DEPLOYED") == nil)
        #expect(!calls.contains { $0.hasPrefix("cloudfront") })
        #expect(try git("log", "--format=%s").split(separator: "\n").count == 1)
    }

    @Test func refusesUncommittedChanges() throws {
        try stubAWS()
        try repository.write("site/index.md", "# Home, changed\n")
        let result = try deploy()
        #expect(result.status != 0)
        #expect(result.output.contains("uncommitted changes"))
        #expect(calls.isEmpty)
    }

    @Test func aChangedStampAloneIsNotUncommittedChanges() throws {
        try stubAWS()
        try repository.write("site/DEPLOYED", "old\n")
        let result = try deploy()
        #expect(result.status == 0, Comment(rawValue: result.output))
        #expect(try git("log", "-1", "--format=%s").hasPrefix("deploy(site): "))
    }
}

/// The check-stack and check-redirect-stacks scripts, with a stand-in `aws`.
@Suite("static-site check-stack")
struct StaticSiteStackCheckTests {
    let bin: Directory
    let cloudformation = repositoryRoot.appending(path: "components/static-site/cloudformation")
    var template: URL { cloudformation.appending(path: "site.yml") }
    var redirectTemplate: URL { cloudformation.appending(path: "redirect.yml") }

    init() throws {
        bin = try Directory()
    }

    /// Writes an `aws` that logs each call to aws.log, whose stacks have
    /// `status`, the domain their name was made from, and `parameters` as the
    /// values of the parameters the check asks for, in that order, and whose
    /// template is `template` as site-template renders it, or `templateBody`
    /// when given.
    func stubAWS(
        status: String = "UPDATE_COMPLETE", parameters: [String] = ["false", "PriceClass_100"],
        template: URL? = nil, templateBody: String? = nil
    ) throws {
        let render = repositoryRoot.appending(path: "components/static-site/bin/site-template").path
        let body = templateBody.map { "printf '%s' \"\($0)\"" } ?? "'\(render)' '\((template ?? self.template).path)'"
        let fields = parameters.map { "\\t" + $0 }.joined()
        try bin.writeExecutable("aws", """
            #!/bin/sh
            echo "$*" >> "\(bin.root.path)/aws.log"
            case "$*" in
              "cloudformation describe-stacks"*)
                domain=$(printf '%s' "$*" | sed -n 's/.*--stack-name [a-z]*-\\([^ ]*\\).*/\\1/p' | tr - .)
                printf '%s\\t%s\(fields)\\n' "\(status)" "$domain" ;;
              "cloudformation get-template"*) \(body) ;;
              *) echo "unexpected: $*" >&2; exit 1 ;;
            esac
            """)
    }

    func run(_ script: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = repositoryRoot.appending(path: "components/static-site/bin/\(script)")
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = bin.root.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func check(www: String = "false", price: String = "PriceClass_100") throws -> (status: Int32, output: String) {
        try run("check-stack", ["site", "travel.mcknight.io", "test", template.path, "WithWww=\(www)", "PriceClass=\(price)"])
    }

    var calls: [String] {
        (bin.read("aws.log") ?? "").split(separator: "\n").map(String.init)
    }

    @Test func aStackFromTheTemplatePasses() throws {
        try stubAWS()
        let result = try check()
        #expect(result.status == 0, Comment(rawValue: result.output))
        #expect(calls.first?.contains("--stack-name site-travel-mcknight-io") == true)
    }

    /// The template as the stack gets it: the function's code in place of the
    /// marker, indented as the marker was, so that it stays inside the `!Sub`
    /// block.
    @Test func siteTemplatePutsTheFunctionInTheTemplate() throws {
        let result = try run("site-template", [template.path])
        let rendered = result.output
        #expect(result.status == 0)
        #expect(!rendered.contains("@FUNCTION"))
        #expect(rendered.contains("      FunctionCode: !Sub |\n        // The distribution's viewer-request function"))
        #expect(rendered.contains("\n        function handler(event) {\n          var request = event.request;\n"))
        // Every ${…} in the template is one that !Sub knows: the function's
        // code must not bring another, such as a JavaScript template literal.
        let known: Set<String> = ["AWS::StackName", "AWS::AccountId", "DomainName", "SiteBucket.Arn", "Distribution"]
        let substitutions = Set(rendered.matches(of: /\$\{([A-Za-z:.]+)\}/).map { String($0.1) })
        #expect(substitutions.isSubset(of: known), Comment(rawValue: substitutions.sorted().joined(separator: ", ")))
    }

    @Test func siteTemplateRendersTheRedirectTemplateToo() throws {
        let result = try run("site-template", [redirectTemplate.path])
        let rendered = result.output
        #expect(result.status == 0)
        #expect(!rendered.contains("@FUNCTION"))
        #expect(rendered.contains("\n        function handler(event) {\n"))
        #expect(rendered.contains("'https://${RedirectTo}' + request.uri + query"))
        let known: Set<String> = ["AWS::StackName", "DomainName", "RedirectTo"]
        let substitutions = Set(rendered.matches(of: /\$\{([A-Za-z:.]+)\}/).map { String($0.1) })
        #expect(substitutions.isSubset(of: known), Comment(rawValue: substitutions.sorted().joined(separator: ", ")))
    }

    @Test func anotherTemplateFails() throws {
        try stubAWS(templateBody: "Resources: {}")
        let result = try check()
        #expect(result.status == 1)
        #expect(result.output.contains("WRONG  site-travel-mcknight-io template"))
    }

    @Test func otherParametersFail() throws {
        try stubAWS(parameters: ["true", "PriceClass_100"])
        let result = try check()
        #expect(result.status == 1)
        #expect(result.output.contains("WRONG  site-travel-mcknight-io WithWww: found true, expected false"))
    }

    @Test func anIncompleteStackFails() throws {
        try stubAWS(status: "UPDATE_ROLLBACK_COMPLETE")
        let result = try check()
        #expect(result.status == 1)
        #expect(result.output.contains("WRONG  site-travel-mcknight-io status"))
    }

    @Test func redirectStacksAreCheckedOneByOne() throws {
        try stubAWS(parameters: ["mcknight.io", "true"], template: redirectTemplate)
        let result = try run("check-redirect-stacks", ["mcknight.io", "test", redirectTemplate.path, "armcknight.com tworingsoft.com"])
        #expect(result.status == 0, Comment(rawValue: result.output))
        let stacks = calls.filter { $0.hasPrefix("cloudformation describe-stacks") }
        #expect(stacks.count == 2)
        #expect(stacks[0].contains("--stack-name redirect-armcknight-com"))
        #expect(stacks[1].contains("--stack-name redirect-tworingsoft-com"))
        #expect(result.output.contains("ok     redirect-tworingsoft-com RedirectTo: mcknight.io"))
    }

    @Test func noRedirectDomainsIsNothingToCheck() throws {
        try stubAWS()
        let result = try run("check-redirect-stacks", ["mcknight.io", "test", redirectTemplate.path, ""])
        #expect(result.status == 0)
        #expect(calls.isEmpty)
    }

    @Test func oneWrongRedirectStackFailsThemAll() throws {
        try stubAWS(parameters: ["elsewhere.example", "true"], template: redirectTemplate)
        let result = try run("check-redirect-stacks", ["mcknight.io", "test", redirectTemplate.path, "armcknight.com"])
        #expect(result.status == 1)
        #expect(result.output.contains("WRONG  redirect-armcknight-com RedirectTo: found elsewhere.example, expected mcknight.io"))
    }
}
