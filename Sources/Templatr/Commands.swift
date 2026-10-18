import Foundation

/// What a command did.
public struct CommandResult: Sendable {
    public var status: Int32
    public var output: Data
    public var error: Data

    public init(status: Int32, output: Data, error: Data) {
        self.status = status
        self.output = output
        self.error = error
    }

    public var succeeded: Bool { status == 0 }

    /// Standard output as text.
    public var text: String { String(decoding: output, as: UTF8.self) }

    /// Standard output and standard error as text, trimmed, for a report.
    public var transcript: String {
        let text = (String(decoding: output, as: UTF8.self) + String(decoding: error, as: UTF8.self))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.count > 2000 ? "…" + String(text.suffix(2000)) : text
    }
}

/// Runs programs. The library runs every command through one, so tests can
/// stand in for `gh`, `security`, `op` and `xcodebuild`.
public protocol CommandRunner: Sendable {
    /// Runs `arguments`, looked up on `PATH`, in `directory`, with `input` on
    /// standard input; with no input, standard input is empty.
    func run(_ arguments: [String], input: Data?, in directory: URL?) throws -> CommandResult
}

extension CommandRunner {
    /// Runs a shell command with `/bin/sh -c`.
    func shell(_ command: String, in directory: URL) throws -> CommandResult {
        try run(["/bin/sh", "-c", command], input: nil, in: directory)
    }
}

/// Runs commands as child processes.
public struct ProcessRunner: CommandRunner {
    /// Variables added to the commands' environment, over this process's own,
    /// such as a Linear API key for the steps when no `.envrc` gives one.
    public var environment: [String: String]

    public init() {
        self.init(environment: [:])
    }

    public init(environment: [String: String]) {
        self.environment = environment
    }

    public func run(_ arguments: [String], input: Data?, in directory: URL?) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = directory
        }
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { $1 }
        }
        let output = Pipe()
        let error = Pipe()
        let standardInput = Pipe()
        process.standardOutput = output
        process.standardError = error
        process.standardInput = input == nil ? FileHandle.nullDevice : standardInput

        try process.run()

        // Both pipes are read at the same time, so a command that fills one
        // does not wait forever for the other to be read. The second reader is
        // a thread of its own: with every worker thread waiting here, a
        // dispatch queue might never run it.
        let errorData = DataBox()
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            errorData.data = error.fileHandleForReading.readDataToEndOfFile()
            done.signal()
        }
        if let input {
            standardInput.fileHandleForWriting.write(input)
            try? standardInput.fileHandleForWriting.close()
        }
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        done.wait()
        process.waitUntilExit()
        return CommandResult(status: process.terminationStatus, output: outputData, error: errorData.data)
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

enum Shell {
    /// `value` quoted for a POSIX shell.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
