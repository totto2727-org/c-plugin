package cplugine2e

import (
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	"github.com/totto2727-org/e2e/go/cli"
)

// The fixture is invoked through the existing container runner, not a separate test runner.
// stdin and stderr share a real PTY while stdout stays independently observable.
const terminalDriver = `import errno, fcntl, json, os, pathlib, pty, re, select, signal, struct, subprocess, sys, termios, time
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
`

const (
	selectionPrompt = "Space: toggle"
	keyUp           = "\x1b[A"
	keyDown         = "\x1b[B"
	keySpace        = " "
	keyEnter        = "\r"
	keyEscape       = "\x1b"
	keyEOF          = "\x04"
	keyInterrupt    = "\x03"
)

type terminalResult struct {
	ExitCode        int    `json:"exit_code"`
	Stdout          string `json:"stdout"`
	Stderr          string `json:"stderr"`
	Sent            int    `json:"sent"`
	Unread          string `json:"unread"`
	Restored        bool   `json:"restored"`
	DisplayRestored bool   `json:"display_restored"`
}

func (s *scenarioEnvironment) runTerminal(directory string, actions []string, pipe bool, arguments ...string) terminalResult {
	s.t.Helper()
	return s.runTerminalWithTerm(directory, actions, pipe, "xterm", arguments...)
}

func (s *scenarioEnvironment) runTerminalWithTerm(directory string, actions []string, pipe bool, terminal string, arguments ...string) terminalResult {
	s.t.Helper()
	driver := s.home + "/terminal-driver.py"
	s.writeFile(driver, terminalDriver)
	request, err := json.Marshal(map[string]any{
		"home": s.home, "cwd": directory, "argv": append([]string{cPlugin}, arguments...),
		"actions": actions, "pipe": pipe, "prompt": selectionPrompt, "term": terminal,
	})
	if err != nil {
		s.t.Fatal(err)
	}
	result := s.runInfrastructure(directory, "/usr/bin/timeout", "15", "/usr/bin/python3", driver, string(request))
	s.requireSuccess(result)
	var actual terminalResult
	if err := json.Unmarshal([]byte(result.Stdout), &actual); err != nil {
		s.t.Fatalf("terminal JSON: %v output=%q", err, result.Stdout)
	}
	if actual.Sent != len(actions) {
		s.t.Fatalf("sent=%d want=%d terminal=%+v", actual.Sent, len(actions), actual)
	}
	if !actual.Restored {
		s.t.Fatalf("terminal settings were not restored: %+v", actual)
	}
	if !actual.DisplayRestored {
		s.t.Fatalf("alternate screen or cursor was not restored: %+v", actual)
	}
	s.requireNotContains(actual.Stdout, selectionPrompt)
	s.requireNotContains(actual.Stderr, "Select indexes")
	s.requireNotContains(actual.Stderr, "1) ")
	return actual
}

func (s *scenarioEnvironment) requireTerminalSuccess(result terminalResult) {
	s.t.Helper()
	if result.ExitCode != 0 {
		s.t.Fatalf("terminal exit=%d stdout=%q stderr=%q", result.ExitCode, result.Stdout, result.Stderr)
	}
}

func (s *scenarioEnvironment) requireTerminalFailure(result terminalResult) {
	s.t.Helper()
	if result.ExitCode == 0 {
		s.t.Fatalf("expected terminal failure: %+v", result)
	}
}

func interactiveFixture(t *testing.T, environment *cli.Environment, name string) (*scenarioEnvironment, string) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "interactive-"+name, "alpha", "beta", "gamma")
	s.writePlugin(s.home, "alpha", "beta", "gamma")
	s.requireSuccess(s.run(project, "init", "--global"))
	return s, project
}

func interactiveSelectionScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := interactiveFixture(t, environment, "selection")
	globalBefore := s.digest(s.home + "/c-plugin-lock.json")
	added := s.runTerminal(project, []string{keySpace + keyDown + keyDown + keySpace + keyEnter}, false, "plugin", "add", "local:./plugin")
	s.requireTerminalSuccess(added)
	s.requireContains(added.Stderr, "alpha [disabled]")
	s.requireContains(added.Stderr, "beta [disabled]")
	s.requireContains(added.Stderr, "gamma [disabled]")
	s.requireContains(added.Stdout, "Added ")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"alpha", "gamma"}))
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
	s.requireSymlink(project+"/.agents/skills/gamma", project+"/plugin/skills/gamma")
	s.requireMissing(project + "/.agents/skills/beta")
	removed := s.runTerminal(project, []string{keyDown + keySpace + keyEnter}, false, "skill", "remove")
	s.requireTerminalSuccess(removed)
	s.requireNotContains(removed.Stderr, "(entire plugin)")
	s.requireContains(removed.Stderr, "demo/alpha")
	s.requireContains(removed.Stderr, "demo/gamma")
	s.requireContains(removed.Stdout, "Removed skills demo/gamma")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"alpha"}))
	s.requireMissing(project + "/.agents/skills/gamma")
	s.requireOwnershipSkill(string(s.readFile(project+"/.agents/c-plugin-state.json")), "gamma", false)
	s.requireSuccess(s.run(project, "target", "add", ".claude/skills"))
	s.requireSuccess(s.run(project, "target", "add", ".cursor/skills"))
	target := s.runTerminal(project, []string{keyDown + keySpace + keyEnter}, false, "target", "remove")
	s.requireTerminalSuccess(target)
	s.requireContains(target.Stderr, ".claude/skills")
	s.requireContains(target.Stderr, ".cursor/skills")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{".claude/skills"}, "plugin", []string{"alpha"}))
	s.requireMissing(project + "/.cursor/skills/alpha")
	s.requireSymlink(project+"/.claude/skills/alpha", project+"/plugin/skills/alpha")
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
	s.requireNotContains(string(s.readFile(project+"/.agents/c-plugin-state.json")), project+"/.cursor/skills")
	s.requireDigest(s.home+"/c-plugin-lock.json", globalBefore)
	s.requireMissing(s.home + "/.agents/c-plugin-state.json")
}

func interactiveGlobalScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := interactiveFixture(t, environment, "global")
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--all"))
	lockBefore := s.digest(project + "/c-plugin-lock.json")
	stateBefore := s.digest(project + "/.agents/c-plugin-state.json")
	s.mkdirAll(project + "/nested")
	added := s.runTerminal(project+"/nested", []string{keySpace + keyDown + keySpace + keyDown + keySpace + keyEnter}, false, "plugin", "add", "--global", "local:./plugin")
	s.requireTerminalSuccess(added)
	s.requireJSON(s.home+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"alpha", "beta", "gamma"}))
	s.requireSuccess(s.run(project, "target", "add", "--global", ".cursor/skills"))
	target := s.runTerminal(project+"/nested", []string{keySpace + keyEnter}, false, "target", "remove", "--global")
	s.requireTerminalSuccess(target)
	s.requireMissing(s.home + "/.cursor/skills/alpha")
	removed := s.runTerminal(project+"/nested", []string{keySpace + keyDown + keyDown + keySpace + keyEnter}, false, "skill", "remove", "--global")
	s.requireTerminalSuccess(removed)
	s.requireJSON(s.home+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"beta"}))
	s.requireMissing(s.home + "/.agents/skills/alpha")
	s.requireMissing(s.home + "/.agents/skills/gamma")
	s.requireSymlink(s.home+"/.agents/skills/beta", s.home+"/plugin/skills/beta")
	s.requireDigest(project+"/c-plugin-lock.json", lockBefore)
	s.requireDigest(project+"/.agents/c-plugin-state.json", stateBefore)
	for _, skill := range []string{"alpha", "beta", "gamma"} {
		s.requireSymlink(project+"/.agents/skills/"+skill, project+"/plugin/skills/"+skill)
	}
}

func interactiveNoOp(s *scenarioEnvironment, project string, actions ...string) {
	s.t.Helper()
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--all"))
	s.requireSuccess(s.run(project, "target", "add", ".cursor/skills"))
	s.remove(project+"/.agents/skills/alpha", project+"/.cursor/skills/alpha")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	for _, action := range actions {
		for _, arguments := range [][]string{
			{"plugin", "add", "local:./plugin"}, {"skill", "remove"}, {"target", "remove"},
		} {
			result := s.runTerminal(project, []string{action}, false, arguments...)
			s.requireTerminalSuccess(result)
			s.requireContains(result.Stdout, "Cancelled; no changes.")
			s.requireFile(project+"/c-plugin-lock.json", lock)
			s.requireFile(project+"/.agents/c-plugin-state.json", state)
			s.requireMissing(project + "/.agents/skills/alpha")
			s.requireMissing(project + "/.cursor/skills/alpha")
			s.requireSymlink(project+"/.agents/skills/beta", project+"/plugin/skills/beta")
		}
	}
}

func interactiveCancelScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := interactiveFixture(t, environment, "cancel")
	interactiveNoOp(s, project, "q", keyEscape)
}

func interactiveEmptyScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := interactiveFixture(t, environment, "empty")
	registered := s.runTerminal(project, []string{keyEnter}, false, "plugin", "add", "local:./plugin")
	s.requireTerminalSuccess(registered)
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{}))
	s.requireJSON(project+"/.agents/c-plugin-state.json", `{"ownershipEntries":{}}`)
	for _, skill := range []string{"alpha", "beta", "gamma"} {
		s.requireMissing(project + "/.agents/skills/" + skill)
	}
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--all"))
	s.requireSuccess(s.run(project, "target", "add", ".cursor/skills"))
	s.remove(project+"/.agents/skills/alpha", project+"/.cursor/skills/alpha")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	for _, keys := range []string{keyEnter, keySpace + keySpace + keyEnter} {
		for _, arguments := range [][]string{{"skill", "remove"}, {"target", "remove"}} {
			result := s.runTerminal(project, []string{keys}, false, arguments...)
			s.requireTerminalSuccess(result)
			s.requireContains(result.Stdout, "No selection; no changes.")
			s.requireFile(project+"/c-plugin-lock.json", lock)
			s.requireFile(project+"/.agents/c-plugin-state.json", state)
			s.requireMissing(project + "/.agents/skills/alpha")
			s.requireMissing(project + "/.cursor/skills/alpha")
			s.requireSymlink(project+"/.agents/skills/beta", project+"/plugin/skills/beta")
		}
	}
	disabled := s.runTerminal(project, []string{keyEnter}, false, "plugin", "add", "local:./plugin")
	s.requireTerminalSuccess(disabled)
	s.requireContains(disabled.Stderr, "alpha [enabled]")
	s.requireContains(disabled.Stderr, "beta [enabled]")
	s.requireContains(disabled.Stderr, "gamma [enabled]")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{".cursor/skills"}, "plugin", []string{}))
	s.requireJSON(project+"/.agents/c-plugin-state.json", `{"ownershipEntries":{}}`)
	for _, root := range []string{".agents/skills", ".cursor/skills"} {
		for _, skill := range []string{"alpha", "beta", "gamma"} {
			s.requireMissing(project + "/" + root + "/" + skill)
		}
	}
	enabled := s.runTerminal(project, []string{keyDown + keySpace + keyEnter}, false, "plugin", "add", "local:./plugin")
	s.requireTerminalSuccess(enabled)
	s.requireContains(enabled.Stderr, "beta [disabled]")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{".cursor/skills"}, "plugin", []string{"beta"}))
	changed := s.runTerminal(project, []string{keySpace + keyDown + keyDown + keySpace + keyEnter}, false, "plugin", "add", "local:./plugin")
	s.requireTerminalSuccess(changed)
	s.requireContains(changed.Stderr, "alpha [disabled]")
	s.requireContains(changed.Stderr, "beta [enabled]")
	s.requireContains(changed.Stderr, "gamma [disabled]")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{".cursor/skills"}, "plugin", []string{"alpha", "gamma"}))
	for _, root := range []string{".agents/skills", ".cursor/skills"} {
		s.requireMissing(project + "/" + root + "/beta")
		for _, skill := range []string{"alpha", "gamma"} {
			s.requireSymlink(project+"/"+root+"/"+skill, project+"/plugin/skills/"+skill)
		}
	}
}

func interactiveInvalidScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := interactiveFixture(t, environment, "invalid")
	result := s.runTerminal(project, []string{"1,199xyz" + keySpace + keySpace + keyDown + keySpace + keyUp + keySpace + keyEnter}, false, "plugin", "add", "local:./plugin")
	s.requireTerminalSuccess(result)
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"alpha", "beta"}))
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
	s.requireSymlink(project+"/.agents/skills/beta", project+"/plugin/skills/beta")
	s.requireMissing(project + "/.agents/skills/gamma")
	var scrollSkills []string
	for index := range 50 {
		scrollSkills = append(scrollSkills, fmt.Sprintf("scroll-%02d", index))
	}
	s.writePlugin(project, scrollSkills...)
	scrolled := s.runTerminal(project, []string{"<TINY>", "<TINY_CONFIRM>", strings.Repeat(keyDown, 52) + keySpace + keyEnter}, false, "plugin", "add", "local:./plugin")
	s.requireTerminalSuccess(scrolled)
	s.requireContains(scrolled.Stderr, "scroll-49 [disabled]")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"scroll-49"}))
	s.requireSymlink(project+"/.agents/skills/scroll-49", project+"/plugin/skills/scroll-49")
	for _, skill := range append([]string{"alpha", "beta", "gamma"}, scrollSkills[:49]...) {
		s.requireMissing(project + "/.agents/skills/" + skill)
	}
}

func interactiveNoInputScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := interactiveFixture(t, environment, "no-input")
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--all"))
	s.requireSuccess(s.run(project, "target", "add", ".cursor/skills"))
	s.remove(project + "/.agents/skills/alpha")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	for index, arguments := range [][]string{
		{"--no-input", "plugin", "add", "local:./plugin"}, {"--no-input", "skill", "remove"}, {"--no-input", "target", "remove"},
	} {
		result := s.runTerminal(project, nil, false, arguments...)
		s.requireTerminalFailure(result)
		s.requireNotContains(result.Stderr, selectionPrompt)
		for _, option := range [][]string{{"--all", "--none", "--skill"}, {"--skill"}, {"--target"}}[index] {
			s.requireContains(result.Stdout, option)
		}
		s.requireFile(project+"/c-plugin-lock.json", lock)
		s.requireFile(project+"/.agents/c-plugin-state.json", state)
		s.requireMissing(project + "/.agents/skills/alpha")
	}
}

func interactivePipeScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := interactiveFixture(t, environment, "pipe")
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--all"))
	s.requireSuccess(s.run(project, "target", "add", ".cursor/skills"))
	s.remove(project + "/.agents/skills/alpha")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	for index, arguments := range [][]string{{"plugin", "add", "local:./plugin"}, {"skill", "remove"}, {"target", "remove"}} {
		result := s.runTerminal(project, nil, true, arguments...)
		s.requireTerminalFailure(result)
		s.requireNotContains(result.Stderr, selectionPrompt)
		for _, option := range [][]string{{"--all", "--none", "--skill"}, {"--skill"}, {"--target"}}[index] {
			s.requireContains(result.Stdout, option)
		}
		if result.Unread != "unconsumed-input\n" {
			t.Fatalf("pipe input consumed: %+v", result)
		}
		s.requireFile(project+"/c-plugin-lock.json", lock)
		s.requireFile(project+"/.agents/c-plugin-state.json", state)
		s.requireMissing(project + "/.agents/skills/alpha")
	}
}

func interactiveInterruptScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := interactiveFixture(t, environment, "interrupt")
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--all"))
	s.remove(project + "/.agents/skills/alpha")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	for _, action := range []string{keyInterrupt, "<SIGINT>"} {
		result := s.runTerminal(project, []string{action}, false, "skill", "remove")
		s.requireTerminalFailure(result)
		s.requireNotContains(result.Stdout, "Cancelled; no changes.")
		s.requireFile(project+"/c-plugin-lock.json", lock)
		s.requireFile(project+"/.agents/c-plugin-state.json", state)
		s.requireMissing(project + "/.agents/skills/alpha")
		s.requireSymlink(project+"/.agents/skills/beta", project+"/plugin/skills/beta")
	}
	invalidTerm := s.runTerminalWithTerm(project, nil, false, "c-plugin-no-such-terminal", "skill", "remove")
	s.requireTerminalFailure(invalidTerm)
	s.requireNotContains(invalidTerm.Stderr, selectionPrompt)
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireFile(project+"/.agents/c-plugin-state.json", state)
	s.requireMissing(project + "/.agents/skills/alpha")
	s.requireSymlink(project+"/.agents/skills/beta", project+"/plugin/skills/beta")
}

func interactiveEOFScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := interactiveFixture(t, environment, "eof")
	interactiveNoOp(s, project, keyEOF)
}
