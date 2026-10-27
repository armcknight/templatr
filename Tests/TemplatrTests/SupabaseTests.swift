import Foundation
import Testing
@testable import Templatr

// mtg, as bootstrap leaves it: its server in server/, and the supabase
// scaffold's component.mk in supabase/, rendered with mtg's values. mtg runs
// Fluent migrations on Postgres, and has no Supabase CLI files.

let mtgSupabasePackage = mtgPackage.replacingOccurrences(
    of: #"        .package(url: "https://github.com/vapor/fluent", from: "4.0.0"),"#,
    with: #"""
            .package(url: "https://github.com/vapor/fluent", from: "4.0.0"),
            .package(url: "https://github.com/vapor/fluent-postgres-driver", from: "2.0.0"),
    """#
)

let mtgSupabaseFlyToml = mtgFlyToml.replacingOccurrences(
    of: "[env]\n  MTG_SERVER_PORT = \"8080\"\n",
    with: """
        [env]
          MTG_SERVER_PORT = "8080"
          # Verify the Supabase TLS cert against its bundled private root CA (see Dockerfile).
          MTG_DB_CA_CERT = "/app/supabase-root-2021-ca.crt"

        """
)

let mtgSupabaseDockerfile = mtgDockerfile.replacingOccurrences(
    of: "ENTRYPOINT",
    with: "COPY deploy/supabase-root-2021-ca.crt /app/supabase-root-2021-ca.crt\nENTRYPOINT"
)

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

/// The root's .envrc.example, as the envrc-example step writes it.
let supabaseEnvrcExample = """
    # Keychain: templatr.supabase.abcdefghijklmnopqrst.database-url
    export DATABASE_URL='postgres://postgres.abcdefghijklmnopqrst:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres?sslmode=require'

    """

let mtgSupabaseInputs: [String: String?] = [
    "project_ref": nil,
    "migration_style": "fluent",
    "product": "mtg-server",
    "fly_app": "mtg-server",
    "database_name": "mtg_collection",
    "pg_version": "17",
    "ca_cert_path": "deploy/supabase-root-2021-ca.crt",
    "ca_cert_env": "MTG_DB_CA_CERT",
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
    "product": "statustician",
    "fly_app": "statustician",
    "database_name": "postgres",
    "pg_version": "15",
    "ca_cert_path": "deploy/supabase-root-2021-ca.crt",
    "ca_cert_env": "DATABASE_CA_CERT",
]

/// Detection and inference with this repository's supabase manifest, as
/// bootstrap runs them.
@Suite("supabase")
struct SupabaseTests {
    let repository: Directory

    init() throws {
        repository = try Directory()
    }

    var supabase: ResolvedComponent? {
        get throws { try resolve("supabase", in: repository.root) }
    }

    /// mtg's server, before it has the component.
    func writeMtgServer() throws {
        try repository.write("server/Package.swift", mtgSupabasePackage)
        try repository.write("server/fly.toml", mtgSupabaseFlyToml)
        try repository.write("server/Dockerfile", mtgSupabaseDockerfile)
        try repository.write("server/deploy/supabase-root-2021-ca.crt", supabaseRootCA)
    }

    func writeMtg() throws {
        try writeMtgServer()
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
        #expect(try #require(try supabase).inputs == mtgSupabaseInputs)
    }

    /// A fluent project has no Supabase CLI files, so before it has the
    /// scaffold's component.mk it is detected from its server's Package.swift,
    /// and the server's files give the inputs that they have.
    @Test func mtgWithoutTheScaffoldIsDetected() throws {
        try writeMtgServer()
        let inputs = try #require(try supabase).inputs
        #expect(inputs["product"] == "mtg-server")
        #expect(inputs["fly_app"] == "mtg-server")
        #expect(inputs["ca_cert_path"] == "deploy/supabase-root-2021-ca.crt")
        #expect(inputs["ca_cert_env"] == "MTG_DB_CA_CERT")
        // Asked for.
        #expect(inputs["project_ref"] == .some(nil))
        #expect(inputs["migration_style"] == .some(nil))
        #expect(inputs["database_name"] == .some(nil))
    }

    @Test func serverAndEnvrcExampleWithoutSupabaseDirectory() throws {
        try repository.write("server/Package.swift", mtgSupabasePackage)
        try repository.write(".envrc.example", supabaseEnvrcExample)
        let inputs = try #require(try supabase).inputs
        #expect(inputs["project_ref"] == "abcdefghijklmnopqrst")
        #expect(inputs["product"] == "mtg-server")
    }

    @Test func envrcExampleWithTheDirectHostAlone() throws {
        try repository.write(".envrc.example", "export DATABASE_URL=postgres://postgres:<password>@db.abcdefghij0123456789.supabase.co:5432/postgres\n")
        #expect(try #require(try supabase).inputs["project_ref"] == "abcdefghij0123456789")
    }

    @Test func fluentWithoutPostgresIsNotDetected() throws {
        try repository.write(
            "server/Package.swift", mtgPackage.replacingOccurrences(of: "vapor/fluent\"", with: "vapor/fluent-sqlite-driver\"")
        )
        try repository.write(".envrc.example", "export DATABASE_URL=postgres://localhost/demo\n")
        #expect(try supabase == nil)
    }

    @Test func cli() throws {
        try writeCLI()
        #expect(try #require(try supabase).inputs == cliInputs)
    }

    @Test func cliIsDetectedByItsConfigAlone() throws {
        try repository.write("supabase/config.toml", cliConfigToml)
        #expect(try #require(try supabase).inputs["migration_style"] == "cli")
    }

    @Test func readsTheFilesInItsDirectory() throws {
        try repository.write("config.toml", cliConfigToml)
        try repository.write("component.mk", mtgComponentMk)
        #expect(try supabase == nil)
    }

    @Test func componentMkOfAnotherComponent() throws {
        try repository.write("supabase/component.mk", "NAMESPACES += local-db\ninclude $(TEMPLATES_MAKE)/postgres.mk\n")
        #expect(try supabase == nil)
    }

    @Test func linkedProjectRefComesFirst() throws {
        try writeCLI()
        try repository.write(
            "supabase/config.toml", cliConfigToml.replacingOccurrences(of: "\"statustician\"", with: "\"zyxwvutsrqponmlkjihg\"")
        )
        try repository.write(".envrc.example", supabaseEnvrcExample.replacingOccurrences(of: "abcdefghijklmnopqrst", with: "0123456789abcdefghij"))
        #expect(try #require(try supabase).inputs["project_ref"] == "abcdefghijklmnopqrst")
    }

    @Test func projectIdIsARefOnlyInItsForm() throws {
        try repository.write("supabase/config.toml", cliConfigToml)
        #expect(try #require(try supabase).inputs["project_ref"] == .some(nil))
        try repository.write(
            "supabase/config.toml",
            cliConfigToml.replacingOccurrences(of: "\"statustician\"", with: "\"abcdefghijklmnopqrst\"")
        )
        #expect(try #require(try supabase).inputs["project_ref"] == "abcdefghijklmnopqrst")
    }

    @Test func configComesBeforeComponentMk() throws {
        try repository.write("supabase/config.toml", cliConfigToml)
        try repository.write("supabase/component.mk", mtgComponentMk)
        let inputs = try #require(try supabase).inputs
        #expect(inputs["migration_style"] == "cli")
        #expect(inputs["database_name"] == "postgres")
        #expect(inputs["pg_version"] == "15")
    }

    @Test func componentMkProductComesBeforeThePackage() throws {
        try writeMtg()
        try repository.write("supabase/component.mk", mtgComponentMk.replacingOccurrences(of: "SUPABASE_PRODUCT = mtg-server", with: "SUPABASE_PRODUCT = migrate"))
        #expect(try #require(try supabase).inputs["product"] == "migrate")
    }

    @Test func migrationStyleIsAskedWithoutTheCLIOrTheScaffold() throws {
        try repository.write("supabase/component.mk", "NAMESPACES += local-db\ninclude $(TEMPLATES_MAKE)/supabase.mk\n")
        let inputs = try #require(try supabase).inputs
        #expect(inputs["migration_style"] == .some(nil))
        #expect(inputs["database_name"] == .some(nil))
        #expect(inputs["pg_version"] == "17")
    }
}
