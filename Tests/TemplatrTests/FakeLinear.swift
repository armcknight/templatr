#if canImport(Network)
import Foundation
import Network

/// A Linear workspace behind a GraphQL endpoint on this Mac, for the
/// linear-workspace component's script. It answers the script's operations,
/// by name, from its state, and changes the state for the mutations. Lists come
/// two nodes a page, so the script must read every page.
final class FakeLinear: @unchecked Sendable {
    struct WorkflowState {
        var id: String
        var name: String
        var type: String
        var position: Double
        var team: String
    }

    struct Team {
        var id: String
        var key: String
        var triageEnabled: Bool
    }

    struct Label {
        var name: String
        /// The team's ID, or `nil` for a workspace label.
        var team: String?
    }

    struct View {
        var id: String
        var name: String
        var filterData: [String: Any]
    }

    struct Issue {
        var id: String
        var identifier: String
        var title: String
        var team: String
        var state: String
    }

    static let key = "lin_api_fake_0123456789"

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "FakeLinear")
    private let listener: NWListener
    private(set) var url = ""

    var viewerAdmin = false
    /// The keys of the teams the viewer owns.
    var viewerOwns: Set<String> = []
    var teams: [Team] = []
    var states: [WorkflowState] = []
    var labels: [Label] = []
    var views: [View] = []
    /// The IDs of the views in the viewer's favorites.
    var favorites: [String] = []
    var initiatives = 0
    var issues: [Issue] = []
    /// The names of the mutations run, in order.
    var mutations: [String] = []
    private var nextID = 0

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [unowned self] connection in
            connection.start(queue: queue)
            receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
        ready.wait()
        url = "http://127.0.0.1:\(listener.port!.rawValue)/graphql"
    }

    deinit {
        listener.cancel()
    }

    func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    func id() -> String {
        nextID += 1
        return "id-\(nextID)"
    }

    func team(_ key: String) -> Team { teams.first { $0.key == key }! }

    func states(of key: String) -> [WorkflowState] {
        let id = team(key).id
        return states.filter { $0.team == id }
    }

    // MARK: - Workspaces

    /// A workspace with the team TEM, set up as superlinear needs.
    static func setUp() throws -> FakeLinear {
        let linear = try FakeLinear()
        linear.viewerAdmin = true
        linear.addTeam("TEM", triage: true, states: [
            ("Triage", "triage", 0), ("Backlog", "backlog", 0), ("Todo", "unstarted", 1), ("In Progress", "started", 2),
            ("In Review", "started", 1002), ("Done", "completed", 3), ("Canceled", "canceled", 4),
        ])
        linear.labels = [
            Label(name: "Needs human", team: nil), Label(name: "superlinear", team: linear.team("TEM").id),
            Label(name: "superlinear: proposed", team: linear.team("TEM").id), Label(name: "Superlinear: Spec", team: nil),
            Label(name: "superlinear: hands off", team: linear.team("TEM").id), Label(name: "Bug", team: nil),
        ]
        linear.views = [View(id: "view-1", name: "superlinear proposals", filterData: [
            "and": [
                ["state": ["type": ["nin": ["canceled", "completed"]]]],
                ["labels": ["some": ["name": ["eq": "superlinear: proposed"]]]],
            ],
        ])]
        linear.favorites = ["view-1"]
        linear.initiatives = 1
        linear.addIssue("TEM", "Get familiar with Linear", state: "Canceled")
        linear.addIssue("TEM", "Set up your teams", state: "Done")
        return linear
    }

    /// A workspace with the teams TEM and OTH, neither set up: no In Review or
    /// Todo state, Triage off, one label, no view, no initiative, and open
    /// onboarding issues. The viewer owns TEM but is not an admin.
    static func notSetUp() throws -> FakeLinear {
        let linear = try FakeLinear()
        linear.viewerOwns = ["TEM"]
        for key in ["TEM", "OTH"] {
            linear.addTeam(key, triage: false, states: [
                ("Backlog", "backlog", 0), ("In Progress", "started", 2), ("Done", "completed", 3), ("Canceled", "canceled", 4),
            ])
        }
        linear.labels = [Label(name: "needs human", team: nil), Label(name: "superlinear", team: linear.team("TEM").id)]
        for title in ["Get familiar with Linear", "Set up your teams", "Connect your tools", "Import your data"] {
            linear.addIssue("TEM", title, state: "Backlog")
        }
        linear.addIssue("TEM", "set up your teams", state: "Backlog")
        linear.addIssue("TEM", "Import your data from Jira", state: "Backlog")
        linear.addIssue("OTH", "Import your data", state: "Backlog")
        return linear
    }

    func addTeam(_ key: String, triage: Bool, states: [(String, String, Double)]) {
        let team = Team(id: id(), key: key, triageEnabled: triage)
        teams.append(team)
        for (name, type, position) in states {
            self.states.append(WorkflowState(id: id(), name: name, type: type, position: position, team: team.id))
        }
    }

    func addIssue(_ key: String, _ title: String, state: String) {
        let number = issues.filter { $0.team == team(key).id }.count + 1
        let stateID = states(of: key).first { $0.name == state }!.id
        issues.append(Issue(id: id(), identifier: "\(key)-\(number)", title: title, team: team(key).id, state: stateID))
    }

    func stateType(of issue: Issue) -> String { states.first { $0.id == issue.state }!.type }

    // MARK: - HTTP

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [unowned self] data, _, done, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let (headers, body) = Self.request(in: buffer) {
                let response = try? JSONSerialization.data(withJSONObject: locked { answer(headers: headers, body: body) })
                let payload = response ?? Data()
                var head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                head += "Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(head.utf8) + payload, completion: .contentProcessed { _ in connection.cancel() })
            } else if done || error != nil {
                connection.cancel()
            } else {
                receive(connection, buffer: buffer)
            }
        }
    }

    /// The headers, with lowercased names, and the body of a whole request, or
    /// `nil` while part of it has not come.
    private static func request(in buffer: Data) -> ([String: String], Data)? {
        guard let end = buffer.firstRange(of: Data("\r\n\r\n".utf8)) else { return nil }
        let lines = String(decoding: buffer[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n").dropFirst()
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = buffer[end.upperBound...]
        return body.count >= length ? (headers, Data(body.prefix(length))) : nil
    }

    // MARK: - GraphQL

    private func answer(headers: [String: String], body: Data) -> [String: Any] {
        guard headers["authorization"] == Self.key else {
            return ["errors": [["message": "Authentication required, not authenticated"]]]
        }
        guard let request = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let query = request["query"] as? String,
              let match = query.firstMatch(of: /(query|mutation)\s+(\w+)/)
        else { return ["errors": [["message": "Bad request"]]] }
        let variables = request["variables"] as? [String: Any] ?? [:]
        let operation = String(match.2)
        if match.1 == "mutation" { mutations.append(operation) }

        switch operation {
        case "Viewer":
            return data(["viewer": [
                "id": "viewer", "name": "owner@example.com", "admin": viewerAdmin,
                "teamMemberships": ["nodes": teams.map { ["owner": viewerOwns.contains($0.key), "team": ["key": $0.key]] }],
            ]])
        case "List":
            return list(query: query, after: variables["after"] as? String)
        case "Initiatives":
            return data(["initiatives": ["nodes": (0..<initiatives).map { ["id": "initiative-\($0)"] }]])
        case "OnboardingIssues":
            let titles = variables["titles"] as? [String] ?? []
            let open = issues.filter { titles.contains($0.title) && !["completed", "canceled"].contains(stateType(of: $0)) }
            return data(["issues": ["nodes": open.map { issue in
                ["id": issue.id, "identifier": issue.identifier, "title": issue.title,
                 "team": ["key": teams.first { $0.id == issue.team }!.key]]
            }]])
        case "CreateState":
            let team = variables["teamId"] as! String
            states.append(WorkflowState(id: id(), name: "In Review", type: "started", position: variables["position"] as! Double, team: team))
        case "UpdateState":
            let index = states.firstIndex { $0.id == variables["id"] as! String }!
            states[index].position = variables["position"] as! Double
        case "EnableTriage":
            let index = teams.firstIndex { $0.id == variables["id"] as! String }!
            teams[index].triageEnabled = true
        case "CreateLabel":
            labels.append(Label(name: variables["name"] as! String, team: variables["teamId"] as? String))
        case "CreateView":
            let view = View(id: id(), name: "superlinear proposals", filterData: variables["filterData"] as! [String: Any])
            views.append(view)
            return data(["customViewCreate": ["customView": ["id": view.id]]])
        case "UpdateView":
            let index = views.firstIndex { $0.id == variables["id"] as! String }!
            views[index].filterData = variables["filterData"] as! [String: Any]
        case "FavoriteView":
            favorites.append(variables["customViewId"] as! String)
        case "CancelIssue":
            let index = issues.firstIndex { $0.id == variables["id"] as! String }!
            issues[index].state = variables["stateId"] as! String
        default:
            return ["errors": [["message": "Unknown operation \(operation)"]]]
        }
        return data([operation: ["success": true]])
    }

    /// A page of one of the lists the script reads with its `all` function.
    private func list(query: String, after: String?) -> [String: Any] {
        guard let match = query.firstMatch(of: /(\w+)\(first:/) else { return ["errors": [["message": "No list"]]] }
        let name = String(match.1)
        var nodes: [[String: Any]]
        switch name {
        case "teams":
            nodes = teams.map { ["id": $0.id, "key": $0.key, "triageEnabled": $0.triageEnabled] }
        case "workflowStates":
            nodes = states.map { ["id": $0.id, "name": $0.name, "type": $0.type, "position": $0.position, "team": ["id": $0.team]] }
        case "issueLabels":
            let workspaceOnly = query.contains("team: { null: true }")
            nodes = labels.filter { !workspaceOnly || $0.team == nil }.map { label in
                ["name": label.name, "team": label.team.map { ["id": $0] as Any } ?? NSNull()]
            }
        case "customViews":
            nodes = views.map { ["id": $0.id, "name": $0.name, "filterData": $0.filterData] }
        case "favorites":
            // The first favorite is a folder with the others in it.
            let all = favorites.map { ["customView": ["id": $0]] as [String: Any] }
            nodes = all.isEmpty ? [] : [["customView": NSNull(), "children": ["nodes": all]]]
        default:
            return ["errors": [["message": "Unknown list \(name)"]]]
        }
        let start = after.flatMap(Int.init) ?? 0
        let end = min(start + 2, nodes.count)
        return data([name: [
            "nodes": Array(nodes[start..<end]),
            "pageInfo": ["hasNextPage": end < nodes.count, "endCursor": String(end)],
        ]])
    }

    private func data(_ value: [String: Any]) -> [String: Any] { ["data": value] }
}
#endif
