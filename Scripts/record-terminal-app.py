#!/usr/bin/python3 -I
import fcntl, glob, json, os, re, select, signal, struct, subprocess, sys, termios, tempfile, time, tty

COLUMNS = 40
ROWS = 12
TIME_LIMIT = 3600
SYNC = b"\x1b[>c"
PROBE = b"\x1b[6n"
SYNC_REPLY = b"\x1b[>1;95;0c"
RESET = (
    b"\x1b[?47h\x1b[r\x1b[?6l\x1b[2J\x1b[H\x1b7\x1b[?47l\x1b[!p\x1b[r\x1b[?7h\x1b[?6l\x1b[?5l\x1b[?3l\x1b[?40l\x1b[?25h\x1b[?1l\x1b>"
    b"\x1b[4l\x1b[20l\x1b(B\x1b)B\x0f\x1b[m\x1b[0 q\x1b]104\x07\x1b]110\x07\x1b]111\x07\x1b]112\x07\x1b]117\x07\x1b]105;0\x07\x1b]2;\x07"
    b"\x1b[3g" + b"".join(b"\x1b[%dG\x1bH" % column for column in range(9, COLUMNS, 8)) +
    b"\x1b[H\x1b7\x1b[2J\x1b[3J"
)


def decode(text):
    parts = re.split(r"\\x([0-9A-Fa-f]{2})", text)
    return b"".join(
        bytes([int(part, 16)]) if index % 2 else part.encode()
        for index, part in enumerate(parts)
    )


def encode(data):
    return "".join(chr(byte) if 0x20 <= byte < 0x7F and byte != 0x5C else "\\x%02X" % byte for byte in data)


def format_recordings(recordings):
    lines = ",\n".join(json.dumps(recording, ensure_ascii=False) for recording in recordings)
    return f"[\n{lines}\n]\n"


def text_lines(text):
    lines = text.split("\n")
    while lines and not lines[-1]:
        lines.pop()
    return lines


def terminal_processes():
    output = subprocess.run(["/bin/ps", "-axo", "pid=,comm="], capture_output=True, text=True, check=True).stdout
    return {int(line.split()[0]) for line in output.splitlines() if line.endswith("/Terminal")}


def host_process():
    process = os.getpid()
    while process > 1:
        output = subprocess.run(["/bin/ps", "-o", "ppid=,comm=", "-p", str(process)], capture_output=True, text=True)
        parent, command = output.stdout.strip().split(None, 1)
        if command.endswith("/Terminal"):
            return process
        process = int(parent)
    raise RuntimeError("no Terminal.app process")


def probe(state, paths):
    process = host_process()
    with open(os.path.join(state, "existing")) as file:
        if process in json.load(file):
            raise RuntimeError("this is not a separate Terminal.app process")
    with open(os.path.join(state, "process"), "w") as file:
        file.write(str(process))

    def events(*arguments):
        result = subprocess.run(
            [os.path.join(state, "events"), str(process), *map(str, arguments)], capture_output=True, timeout=60
        )
        if result.returncode != 0:
            raise RuntimeError(f"{arguments}: {result.stderr!r}")
        return result.stdout.decode()

    terminal = os.open("/dev/tty", os.O_RDWR)
    window = events("find", os.ttyname(0)).strip()
    events("hide")

    def window_size():
        rows, columns, _, _ = struct.unpack("4H", fcntl.ioctl(terminal, termios.TIOCGWINSZ, b"\0" * 8))
        return rows, columns

    def set_window_size(columns=COLUMNS, rows=ROWS):
        end = time.time() + 5
        while window_size() != (rows, columns) and time.time() < end:
            events("size", window, columns, rows)
            time.sleep(0.1)
        time.sleep(0.15)
        if window_size() != (rows, columns):
            raise RuntimeError(f"window is {window_size()}")

    set_window_size()

    def write(data):
        end = time.time() + 60
        while data:
            if time.time() > end:
                raise RuntimeError("Terminal.app stopped reading")
            if select.select([], [terminal], [], 1)[1]:
                data = data[os.write(terminal, data):]

    def read_to_sync(seconds):
        data = b""
        end = time.time() + seconds
        while time.time() < end:
            if select.select([terminal], [], [], 0.05)[0]:
                data += os.read(terminal, 65536)
                if data.endswith(SYNC_REPLY):
                    time.sleep(0.02)
                    if not select.select([terminal], [], [], 0)[0]:
                        return data, True
        return data, False

    def record_widths(path):
        scalars = [value for value in range(0x80, 0x110000) if not 0xD800 <= value <= 0xDFFF]
        widths = {}
        for start in range(0, len(scalars), 1000):
            chunk = scalars[start:start + 1000]
            write(b"".join(b"\r\x1b[Ka" + chr(value).encode() + PROBE for value in chunk) + SYNC)
            reply, synced = read_to_sync(60)
            columns = [int(column) for column in re.findall(rb"\x1b\[\d+;(\d+)R", reply)]
            if not synced or len(columns) != len(chunk):
                raise RuntimeError(f"no reply to U+{chunk[0]:X}")
            widths.update({value: column - 2 for value, column in zip(chunk, columns)})
        write(RESET + SYNC)
        read_to_sync(2)
        lines = []
        first = 0x80
        for value in range(0x81, 0x110001):
            if widths.get(value, widths[first]) != widths[first] or value == 0x110000:
                lines.append(f"{first:X} {value - 1:X} {widths[first]}\n")
                first = value
        with open(path, "w") as file:
            file.writelines(lines)

    original = termios.tcgetattr(terminal)
    tty.setraw(terminal)
    try:
        for path in paths:
            if path.endswith(".txt"):
                record_widths(path)
                continue
            with open(path) as file:
                recordings = json.load(file)
            for index, recording in enumerate(recordings):
                with open(os.path.join(state, "current"), "w") as file:
                    file.write(recording["name"])
                if index % 200 == 0:
                    with open(path, "w") as file:
                        file.write(format_recordings(recordings))
                write(RESET + SYNC)
                if not read_to_sync(2)[1]:
                    write(b"\x07\x1b\\" + RESET + SYNC)
                    if not read_to_sync(2)[1]:
                        raise RuntimeError(f"no reply after reset before {recording['name']}")
                size = (ROWS, COLUMNS)
                reply = b""
                for step_index, step in enumerate(recording.get("steps", [])):
                    write((b"" if step_index else decode(recording["input"])) + SYNC)
                    part, synced = read_to_sync(15)
                    if not synced:
                        raise RuntimeError(f"no reply to {recording['name']}: {part!r}")
                    reply += part[: -len(SYNC_REPLY)]
                    size = (step["rows"], step["columns"])
                    set_window_size(step["columns"], step["rows"])
                    write(decode(step.get("input", "")) + SYNC)
                    part, synced = read_to_sync(15)
                    if not synced:
                        raise RuntimeError(f"no reply to {recording['name']}: {part!r}")
                    reply += part[: -len(SYNC_REPLY)]
                write((b"" if "steps" in recording else decode(recording["input"])) + PROBE + SYNC)
                part, synced = read_to_sync(15)
                reply += part
                if not synced:
                    raise RuntimeError(f"no reply to {recording['name']}: {reply!r}")
                if window_size() != size:
                    raise RuntimeError(f"{recording['name']} changed the window to {window_size()}")
                contents, history, title = events("read", window).split("\x01")
                if title not in ("Terminal", "probe.command"):
                    recording["title"] = title
                else:
                    recording.pop("title", None)
                recording["reply"] = encode(reply[: -len(SYNC_REPLY)])
                recording["screen"] = text_lines(contents)
                if size != (ROWS, COLUMNS):
                    write(RESET + SYNC)
                    read_to_sync(2)
                    set_window_size()
                history_lines = text_lines(history)
                if history_lines != recording["screen"]:
                    recording["history"] = history_lines
                else:
                    recording.pop("history", None)
            with open(path, "w") as file:
                file.write(format_recordings(recordings))
    finally:
        termios.tcsetattr(terminal, termios.TCSADRAIN, original)


