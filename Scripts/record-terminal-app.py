#!/usr/bin/python3 -I
import fcntl, glob, json, os, re, select, struct, subprocess, sys, termios, tempfile, time, tty

COLUMNS = 40
ROWS = 12
TIME_LIMIT = 900
SYNC = b"\x1b[>c"
PROBE = b"\x1b[6n"
SYNC_REPLY = b"\x1b[>1;95;0c"
RESET = (
    b"\x1b[?1049l\x1b[?47l\x1b[!p\x1b[r\x1b[?7h\x1b[?6l\x1b[?5l\x1b[?3l\x1b[?40l\x1b[?25h\x1b[?1l\x1b>"
    b"\x1b[4l\x1b[20l\x1b(B\x1b)B\x0f\x1b[m\x1b[0 q\x1b]104\x07\x1b]110\x07\x1b]111\x07\x1b]2;\x07"
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


def osascript(script):
    result = subprocess.run(["/usr/bin/osascript", "-e", script], capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip())
    return result.stdout.rstrip("\n")


def text_lines(text):
    lines = text.split("\n")
    while lines and not lines[-1].strip(" "):
        lines.pop()
    return lines


def probe(window, paths):
    tab = f"tab 1 of window id {window}"
    terminal = os.open("/dev/tty", os.O_RDWR)

    def window_size():
        rows, columns, _, _ = struct.unpack("4H", fcntl.ioctl(terminal, termios.TIOCGWINSZ, b"\0" * 8))
        return rows, columns

    def set_window_size():
        osascript(
            f'tell application "Terminal"\n'
            f"set number of columns of {tab} to {COLUMNS}\n"
            f"set number of rows of {tab} to {ROWS}\n"
            f"end tell"
        )
        time.sleep(0.8)
        if window_size() != (ROWS, COLUMNS):
            raise RuntimeError(f"window is {window_size()}")

    set_window_size()

    def write(data):
        while data:
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

    def contents_and_history():
        return osascript(
            f'tell application "Terminal" to return (contents of {tab}) & (ASCII character 1) & (history of {tab}) & (ASCII character 1) & (custom title of {tab})'
        ).split("\x01")

    original = termios.tcgetattr(terminal)
    tty.setraw(terminal)
    try:
        for path in paths:
            with open(path) as file:
                recordings = json.load(file)
            for recording in recordings:
                write(RESET + SYNC)
                if not read_to_sync(2)[1]:
                    write(b"\x07\x1b\\" + RESET + SYNC)
                    if not read_to_sync(2)[1]:
                        raise RuntimeError(f"no reply after reset before {recording['name']}")
                write(decode(recording["input"]) + PROBE + SYNC)
                reply, synced = read_to_sync(3)
                if not synced:
                    raise RuntimeError(f"no reply to {recording['name']}: {reply!r}")
                if window_size() != (ROWS, COLUMNS):
                    raise RuntimeError(f"{recording['name']} changed the window to {window_size()}")
                contents, history, title = contents_and_history()
                if title != "Terminal":
                    recording["title"] = title
                else:
                    recording.pop("title", None)
                recording["reply"] = encode(reply[: -len(SYNC_REPLY)])
                recording["screen"] = text_lines(contents)
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
    with tempfile.TemporaryDirectory() as folder:
        done = os.path.join(folder, "done")
        log = os.path.join(folder, "log")
        window_file = os.path.join(folder, "window")
        arguments = " ".join(f"'{os.path.abspath(path)}'" for path in paths)
        command = (
            f"unset HISTFILE; exec /usr/bin/python3 -I '{os.path.abspath(__file__)}'"
            f" --probe '{window_file}' '{done}' '{log}' {arguments}"
        )
        reply = osascript(f'tell application "Terminal" to do script "{command}"')
        owned = re.fullmatch(r"tab 1 of window id (\d+)", reply)
        tab_count = owned and osascript(f'tell application "Terminal" to count tabs of window id {owned.group(1)}')
        if tab_count != "1":
            with open(window_file, "w") as file:
                file.write("")
            sys.exit(f"Terminal.app did not open a new window: {reply}")
        window = owned.group(1)
        osascript(f'tell application "Terminal" to set visible of window id {window} to false')
        with open(window_file + ".tmp", "w") as file:
            file.write(window)
        os.rename(window_file + ".tmp", window_file)
        end = time.time() + TIME_LIMIT
        try:
            while not os.path.exists(done) and time.time() < end:
                time.sleep(0.2)
        finally:
            osascript(f'tell application "Terminal" to if exists window id {window} then close window id {window}')
        if not os.path.exists(done):
            sys.exit("the recording did not finish")
        with open(log) as file:
            message = file.read()
    if message:
        sys.exit(message)


if sys.argv[1:2] == ["--probe"]:
    window_file, done, log = sys.argv[2:5]
    while not os.path.exists(window_file):
        time.sleep(0.05)
    with open(window_file) as file:
        window = file.read()
    if not window:
        sys.exit()
    message = ""
    try:
        probe(window, sys.argv[5:])
    except Exception as error:
        message = repr(error)
    with open(log, "w") as file:
        file.write(message)
    open(done, "w").close()
else:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    record(sys.argv[1:] or sorted(glob.glob(os.path.join(root, "Tests/TerminalCoreTests/Recordings/*.json"))))
