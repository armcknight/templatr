import Foundation

/// Runs a command and returns its exit status, standard output and standard
/// error.
func run(_ arguments: [String]) throws(MatchError) -> (status: Int32, output: String, error: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    process.standardInput = FileHandle.nullDevice
    do {
        try process.run()
    } catch {
        throw MatchError("Could not run \(arguments[0]): \(error.localizedDescription)")
    }
    // The second pipe is read on a thread of its own, so a command that fills
    // one does not wait forever for the other to be read.
    let errorData = DataBox()
    let done = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        errorData.data = error.fileHandleForReading.readDataToEndOfFile()
        done.signal()
    }
    let outputData = output.fileHandleForReading.readDataToEndOfFile()
    done.wait()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: outputData, as: UTF8.self), String(decoding: errorData.data, as: UTF8.self))
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}
