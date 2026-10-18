import Foundation
import Testing
@testable import ComponentManifest

// The parts of mtg's files that the supabase rules read, cut down. mtg runs
// Fluent migrations, and keeps Supabase's root CA in deploy/.

let mtgSupabaseFlyToml = mtgFlyToml.replacingOccurrences(
    of: "  MTG_SERVER_PORT = \"8080\"\n",
    with: "  MTG_SERVER_PORT = \"8080\"\n  MTG_DB_CA_CERT = \"/app/supabase-root-2021-ca.crt\"\n"
)

let mtgSupabaseDockerfile = mtgDockerfile.replacingOccurrences(
    of: "ARG GIT_SHA=unknown\n",
    with: "COPY deploy/supabase-root-2021-ca.crt /app/supabase-root-2021-ca.crt\nARG GIT_SHA=unknown\n"
)

let mtgDockerCompose = """
    services:
      db:
        image: postgres:17
        environment:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: mtg_collection

    """

let mtgEnvExample = """
    # PostgreSQL connection string
    DATABASE_URL=postgres://localhost:5432/mtg_collection
    MTG_SERVER_PORT=8080

    """

let mtgEnvrcExample = """
    # DATABASE_URL — your external Postgres (Supabase or Neon). Use the POOLED connection
    # string (session mode, port 5432) and add ?sslmode=require.
    # export DATABASE_URL=postgres://USER:PASSWORD@HOST:5432/postgres?sslmode=require

    """

let supabaseRootCA = """
    -----BEGIN CERTIFICATE-----
    MIIDxDCCAqygAwIBAgIUbLxMod62P2ktCiAkxnKJwtE9VPYwDQYJKoZIhvcNAQEL
    -----END CERTIFICATE-----

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

let cliEnvExample = """
    DATABASE_URL=postgres://postgres.abcdefghijklmnopqrst:<password>@aws-0-us-west-1.pooler.supabase.com:5432/postgres?sslmode=require

    """

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
        try repository.write("Package.swift", mtgPackage)
        try repository.write("fly.toml", mtgSupabaseFlyToml)
        try repository.write("Dockerfile", mtgSupabaseDockerfile)
        try repository.write("docker-compose.yml", mtgDockerCompose)
        try repository.write(".env.example", mtgEnvExample)
        try repository.write(".envrc.example", mtgEnvrcExample)
        try repository.write("deploy/supabase-root-2021-ca.crt", supabaseRootCA)
    }

    func writeCLI() throws {
        try repository.write("Package.swift", cliPackage)
        try repository.write("fly.toml", "app = \"statustician\"\nprimary_region = \"sjc\"\n")
        try repository.write("supabase/config.toml", cliConfigToml)
        try repository.write("supabase/migrations/20261017000000_init.sql", "CREATE TABLE checks (id uuid PRIMARY KEY);\n")
        try repository.write(".env.example", cliEnvExample)
    }

    @Test func mtg() throws {
        try writeMtg()
        #expect(detection.detects(supabase))
        #expect(detection.inputs(of: supabase) == mtgSupabaseInputs)
    }

    @Test func mtgIsDetectedByItsCertificateAlone() throws {
        try repository.write("deploy/supabase-root-2021-ca.crt", supabaseRootCA)
        #expect(detection.detects(supabase))
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

    @Test func detectedByAHostInTheEnvrcExample() throws {
        try repository.write(".envrc.example", "export DATABASE_URL=postgres://postgres:pw@db.abcdefghijklmnopqrst.supabase.co:5432/postgres\n")
        #expect(detection.detects(supabase))
        #expect(detection.inputs(of: supabase)["project_ref"] == "abcdefghijklmnopqrst")
    }

    @Test func vaporServerWithoutSupabase() throws {
        try repository.write("Package.swift", mtgPackage)
        try repository.write("fly.toml", mtgFlyToml)
        try repository.write("docker-compose.yml", mtgDockerCompose)
        try repository.write(".env.example", mtgEnvExample)
        #expect(!detection.detects(supabase))
    }

    @Test func linkedProjectRefComesFirst() throws {
        try writeCLI()
        try repository.write("supabase/.temp/project-ref", "zyxwvutsrqponmlkjihg")
        #expect(detection.inputs(of: supabase)["project_ref"] == "zyxwvutsrqponmlkjihg")
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

    @Test func migrationStyleIsAskedWithoutTheCLIOrFluent() throws {
        try repository.write("Package.swift", cliPackage)
        try repository.write("deploy/supabase-root-2021-ca.crt", supabaseRootCA)
        let inputs = detection.inputs(of: supabase)
        #expect(inputs["migration_style"] == .some(nil))
        #expect(inputs["database_name"] == .some(nil))
        #expect(inputs["pg_version"] == "17")
    }

    /// Set MTG_REPOSITORY to a checkout of mtg to run it. Only the project
    /// reference is asked for: mtg keeps it only in the ignored .envrc.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MTG_REPOSITORY"] != nil))
    func mtgCheckout() throws {
        let checkout = Detection(root: URL(fileURLWithPath: ProcessInfo.processInfo.environment["MTG_REPOSITORY"]!))
        #expect(checkout.detects(supabase))
        let inputs = checkout.inputs(of: supabase)
        #expect(inputs.filter { $0.value == nil }.keys.sorted() == ["project_ref"])
        #expect(inputs["migration_style"] == "fluent")
        #expect(inputs["ca_cert_env"] == "MTG_DB_CA_CERT")
    }
}
