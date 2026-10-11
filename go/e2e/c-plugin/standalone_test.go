package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/cli"
)

func standaloneFixture(t *testing.T, environment *cli.Environment, name string) (*scenarioEnvironment, string) {
	t.Helper()
	home := "/tmp/c-plugin-standalone-" + name + "/home"
	project := home + "/project"
	s := newScenarioEnvironment(t, environment, home)
	s.writeFile(project+"/standalone/solo/SKILL.md", skillMarkdown("solo"))
	s.requireSuccess(s.run(project, "init"))
	return s, project
}

const soloLock = `{"version":"3","targets":[],"plugins":[],"skills":[{"name":"solo","source":"./standalone/solo"}]}`

func standaloneLifecycleScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standaloneFixture(t, environment, "lifecycle")
	s.mkdirAll(project + "/nested")
	added := s.run(project+"/nested", "skill", "add", "local:./standalone/solo")
	s.requireSuccess(added)
	s.requireContains(added.Stdout, "Added skill "+project+"/standalone/solo")
	s.requireJSON(project+"/c-plugin-lock.json", soloLock)
	s.requireSymlink(project+"/.agents/skills/solo", project+"/standalone/solo")
	s.requireMissing(project + "/standalone/solo/plugin.json")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	s.remove(project + "/.agents/skills/solo")
	repeat := s.run(project+"/nested", "skill", "add", "local:./standalone/solo")
	s.requireSuccess(repeat)
	s.requireOutput(repeat, "No skill changes for "+project+"/c-plugin-lock.json\n")
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireFile(project+"/.agents/c-plugin-state.json", state)
	s.requireMissing(project + "/.agents/skills/solo")
	s.requireSuccess(s.run(project, "skill", "sync"))
	s.requireSymlink(project+"/.agents/skills/solo", project+"/standalone/solo")
	removed := s.run(project+"/nested", "skill", "remove", "--skill", "solo")
	s.requireSuccess(removed)
	s.requireJSON(project+"/c-plugin-lock.json", emptyLock)
	s.requireJSON(project+"/.agents/c-plugin-state.json", `{"version":"1","entries":[]}`)
	s.requireMissing(project + "/.agents/skills/solo")
}

func standaloneGlobalScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standaloneFixture(t, environment, "global")
	s.writeFile(s.home+"/standalone/solo/SKILL.md", skillMarkdown("solo"))
	s.requireSuccess(s.run(project, "init", "--global"))
	s.requireSuccess(s.run(project, "skill", "add", "local:./standalone/solo"))
	projectLock := string(s.readFile(project + "/c-plugin-lock.json"))
	projectState := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	s.mkdirAll(project + "/nested")
	s.requireSuccess(s.run(project+"/nested", "skill", "add", "--global", "local:./standalone/solo"))
	s.requireJSON(s.home+"/c-plugin-lock.json", soloLock)
	s.requireSymlink(s.home+"/.agents/skills/solo", s.home+"/standalone/solo")
	s.requireSuccess(s.run(project+"/nested", "skill", "remove", "--global", "--skill", "solo"))
	s.requireJSON(s.home+"/c-plugin-lock.json", emptyLock)
	s.requireMissing(s.home + "/.agents/skills/solo")
	s.requireFile(project+"/c-plugin-lock.json", projectLock)
	s.requireFile(project+"/.agents/c-plugin-state.json", projectState)
	s.requireSymlink(project+"/.agents/skills/solo", project+"/standalone/solo")
}

func explicitRootScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standaloneFixture(t, environment, "explicit-root")
	s.writePlugin(project+"/plugins", "alpha")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	for _, arguments := range [][]string{
		{"skill", "add", "local:./standalone"},
		{"plugin", "add", "local:./plugins", "--all"},
	} {
		result := s.run(project, arguments...)
		s.requireFailure(result)
		s.requireFile(project+"/c-plugin-lock.json", lock)
		s.requireMissing(project + "/.agents/c-plugin-state.json")
		s.requireMissing(project + "/.agents/skills/solo")
		s.requireMissing(project + "/.agents/skills/alpha")
	}
}

func standaloneDuplicateScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standaloneFixture(t, environment, "duplicate")
	s.requireSuccess(s.run(project, "skill", "add", "local:./standalone/solo"))
	s.writeFile(project+"/other/solo/SKILL.md", skillMarkdown("solo"))
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	result := s.run(project, "skill", "add", "local:./other/solo")
	s.requireFailure(result)
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireFile(project+"/.agents/c-plugin-state.json", state)
	s.requireSymlink(project+"/.agents/skills/solo", project+"/standalone/solo")
}

func standaloneUnavailableScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standaloneFixture(t, environment, "unavailable")
	s.requireSuccess(s.run(project, "skill", "add", "local:./standalone/solo"))
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	literal := s.runInfrastructure("", "readlink", project+"/.agents/skills/solo")
	s.requireSuccess(literal)
	s.remove(project + "/standalone/solo")
	result := s.run(project, "skill", "sync")
	s.requireSuccess(result)
	s.requireContains(result.Stdout, "partial")
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireFile(project+"/.agents/c-plugin-state.json", state)
	s.requireSuccess(s.runInfrastructure("", "test", "-L", project+"/.agents/skills/solo"))
	after := s.runInfrastructure("", "readlink", project+"/.agents/skills/solo")
	s.requireSuccess(after)
	s.requireOutput(after, literal.Stdout)
}

func standaloneInvalidScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standaloneFixture(t, environment, "invalid")
	s.writeFile(project+"/standalone/solo/SKILL.md", "---\nname: solo\n---\n")
	s.writeFile(project+"/.agents/skills/foreign", "foreign\n")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	result := s.run(project, "skill", "add", "local:./standalone/solo")
	s.requireFailure(result)
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireMissing(project + "/.agents/c-plugin-state.json")
	s.requireMissing(project + "/.agents/skills/solo")
	s.requireFile(project+"/.agents/skills/foreign", "foreign\n")
}

func standaloneEscapeScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standaloneFixture(t, environment, "escape")
	outside := s.home + "/outside/SKILL.md"
	s.writeFile(outside, skillMarkdown("solo"))
	digest := s.digest(outside)
	s.remove(project + "/standalone/solo/SKILL.md")
	s.requireSuccess(s.runInfrastructure("", "ln", "-s", outside, project+"/standalone/solo/SKILL.md"))
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	result := s.run(project, "skill", "add", "local:./standalone/solo")
	s.requireFailure(result)
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireDigest(outside, digest)
	s.requireSymlink(project+"/standalone/solo/SKILL.md", outside)
	s.requireMissing(project + "/.agents/c-plugin-state.json")
	s.requireMissing(project + "/.agents/skills/solo")
}

func standalonePluginConflictScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standaloneFixture(t, environment, "plugin-conflict")
	s.writePlugin(project, "alpha")
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--all"))
	s.writeFile(project+"/standalone/alpha/SKILL.md", skillMarkdown("alpha"))
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	result := s.run(project, "skill", "add", "local:./standalone/alpha")
	s.requireFailure(result)
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireFile(project+"/.agents/c-plugin-state.json", state)
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
}

func pluginEnabledSetScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "enabled-set", "alpha", "beta")
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--all"))
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--skill", "beta"))
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"beta"}))
	s.requireMissing(project + "/.agents/skills/alpha")
	s.requireSymlink(project+"/.agents/skills/beta", project+"/plugin/skills/beta")
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--none"))
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{}))
	s.requireJSON(project+"/.agents/c-plugin-state.json", `{"version":"1","entries":[]}`)
	s.requireMissing(project + "/.agents/skills/beta")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	repeat := s.run(project, "plugin", "add", "local:./plugin", "--none")
	s.requireSuccess(repeat)
	s.requireOutput(repeat, "No skill changes for "+project+"/c-plugin-lock.json\n")
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireFile(project+"/.agents/c-plugin-state.json", state)
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--all"))
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"alpha", "beta"}))
	for _, skill := range []string{"alpha", "beta"} {
		s.requireSymlink(project+"/.agents/skills/"+skill, project+"/plugin/skills/"+skill)
	}
	lock = string(s.readFile(project + "/c-plugin-lock.json"))
	state = string(s.readFile(project + "/.agents/c-plugin-state.json"))
	for _, selectors := range [][]string{{"--all", "--skill", "alpha"}, {"--all", "--none"}, {"--none", "--skill", "alpha"}} {
		arguments := append([]string{"plugin", "add", "local:./plugin"}, selectors...)
		result := s.run(project, arguments...)
		s.requireFailure(result)
		s.requireFile(project+"/c-plugin-lock.json", lock)
		s.requireFile(project+"/.agents/c-plugin-state.json", state)
		for _, skill := range []string{"alpha", "beta"} {
			s.requireSymlink(project+"/.agents/skills/"+skill, project+"/plugin/skills/"+skill)
		}
	}
}
