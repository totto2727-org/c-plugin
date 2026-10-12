package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/go/cli"
)

func unifiedHelpHierarchyScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "unified-help", "alpha")
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--all"))
	lock := s.digest(project + "/c-plugin-lock.json")
	state := s.digest(project + "/.agents/c-plugin-state.json")
	for _, command := range [][]string{
		{}, {"plugin"}, {"skill"}, {"target"}, {"sync"}, {"update"}, {"list"},
		{"plugin", "list"}, {"plugin", "remove"}, {"skill", "list"}, {"skill", "remove"},
		{"plugin", "skill", "enable"}, {"plugin", "skill", "disable"},
		{"target", "add"}, {"target", "remove"},
	} {
		result := s.run(project, append(command, "--help")...)
		s.requireSuccess(result)
		s.requireContains(result.Stdout, "Available options:")
		s.requireDigest(project+"/c-plugin-lock.json", lock)
		s.requireDigest(project+"/.agents/c-plugin-state.json", state)
	}
	plugin := s.run(project, "plugin", "remove", "--help")
	s.requireContains(plugin.Stdout, "--plugin")
	s.requireNotContains(plugin.Stdout, "--skill")
	skill := s.run(project, "skill", "--help")
	s.requireNotContains(skill.Stdout, "  sync")
	s.requireNotContains(skill.Stdout, "  update")
	s.requireNotContains(skill.Stdout, "  target")
	remove := s.run(project, "skill", "remove", "--help")
	s.requireContains(remove.Stdout, "--skill")
	s.requireNotContains(remove.Stdout, "--plugin")
	for _, arguments := range [][]string{
		{"skill", "sync"}, {"skill", "update"}, {"skill", "target", "add", ".cursor/skills"},
		{"skill", "target", "remove", "--target", ".cursor/skills"},
		{"skill", "remove", "--plugin", "demo"}, {"plugin", "remove", "--skill", "demo/alpha"},
		{"target", "remove", "--plugin", "demo"}, {"target", "remove", "--skill", "alpha"},
		{"list", "--skill", "alpha"}, {"plugin", "list", "--plugin", "demo"},
		{"skill", "list", "--skill", "alpha"}, {"sync", "--skill", "alpha"}, {"update", "--plugin", "demo"},
	} {
		result := s.run(project, arguments...)
		s.requireFailure(result)
		s.requireDigest(project+"/c-plugin-lock.json", lock)
		s.requireDigest(project+"/.agents/c-plugin-state.json", state)
		s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
		s.requireMissing(project + "/.cursor")
	}
}

func pluginToggleScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "plugin-toggle", "alpha", "beta", "gamma")
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--none"))
	s.requireSuccess(s.run(project, "plugin", "skill", "enable", "demo", "--skill", "beta"))
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"beta"}))
	s.requireSuccess(s.run(project, "plugin", "skill", "enable", "demo", "--skill", "alpha"))
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"alpha", "beta"}))
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
	s.requireSymlink(project+"/.agents/skills/beta", project+"/plugin/skills/beta")
	s.requireMissing(project + "/.agents/skills/gamma")
	s.requireSuccess(s.run(project, "plugin", "skill", "disable", "demo", "--skill", "beta"))
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"alpha"}))
	s.requireMissing(project + "/.agents/skills/beta")
	s.remove(project + "/.agents/skills/alpha")
	lock := s.digest(project + "/c-plugin-lock.json")
	state := s.digest(project + "/.agents/c-plugin-state.json")
	for _, arguments := range [][]string{
		{"plugin", "skill", "enable", "demo", "--skill", "alpha"},
		{"plugin", "skill", "disable", "demo", "--skill", "beta"},
	} {
		s.requireSuccess(s.run(project, arguments...))
		s.requireDigest(project+"/c-plugin-lock.json", lock)
		s.requireDigest(project+"/.agents/c-plugin-state.json", state)
		s.requireMissing(project + "/.agents/skills/alpha")
	}
	for _, command := range []string{"enable", "disable"} {
		cancel := s.runTerminal(project, []string{"q"}, false, "plugin", "skill", command, "demo")
		s.requireTerminalSuccess(cancel)
		s.requireContains(cancel.Stdout, "Cancelled; no changes.")
		s.requireDigest(project+"/c-plugin-lock.json", lock)
		s.requireDigest(project+"/.agents/c-plugin-state.json", state)
		s.requireMissing(project + "/.agents/skills/alpha")
		for _, pipe := range []bool{false, true} {
			arguments := []string{"plugin", "skill", command, "demo"}
			if !pipe {
				arguments = append([]string{"--no-input"}, arguments...)
			}
			failure := s.runTerminal(project, nil, pipe, arguments...)
			s.requireTerminalFailure(failure)
			s.requireNotContains(failure.Stderr, selectionPrompt)
			s.requireContains(failure.Stdout, "--skill")
			s.requireContains(failure.Stdout, "--all")
			if pipe && failure.Unread != "unconsumed-input\n" {
				t.Fatalf("toggle pipe consumed: %+v", failure)
			}
			s.requireDigest(project+"/c-plugin-lock.json", lock)
			s.requireDigest(project+"/.agents/c-plugin-state.json", state)
		}
	}
	s.requireSuccess(s.run(project, "plugin", "skill", "disable", "demo", "--all"))
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{}))
	enabled := s.runTerminal(project, []string{"99", "2"}, false, "plugin", "skill", "enable", "demo")
	s.requireTerminalSuccess(enabled)
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"beta"}))
	s.requireSymlink(project+"/.agents/skills/beta", project+"/plugin/skills/beta")
	disabled := s.runTerminal(project, []string{"all"}, false, "plugin", "skill", "disable", "demo")
	s.requireTerminalSuccess(disabled)
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{}))
	s.requireMissing(project + "/.agents/skills/beta")
	s.writePlugin(s.home, "gamma")
	s.requireSuccess(s.run(project, "init", "--global"))
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--none", "--global"))
	s.mkdirAll(project + "/nested")
	lock = s.digest(project + "/c-plugin-lock.json")
	state = s.digest(project + "/.agents/c-plugin-state.json")
	s.requireSuccess(s.run(project+"/nested", "plugin", "skill", "enable", "demo", "--all", "-g"))
	s.requireJSON(s.home+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"gamma"}))
	s.requireSymlink(s.home+"/.agents/skills/gamma", s.home+"/plugin/skills/gamma")
	s.requireSuccess(s.run(project+"/nested", "plugin", "skill", "disable", "demo", "--skill", "gamma", "-g"))
	s.requireJSON(s.home+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{}))
	s.requireMissing(s.home + "/.agents/skills/gamma")
	s.requireDigest(project+"/c-plugin-lock.json", lock)
	s.requireDigest(project+"/.agents/c-plugin-state.json", state)
	for _, arguments := range [][]string{
		{"plugin", "skill", "enable", "missing", "--all"}, {"plugin", "skill", "disable", "missing", "--all"},
		{"plugin", "skill", "enable", "demo", "--skill", "unknown"}, {"plugin", "skill", "disable", "demo", "--skill", "unknown"},
		{"plugin", "skill", "enable", "--all"}, {"plugin", "skill", "disable", "--all"},
		{"plugin", "skill", "enable", "demo", "--none"}, {"plugin", "skill", "disable", "demo", "--none"},
		{"plugin", "skill", "enable", "demo", "--all", "--skill", "alpha"},
	} {
		s.requireFailure(s.run(project, arguments...))
		s.requireDigest(project+"/c-plugin-lock.json", lock)
		s.requireDigest(project+"/.agents/c-plugin-state.json", state)
	}
	s.writeFile(project+"/standalone/alpha/SKILL.md", skillMarkdown("alpha"))
	s.requireSuccess(s.run(project, "skill", "add", "local:./standalone/alpha"))
	lock = s.digest(project + "/c-plugin-lock.json")
	state = s.digest(project + "/.agents/c-plugin-state.json")
	s.requireFailure(s.run(project, "plugin", "skill", "enable", "demo", "--skill", "alpha"))
	s.requireDigest(project+"/c-plugin-lock.json", lock)
	s.requireDigest(project+"/.agents/c-plugin-state.json", state)
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/standalone/alpha")
	s.writeFile(project+"/other/plugin.json", `{"$schema":"`+pluginSchema+`","name":"other"}`)
	s.writeFile(project+"/other/skills/beta/SKILL.md", skillMarkdown("beta"))
	s.requireSuccess(s.run(project, "plugin", "add", "local:./other", "--all"))
	lock = s.digest(project + "/c-plugin-lock.json")
	state = s.digest(project + "/.agents/c-plugin-state.json")
	s.requireFailure(s.run(project, "plugin", "skill", "enable", "demo", "--skill", "beta"))
	s.requireDigest(project+"/c-plugin-lock.json", lock)
	s.requireDigest(project+"/.agents/c-plugin-state.json", state)
	s.requireSymlink(project+"/.agents/skills/beta", project+"/other/skills/beta")
	chosen := s.runTerminal(project, []string{"1,1", "1 2", "99", "1", "3"}, false, "plugin", "skill", "enable")
	s.requireTerminalSuccess(chosen)
	s.requireContains(chosen.Stderr, "1) demo\r\n")
	s.requireContains(chosen.Stderr, "2) other\r\n")
	s.requireContains(chosen.Stderr, "3) gamma [disabled]")
	s.requireNotContains(chosen.Stderr, "(entire plugin)")
	s.requireSymlink(project+"/.agents/skills/gamma", project+"/plugin/skills/gamma")
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/standalone/alpha")
	unselected := s.runTerminal(project, []string{"1", "3"}, false, "plugin", "skill", "disable")
	s.requireTerminalSuccess(unselected)
	s.requireContains(unselected.Stderr, "3) gamma [enabled]")
	s.requireMissing(project + "/.agents/skills/gamma")
	s.requireDigest(project+"/c-plugin-lock.json", lock)
	state = s.digest(project + "/.agents/c-plugin-state.json")
	for _, command := range []string{"enable", "disable"} {
		for _, pipe := range []bool{false, true} {
			arguments := []string{"plugin", "skill", command, "--all"}
			if !pipe {
				arguments = append([]string{"--no-input"}, arguments...)
			}
			failure := s.runTerminal(project, nil, pipe, arguments...)
			s.requireTerminalFailure(failure)
			s.requireContains(failure.Stdout, "PLUGIN")
			s.requireNotContains(failure.Stderr, selectionPrompt)
			if pipe && failure.Unread != "unconsumed-input\n" {
				t.Fatalf("plugin-selection pipe consumed: %+v", failure)
			}
			s.requireDigest(project+"/c-plugin-lock.json", lock)
			s.requireDigest(project+"/.agents/c-plugin-state.json", state)
		}
	}
	s.remove(project + "/plugin")
	for _, command := range []string{"enable", "disable"} {
		for _, action := range []string{"q", "", "<EOF>", "none"} {
			cancel := s.runTerminal(project, []string{action}, false, "plugin", "skill", command)
			s.requireTerminalSuccess(cancel)
			s.requireContains(cancel.Stdout, "Cancelled; no changes.")
			s.requireContains(cancel.Stderr, "1) demo\r\n")
			s.requireContains(cancel.Stderr, "2) other\r\n")
			s.requireNotContains(cancel.Stderr, "[disabled]")
			s.requireDigest(project+"/c-plugin-lock.json", lock)
			s.requireDigest(project+"/.agents/c-plugin-state.json", state)
			s.requireMissing(project + "/plugin")
		}
		s.requireFailure(s.run(project, "plugin", "skill", command, "demo", "--all"))
		s.requireDigest(project+"/c-plugin-lock.json", lock)
		s.requireDigest(project+"/.agents/c-plugin-state.json", state)
		s.requireMissing(project + "/plugin")
	}
}

func separatedRemovalScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "separated-removal", "alpha")
	s.writeFile(project+"/standalone/solo/SKILL.md", skillMarkdown("solo"))
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--all"))
	s.requireSuccess(s.run(project, "skill", "add", "local:./standalone/solo"))
	// Existing exact-target links without ownership must never be adopted or deleted.
	s.remove(project + "/.agents/c-plugin-state.json")
	s.requireSuccess(s.run(project, "sync"))
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
	s.requireSymlink(project+"/.agents/skills/solo", project+"/standalone/solo")
	s.requireJSON(project+"/.agents/c-plugin-state.json", `{"version":"1","entries":[]}`)
	lock := s.digest(project + "/c-plugin-lock.json")
	state := s.digest(project + "/.agents/c-plugin-state.json")
	for _, action := range []string{"q", "cancel", "", "<EOF>"} {
		cancel := s.runTerminal(project, []string{action}, false, "plugin", "remove")
		s.requireTerminalSuccess(cancel)
		s.requireContains(cancel.Stderr, "1) demo (entire plugin)")
		s.requireNotContains(cancel.Stderr, "demo/alpha")
		s.requireNotContains(cancel.Stderr, "solo")
		s.requireContains(cancel.Stdout, "Cancelled; no changes.")
		s.requireDigest(project+"/c-plugin-lock.json", lock)
		s.requireDigest(project+"/.agents/c-plugin-state.json", state)
	}
	removed := s.runTerminal(project, []string{"1"}, false, "skill", "remove")
	s.requireTerminalSuccess(removed)
	s.requireContains(removed.Stderr, "1) demo/alpha")
	s.requireContains(removed.Stderr, "2) solo (standalone skill)")
	s.requireNotContains(removed.Stderr, "(entire plugin)")
	s.requireJSON(project+"/c-plugin-lock.json", `{"version":"3","targets":[],"plugins":[{"source":"./plugin","name":"demo","skills":[]}],"skills":[{"name":"solo","source":"./standalone/solo"}]}`)
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
	s.requireSymlink(project+"/.agents/skills/solo", project+"/standalone/solo")
	disabled := s.runTerminal(project, []string{"1"}, false, "plugin", "remove")
	s.requireTerminalSuccess(disabled)
	s.requireContains(disabled.Stderr, "1) demo (entire plugin)")
	s.requireNotContains(disabled.Stderr, "solo")
	s.requireContains(disabled.Stdout, "Removed plugins demo")
	s.requireJSON(project+"/c-plugin-lock.json", soloLock)
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
	s.requireSymlink(project+"/.agents/skills/solo", project+"/standalone/solo")
	s.requireJSON(project+"/.agents/c-plugin-state.json", `{"version":"1","entries":[]}`)
	before := s.digest(project + "/c-plugin-lock.json")
	s.requireSuccess(s.run(project, "plugin", "remove", "--plugin", "demo"))
	s.requireDigest(project+"/c-plugin-lock.json", before)
	s.requireSuccess(s.run(project, "skill", "remove", "--skill", "solo"))
	s.requireJSON(project+"/c-plugin-lock.json", emptyLock)
	s.requireSymlink(project+"/.agents/skills/solo", project+"/standalone/solo")
}
