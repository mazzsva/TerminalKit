import Foundation
import TerminalCore
import Testing

@Suite(.timeLimit(.minutes(1)))
struct PseudoTerminalTests {
    @Test func reportsTheExitStatus() async throws {
        #expect(try await termination("exit 3") == .exit(3))
    }

    @Test func reportsAnUncaughtSignal() async throws {
        #expect(try await termination("kill -TERM $$") == .uncaughtSignal(SIGTERM))
    }

    @Test func readsTheOutput() async throws {
        #expect(try await output("printf 'hello\\nworld'") == "hello\r\nworld")
    }

    @Test func readsAllOutputBeforeTheExit() async throws {
        #expect(try await output("head -c 200000 /dev/zero | tr '\\0' a").count == 200_000)
    }

    @Test func givesTheProcessAControllingTerminal() async throws {
        #expect(try await output("exec 3</dev/tty && echo yes") == "yes\r\n")
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

    @Test func throwsWhenTheExecutableIsMissing() {
        #expect(throws: POSIXError(.ENOENT)) {
            try PseudoTerminal(executableURL: URL(filePath: "/missing"), environment: [:], columns: 80, rows: 24)
        }
    }
}

private func output(
    _ script: String,
    environment: [String: String] = [:],
    currentDirectoryURL: URL? = nil,
    columns: Int = 80,
    rows: Int = 24,
    input: (PseudoTerminal) -> Void = { _ in }
) async throws -> String {
    let pseudoTerminal = try PseudoTerminal(
        executableURL: URL(filePath: "/bin/sh"),
        arguments: ["-c", script],
        environment: environment,
        currentDirectoryURL: currentDirectoryURL,
        columns: columns,
        rows: rows
    )
    input(pseudoTerminal)
    var output: [UInt8] = []
    for await event in pseudoTerminal.events {
        if case .output(let bytes) = event {
            output += bytes
        }
    }
    return String(decoding: output, as: UTF8.self)
}

private func termination(_ script: String) async throws -> PseudoTerminal.Termination? {
    let pseudoTerminal = try PseudoTerminal(
        executableURL: URL(filePath: "/bin/sh"),
        arguments: ["-c", script],
        environment: [:],
        columns: 80,
        rows: 24
    )
    for await event in pseudoTerminal.events {
        if case .exit(let termination) = event {
            return termination
        }
    }
    return nil
}
