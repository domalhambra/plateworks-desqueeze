import Foundation

/// The server did not do what the test waited for.
struct ServerError: Error, CustomStringConvertible {
    let description: String
}

/// The built `desqueeze-mcp` as a child process, and a small MCP client for it.
///
/// The client is written here and does not use the MCP library, so the tests
/// check the bytes on the wire: one JSON-RPC 2.0 message on each line of
/// standard input and of standard output.
///
/// Every read has a time limit. A server that hangs fails the test and does
/// not block the suite.
final class ServerProcess: @unchecked Sendable {
    /// For a call that starts no tool, or exiftool only.
    static let shortWait: TimeInterval = 20
    /// For a call that can start Adobe DNG Converter.
    static let longWait: TimeInterval = 180

    private let process = Process()
    private let toServer = Pipe()
    private let fromServer = Pipe()
    private let serverErrors = Pipe()
    private let exited = DispatchSemaphore(value: 0)

    private let condition = NSCondition()
    private var unfinishedLine = Data()
    private var lines: [String] = []
    private var linesRead = 0
    private var outputEnded = false
    private var errorsEnded = false
    private var errorData = Data()
    private var lastID = 0

    /// - Parameter environment: the whole environment of the server.
    init(executable: URL, arguments: [String] = [], environment: [String: String]) throws {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = toServer
        process.standardOutput = fromServer
        process.standardError = serverErrors
        process.terminationHandler = { [exited] _ in exited.signal() }

        fromServer.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            self.condition.lock()
            if data.isEmpty {
                self.outputEnded = true
                handle.readabilityHandler = nil
            } else {
                self.unfinishedLine.append(data)
                while let end = self.unfinishedLine.firstIndex(of: 0x0A) {
                    self.lines.append(String(decoding: self.unfinishedLine[..<end], as: UTF8.self))
                    self.unfinishedLine = Data(self.unfinishedLine[(end + 1)...])
                }
            }
            self.condition.broadcast()
            self.condition.unlock()
        }
        serverErrors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            self.condition.lock()
            if data.isEmpty {
                self.errorsEnded = true
                handle.readabilityHandler = nil
            } else {
                self.errorData.append(data)
            }
            self.condition.broadcast()
            self.condition.unlock()
        }
        try process.run()
    }

    // MARK: To the server

    /// Writes `text` as it is. The caller adds each line end.
    func write(_ text: String) throws {
        try toServer.fileHandleForWriting.write(contentsOf: Data(text.utf8))
    }

    /// One message as one line of JSON, with no line end.
    static func line(_ message: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]), as: UTF8.self)
    }

    /// A request with the next id. It is not sent.
    func request(_ method: String, _ params: [String: Any]? = nil) -> (id: Int, message: [String: Any]) {
        condition.lock()
        lastID += 1
        let id = lastID
        condition.unlock()
        var message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if let params { message["params"] = params }
        return (id, message)
    }

    /// Sends a request. Returns its id.
    @discardableResult
    func send(_ method: String, _ params: [String: Any]? = nil) throws -> Int {
        let (id, message) = request(method, params)
        try write(try Self.line(message) + "\n")
        return id
    }

    /// Sends a notification: a message with no id, which gets no answer.
    func notify(_ method: String, _ params: [String: Any]? = nil) throws {
        var message: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if let params { message["params"] = params }
        try write(try Self.line(message) + "\n")
    }

    /// Closes the server's standard input, as a client that goes away does.
    func closeInput() {
        try? toServer.fileHandleForWriting.close()
    }

    /// Sends a signal to the server, as a client that stops it does. It
    /// goes to the process of the server only: never to a group, and never
    /// to a process that this object did not start.
    func send(signal number: Int32) {
        guard process.isRunning else { return }
        kill(process.processIdentifier, number)
    }

    // MARK: From the server

    /// The next line of standard output, as a JSON object.
    ///
    /// - Throws: when no line comes in time, when the output ends, and when
    ///   the line is not one JSON object.
    func nextMessage(timeout: TimeInterval = ServerProcess.shortWait) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while linesRead == lines.count {
            if outputEnded {
                throw ServerError(description: "The server closed its standard output. Standard error: "
                    + String(decoding: errorData, as: UTF8.self))
            }
            guard condition.wait(until: deadline) else {
                throw ServerError(description: "No message from the server in \(Int(timeout)) seconds.")
            }
        }
        let line = lines[linesRead]
        linesRead += 1
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
              let message = object as? [String: Any] else {
            throw ServerError(description: "Not one JSON object on a line of standard output: \(line)")
        }
        return message
    }

    /// Reads until the answer to request `id`.
    ///
    /// - Returns: the answer, and every message that came before it.
    func answer(to id: Int, timeout: TimeInterval = ServerProcess.shortWait) throws
        -> (answer: [String: Any], earlier: [[String: Any]]) {
        let deadline = Date().addingTimeInterval(timeout)
        var earlier: [[String: Any]] = []
        while true {
            let message = try nextMessage(timeout: max(0.01, deadline.timeIntervalSinceNow))
            if message["method"] == nil, message["id"] as? Int == id { return (message, earlier) }
            earlier.append(message)
        }
    }

    /// Sends a request and reads its result. No other message may come first.
    func result(of method: String, _ params: [String: Any]? = nil,
                timeout: TimeInterval = ServerProcess.shortWait) throws -> [String: Any] {
        let id = try send(method, params)
        let (answer, earlier) = try answer(to: id, timeout: timeout)
        guard earlier.isEmpty else {
            throw ServerError(description: "Messages came before the answer to \(method): \(earlier)")
        }
        guard let result = answer["result"] as? [String: Any] else {
            throw ServerError(description: "\(method) gave no result: \(answer)")
        }
        return result
    }

    /// Waits for the server to end.
    ///
    /// - Returns: the exit status, or nil when the server still runs.
    func waitForExit(timeout: TimeInterval = ServerProcess.shortWait) -> Int32? {
        guard exited.wait(timeout: .now() + timeout) == .success else { return nil }
        exited.signal()
        return process.terminationReason == .exit ? process.terminationStatus : -process.terminationStatus
    }

    /// Ends the server, if it still runs. For `tearDown`.
    func stop() {
        closeInput()
        if process.isRunning {
            process.terminate()
            if waitForExit(timeout: 5) == nil { kill(process.processIdentifier, SIGKILL) }
        }
    }

    /// Every complete line that standard output got, so far.
    var outputLines: [String] {
        condition.lock()
        defer { condition.unlock() }
        return lines
    }

    /// What standard output holds after its last line end. Empty, for a
    /// server that writes whole lines only.
    var unfinishedOutput: String {
        condition.lock()
        defer { condition.unlock() }
        return String(decoding: unfinishedLine, as: UTF8.self)
    }

    /// Waits until the server has closed its standard output and its
    /// standard error, so both are read to their ends.
    ///
    /// - Returns: false when they are still open.
    func waitForEndOfOutput(timeout: TimeInterval = ServerProcess.shortWait) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        defer { condition.unlock() }
        while !(outputEnded && errorsEnded) {
            guard condition.wait(until: deadline) else { return false }
        }
        return true
    }

    var errorText: String {
        condition.lock()
        defer { condition.unlock() }
        return String(decoding: errorData, as: UTF8.self)
    }
}
