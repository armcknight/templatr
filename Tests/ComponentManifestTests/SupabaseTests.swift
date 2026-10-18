import Foundation
import Testing
@testable import ComponentManifest

// mtg, as bootstrap leaves it: its server in server/, and the supabase
// scaffold's component.mk in supabase/, rendered with mtg's values. mtg runs
// Fluent migrations, and has no Supabase CLI files.

let mtgComponentMk = """
    SUPABASE_MIGRATION_STYLE = fluent
    SUPABASE_PRODUCT = mtg-server
    SUPABASE_PACKAGE_PATH = server
    SUPABASE_MIGRATE_ARGS = migrate --yes
    SUPABASE_DB_NAME = mtg_collection
    SUPABASE_PG_VERSION = 17
    SUPABASE_CA_CERT = server/deploy/supabase-root-2021-ca.crt

    NAMESPACES += local-db
    TEMPLATES_FRAGMENTS += $(TEMPLATES_MAKE)/supabase.mk

    include $(TEMPLATES_MAKE)/supabase.mk

    """

let supabaseRootCA = """
    -----BEGIN CERTIFICATE-----
    MIIDxDCCAqygAwIBAgIUbLxMod62P2ktCiAkxnKJwtE9VPYwDQYJKoZIhvcNAQEL
    -----END CERTIFICATE-----

    """

// The server's files are in vapor-fly's directory, which the rules do not
// read, so fly_app is asked for, and the CA's inputs have their defaults.
let mtgSupabaseInputs: [String: String?] = [
    "project_ref": nil,
    "migration_style": "fluent",
    "product": "mtg-server",
    "fly_app": nil,
    "database_name": "mtg_collection",
    "pg_version": "17",
    "ca_cert_path": "deploy/supabase-root-2021-ca.crt",
    "ca_cert_env": "DATABASE_CA_CERT",
]

// A server that uses the Supabase CLI, as `supabase init` makes it, with its
// migrations in supabase/migrations.

let cliConfigToml = """
    # For detailed configuration reference documentation, visit:
    # https://supabase.com/docs/guides/local-development/cli/config
    project_id = "statustician"

    [api]
    enabled = true
    port = 54321

    [db]
    port = 54322
    shadow_port = 54320
    major_version = 15

    """

let cliPackage = mtgPackage
    .replacingOccurrences(of: "mtg-server", with: "statustician")
    .replacingOccurrences(of: "https://github.com/vapor/fluent", with: "https://github.com/vapor/postgres-nio")

let cliInputs: [String: String?] = [
    "project_ref": "abcdefghijklmnopqrst",
    "migration_style": "cli",
    "product": nil,
    "fly_app": nil,
    "database_name": "postgres",
    "pg_version": "15",
    "ca_cert_path": "deploy/supabase-root-2021-ca.crt",
    "ca_cert_env": "DATABASE_CA_CERT",
]

@Suite("supabase")
struct SupabaseTests {
    let repository: Repository
    let supabase: Manifest

    init() throws {
        repository = try Repository()
        supabase = try Manifest(contentsOf: repositoryRoot.appending(path: "components/supabase/component.toml"))
    }

    var detection: Detection { Detection(root: repository.root) }

    func writeMtg() throws {
        try repository.write("server/Package.swift", mtgPackage)
        try repository.write("server/fly.toml", mtgFlyToml)
        try repository.write("server/Dockerfile", mtgDockerfile)
        try repository.write("server/deploy/supabase-root-2021-ca.crt", supabaseRootCA)
        try repository.write("supabase/component.mk", mtgComponentMk)
    }

    /// `supabase link` writes the reference ID to supabase/.temp/project-ref.
    func writeCLI() throws {
        try repository.write("server/Package.swift", cliPackage)
        try repository.write("server/fly.toml", "app = \"statustician\"\nprimary_region = \"sjc\"\n")
        try repository.write("supabase/config.toml", cliConfigToml)
        try repository.write("supabase/migrations/20261017000000_init.sql", "CREATE TABLE checks (id uuid PRIMARY KEY);\n")
        try repository.write("supabase/.temp/project-ref", "abcdefghijklmnopqrst\n")
    }

    @Test func mtg() throws {
        try writeMtg()
        #expect(detection.detects(supabase))
        #expect(detection.inputs(of: supabase) == mtgSupabaseInputs)
    }

    /// A fluent project has no Supabase CLI files, so until it has the
    /// scaffold's component.mk it gets the component by name.
    @Test func mtgWithoutTheScaffoldIsNotDetected() throws {
        try writeMtg()
        try FileManager.default.removeItem(at: repository.root.appending(path: "supabase"))
        #expect(!detection.detects(supabase))
    }

    @Test func cli() throws {
        try writeCLI()
        #expect(detection.detects(supabase))
        #expect(detection.inputs(of: supabase) == cliInputs)
    }

    @Test func cliIsDetectedByItsConfigAlone() throws {
        try repository.write("supabase/config.toml", cliConfigToml)
        #expect(detection.detects(supabase))
        #expect(detection.inputs(of: supabase)["migration_style"] == "cli")
    }

    @Test func readsTheFilesInItsDirectory() throws {
        try repository.write("config.toml", cliConfigToml)
        try repository.write("component.mk", mtgComponentMk)
        #expect(!detection.detects(supabase))
    }

    @Test func componentMkOfAnotherComponent() throws {
        try repository.write("supabase/component.mk", "NAMESPACES += local-db\ninclude $(TEMPLATES_MAKE)/postgres.mk\n")
        #expect(!detection.detects(supabase))
    }

    @Test func linkedProjectRefComesFirst() throws {
        try writeCLI()
        try repository.write(
            "supabase/config.toml", cliConfigToml.replacingOccurrences(of: "\"statustician\"", with: "\"zyxwvutsrqponmlkjihg\"")
        )
        #expect(detection.inputs(of: supabase)["project_ref"] == "abcdefghijklmnopqrst")
    }

    @Test func projectIdIsARefOnlyInItsForm() throws {
        try repository.write("supabase/config.toml", cliConfigToml)
        #expect(detection.inputs(of: supabase)["project_ref"] == .some(nil))
        try repository.write(
            "supabase/config.toml",
            cliConfigToml.replacingOccurrences(of: "\"statustician\"", with: "\"abcdefghijklmnopqrst\"")
        )
        #expect(detection.inputs(of: supabase)["project_ref"] == "abcdefghijklmnopqrst")
    }

    @Test func configComesBeforeComponentMk() throws {
        try repository.write("supabase/config.toml", cliConfigToml)
        try repository.write("supabase/component.mk", mtgComponentMk)
        let inputs = detection.inputs(of: supabase)
        #expect(inputs["migration_style"] == "cli")
        #expect(inputs["database_name"] == "postgres")
        #expect(inputs["pg_version"] == "15")
    }

    @Test func migrationStyleIsAskedWithoutTheCLIOrTheScaffold() throws {
        try repository.write("supabase/component.mk", "NAMESPACES += local-db\ninclude $(TEMPLATES_MAKE)/supabase.mk\n")
        let inputs = detection.inputs(of: supabase)
        #expect(inputs["migration_style"] == .some(nil))
        #expect(inputs["database_name"] == .some(nil))
        #expect(inputs["pg_version"] == "17")
    }
}
