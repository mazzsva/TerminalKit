import Foundation
import TerminalCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct PseudoTerminalTests {
    @Test func readsTheOutput() async throws {
        #expect(try await output("printf 'hello\\nworld'") == "hello\r\nworld")
    }

    @Test func endsTheOutputWhenTheProcessExits() async throws {
        let start = ContinuousClock.now
        #expect(try await output("trap '' HUP; /bin/sleep 5 & echo done") == "done\r\n")
        #expect(ContinuousClock.now - start < .seconds(4))
    }

    @Test func readsAllOutputBeforeTheExit() async throws {
        #expect(try await output("head -c 200000 /dev/zero | tr '\\0' a").count == 200_000)
    }

    @Test func waitsForTheReaderBeforeItReadsMoreOutput() async throws {
        let marker = URL.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: marker) }
        let pseudoTerminal = try PseudoTerminal(
            executableURL: URL(filePath: "/bin/sh"),
            arguments: ["-c", "head -c 10000000 /dev/zero; touch \"$0\"", marker.path(percentEncoded: false)],
            environment: [:],
            columns: 80,
            rows: 24
        )
        try await Task.sleep(for: .seconds(1))
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
        for await _ in pseudoTerminal.output {}
        #expect(FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }

    @Test(arguments: ["/bin/sh", "/bin/zsh", "/bin/dash"])
    func givesTheProcessAControllingTerminal(shell: String) async throws {
        let output = try await output("exec 3</dev/tty && echo yes", shell: shell)
        #expect(output == "yes\r\n")
    }

    @Test(arguments: ["/bin/sh", "/bin/zsh", "/bin/dash"])
    func makesTheProcessTheForegroundProcessGroup(shell: String) async throws {
        let output = try await output("/bin/ps -o tpgid= -p $$ | /usr/bin/tr -d ' '; echo $$", shell: shell)
        let lines = output.split(separator: "\r\n")
        #expect(lines.count == 2 && lines[0] == lines[1])
    }

    @Test func setsTheWindowSize() async throws {
        #expect(try await output("stty size", columns: 100, rows: 30) == "30 100\r\n")
    }

    @Test func passesTheEnvironment() async throws {
        #expect(try await output("printf %s \"$NAME\"", environment: ["NAME": "value"]) == "value")
    }

    @Test func startsInTheCurrentDirectory() async throws {
        #expect(try await output("pwd", currentDirectoryURL: URL(filePath: "/usr/bin")) == "/usr/bin\r\n")
    }

    @Test func throwsWhenTheCurrentDirectoryIsMissing() {
        #expect(throws: POSIXError(.ENOENT)) {
            try PseudoTerminal(
                executableURL: URL(filePath: "/bin/sh"),
                environment: [:],
                currentDirectoryURL: URL(filePath: "/missing"),
                columns: 80,
                rows: 24
            )
        }
    }

    @Test func sendsInput() async throws {
        let output = try await output("read line; printf 'got:%s' \"$line\"") { pseudoTerminal in
            pseudoTerminal.write(Array("abc\r".utf8))
        }
        #expect(output.hasSuffix("got:abc"))
    }

    @Test func sendsInputThatFillsTheTerminal() async throws {
        let output = try await output("stty -echo; wc -l") { pseudoTerminal in
            pseudoTerminal.write(Array((String(repeating: "abcdefghi\n", count: 2_000) + "\u{4}").utf8))
        }
        #expect(output.hasSuffix("2000\r\n"))
    }

    @Test func resizesTheTerminal() async throws {
        let output = try await output("read line; stty size") { pseudoTerminal in
            pseudoTerminal.resize(columns: 120, rows: 40)
            pseudoTerminal.write(Array("\r".utf8))
        }
        #expect(output.hasSuffix("40 120\r\n"))
    }

    @Test(arguments: ["/bin/sh", "/bin/zsh", "/bin/dash"])
    func signalsTheWindowSizeChange(shell: String) async throws {
        let pseudoTerminal = try PseudoTerminal(
            executableURL: URL(filePath: shell),
            arguments: ["-c", "trap '/bin/stty size; exit' WINCH; echo ready; while :; do /bin/sleep 0.1; done"],
            environment: [:],
            columns: 80,
            rows: 24
        )
        var output = ""
        for await bytes in pseudoTerminal.output {
            output += String(decoding: bytes, as: UTF8.self)
            if output.hasSuffix("ready\r\n") {
                pseudoTerminal.resize(columns: 100, rows: 30)
            }
        }
        #expect(output.hasSuffix("30 100\r\n"))
    }

    @Test func hangsUpTheProcessWhenReleased() async throws {
        var pseudoTerminal: PseudoTerminal? = try PseudoTerminal(
            executableURL: URL(filePath: "/bin/zsh"),
            arguments: ["-c", "/bin/sleep 60"],
            environment: [:],
            columns: 80,
            rows: 24
        )
        let processIdentifier = try #require(pseudoTerminal?.processIdentifier)
        pseudoTerminal = nil
        while kill(processIdentifier, 0) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(errno == ESRCH)
    }

    @Test func hangsUpAProcessThatWaitsForTheReader() async throws {
        var pseudoTerminal: PseudoTerminal? = try PseudoTerminal(
            executableURL: URL(filePath: "/usr/bin/yes"),
            environment: [:],
            columns: 80,
            rows: 24
        )
        let processIdentifier = try #require(pseudoTerminal?.processIdentifier)
        try await Task.sleep(for: .milliseconds(300))
        pseudoTerminal = nil
        while kill(processIdentifier, 0) == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(errno == ESRCH)
    }

    @Test func throwsWhenTheExecutableIsMissing() {
        #expect(throws: POSIXError(.ENOENT)) {
            try PseudoTerminal(executableURL: URL(filePath: "/missing"), environment: [:], columns: 80, rows: 24)
        }
    }
}

private func output(
    _ script: String,
    shell: String = "/bin/sh",
    environment: [String: String] = [:],
    currentDirectoryURL: URL? = nil,
    columns: Int = 80,
    rows: Int = 24,
    input: (PseudoTerminal) -> Void = { _ in }
) async throws -> String {
    let pseudoTerminal = try PseudoTerminal(
        executableURL: URL(filePath: shell),
        arguments: ["-c", script],
        environment: environment,
        currentDirectoryURL: currentDirectoryURL,
        columns: columns,
        rows: rows
    )
    input(pseudoTerminal)
    var output: [UInt8] = []
    for await bytes in pseudoTerminal.output {
        output += bytes
    }
    return String(decoding: output, as: UTF8.self)
}
