import errno, fcntl, json, os, pathlib, pty, re, select, signal, struct, subprocess, sys, termios, time
request = json.loads(sys.argv[1])
master, slave = pty.openpty()
fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
def terminal_settings():
    current = termios.tcgetattr(slave)
    # PENDIN is kernel input-replay bookkeeping, not a mode owned by the CLI.
    current[3] &= ~getattr(termios, "PENDIN", 0)
    return current
initial_settings = terminal_settings()
read_end = write_end = None
if request.get("pipe"):
    read_end, write_end = os.pipe()
    os.write(write_end, b"unconsumed-input\n")
    os.close(write_end)
input_fd = read_end if read_end is not None else slave
env = dict(os.environ, HOME=request["home"], TERM=request["term"])
child = subprocess.Popen(request["argv"], cwd=request["cwd"], env=env,
    stdin=input_fd, stderr=slave, stdout=subprocess.PIPE, start_new_session=True)
streams = {master: "stderr", child.stdout.fileno(): "stdout"}
output = {"stdout": b"", "stderr": b""}
actions = request.get("actions") or []
step = 0
cursor = 0
deadline = time.monotonic() + 10
try:
    while streams:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError("CLI timeout: " + repr(output))
        ready, _, _ = select.select(list(streams), [], [], min(remaining, 0.05))
        if not ready and child.poll() is not None:
            streams.pop(master, None)
            continue
        for fd in ready:
            try:
                data = os.read(fd, 65536)
            except OSError as error:
                if error.errno != errno.EIO:
                    raise
                data = b""
            if not data:
                del streams[fd]
                continue
            channel = streams[fd]
            output[channel] += data
            if channel == "stderr" and step < len(actions):
                marker = ("Enlarge terminal" if actions[step] == "<TINY_CONFIRM>" else request["prompt"]).encode()
                found = output["stderr"].find(marker, cursor)
                if found >= 0:
                    cursor = len(output["stderr"])
                    action = actions[step]
                    if action == "<TINY>":
                        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 2, 80, 0, 0))
                        os.killpg(child.pid, signal.SIGWINCH)
                    elif action == "<TINY_CONFIRM>":
                        paths = [pathlib.Path(request["cwd"]) / name for name in ["c-plugin-lock.json", ".agents/c-plugin-state.json"]]
                        before = [path.read_bytes() if path.exists() else None for path in paths]
                        os.write(master, b"\r")
                        ready, _, _ = select.select([child.stdout.fileno()], [], [], 0.2)
                        if ready or child.poll() is not None:
                            raise RuntimeError("tiny-terminal Enter confirmed before enlargement")
                        after = [path.read_bytes() if path.exists() else None for path in paths]
                        if before != after:
                            raise RuntimeError("tiny-terminal Enter changed persisted state")
                        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 12, 80, 0, 0))
                        os.killpg(child.pid, signal.SIGWINCH)
                    elif action == "<RESIZE>":
                        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 12, 80, 0, 0))
                        os.killpg(child.pid, signal.SIGWINCH)
                    elif action == "<SIGINT>":
                        os.killpg(child.pid, signal.SIGINT)
                    else:
                        os.write(master, action.encode())
                    step += 1
    status = child.wait(timeout=max(0.1, deadline - time.monotonic()))
    unread = os.read(read_end, 65536).decode() if read_end is not None else ""
    restored = terminal_settings() == initial_settings
    modes = [(b"\x1b[?1049h", b"\x1b[?1049l"), (b"\x1b[?25l", b"\x1b[?25h")]
    display_restored = all(enter not in output["stderr"] or output["stderr"].rfind(leave) > output["stderr"].rfind(enter) for enter, leave in modes)
    if actions:
        display_restored = display_restored and all(enter in output["stderr"] for enter, _ in modes)
    escape = re.compile(rb"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\)|[()][0-2A-Z]|[=>])")
    stderr = escape.sub(b"", output["stderr"]).decode(errors="replace")
    print(json.dumps(dict(exit_code=status, stdout=output["stdout"].decode(errors="replace"),
        stderr=stderr, sent=step, unread=unread, restored=restored, display_restored=display_restored)))
finally:
    if child.poll() is None:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait()
    child.stdout.close()
    os.close(master)
    os.close(slave)
    if read_end is not None:
        os.close(read_end)
