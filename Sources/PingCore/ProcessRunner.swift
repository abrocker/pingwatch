import Foundation

enum ProcessRunner {
    /// Runs a command-line tool and returns its exit status and standard output,
    /// or nil if it could not be started. The tool is terminated after `timeout` seconds.
    /// With `includeStandardError` the tool's error output is mixed into the result (traceroute prints its header there).
    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval,
                    includeStandardError: Bool = false) async -> (status: Int32, output: String)? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let out = Pipe()
            process.standardOutput = out
            process.standardError = includeStandardError ? out : FileHandle.nullDevice
            process.terminationHandler = { proc in
                let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: (proc.terminationStatus, text))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }
            // Safety net so a hanging tool can never stall the monitor.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }
}