def record(paths):
    script = os.path.abspath(__file__)
    with tempfile.TemporaryDirectory() as state:
        subprocess.run(
            ["/usr/bin/swiftc", os.path.join(os.path.dirname(script), "terminal-app-events.swift"), "-o", os.path.join(state, "events")],
            check=True,
        )
        with open(os.path.join(state, "existing"), "w") as file:
            json.dump(sorted(terminal_processes()), file)
        command = os.path.join(state, "probe.command")
        arguments = " ".join(f"'{os.path.abspath(path)}'" for path in paths)
        with open(command, "w") as file:
            file.write(f"#!/bin/zsh\nexec /usr/bin/python3 -I '{script}' --probe '{state}' {arguments}\n")
        os.chmod(command, 0o755)
        subprocess.run(
            ["/usr/bin/open", "-n", "-g", "-a", "Terminal", command, "--args", "-ApplePersistenceIgnoreState", "YES", "-NSQuitAlwaysKeepsWindows", "NO", "-NSAppSleepDisabled", "YES"],
            check=True,
        )
        process_file = os.path.join(state, "process")
        done = os.path.join(state, "done")
        end = time.time() + 30
        while not os.path.exists(process_file) and not os.path.exists(done) and time.time() < end:
            time.sleep(0.1)
        if not os.path.exists(process_file):
            sys.exit(open(done).read() if os.path.exists(done) else "the separate Terminal.app process did not start")
        with open(process_file) as file:
            process = int(file.read())
        end = time.time() + TIME_LIMIT
        while not os.path.exists(done) and time.time() < end and process in terminal_processes():
            time.sleep(0.2)
        if process not in terminal_processes():
            with open(os.path.join(state, "current")) as file:
                sys.exit(f"Terminal.app crashed at {file.read()}")
        os.kill(process, signal.SIGTERM)
        if not os.path.exists(done):
            with open(os.path.join(state, "current")) as file:
                sys.exit(f"the recording did not finish, at {file.read()}")
        with open(done) as file:
            message = file.read()
    if message:
        sys.exit(message)


if sys.argv[1:2] == ["--probe"]:
    state = sys.argv[2]
    message = ""
    try:
        probe(state, sys.argv[3:])
    except Exception as error:
        message = repr(error)
    with open(os.path.join(state, "done"), "w") as file:
        file.write(message)
else:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    recordings = os.path.join(root, "Tests/TerminalCoreTests/Recordings")
    record(sys.argv[1:] or sorted(glob.glob(os.path.join(recordings, "*.json"))) + [os.path.join(recordings, "widths.txt")])
