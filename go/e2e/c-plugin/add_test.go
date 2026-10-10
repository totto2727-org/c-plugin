package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/cli"
)

func addScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	root := "/tmp/c-plugin-v2-add-e2e"
	home := root + "/home"
	project := home + "/project"
	repository := project + "/plugin"
	plugin := repository
	lockPath := project + "/c-plugin-lock.json"
	statePath := project + "/.agents/c-plugin-state.json"
	foreign := project + "/.agents/skills/alpha"
	link := project + "/.agents/skills/beta"
	scenario := newScenarioEnvironment(t, environment, home)
	scenario.writePlugin(project, "alpha", "beta")
	scenario.mkdirAll(project)
	scenario.requireSuccess(scenario.run(project, "init"))
	scenario.writeFile(foreign, "foreign\n")
	scenario.mkdirAll(project + "/nested")

	added := scenario.run(project+"/nested", "skill", "add",
		"--local", "./plugin",
		"--skill", "alpha",
		"--skill", "beta",
	)
	scenario.requireSuccess(added)
	scenario.requireContains(added.Stdout, "Added "+repository+" to "+lockPath+": partial")
	scenario.requireJSON(lockPath, localLock([]string{}, "plugin", []string{"alpha", "beta"}))
	scenario.requireSymlink(link, plugin+"/skills/beta")
	scenario.requireRegularFile(foreign)
	scenario.requireFile(foreign, "foreign\n")
	state := string(scenario.readFile(statePath))
	scenario.requireContains(state, `"skill": "beta"`)
	scenario.requireNotContains(state, `"skill": "alpha"`)
	beforeRepeat := scenario.digest(lockPath)
	stateBeforeRepeat := scenario.digest(statePath)

	repeat := scenario.run(project+"/nested", "skill", "add",
		"--local", "./plugin",
		"--skill", "alpha",
		"--skill", "beta",
	)
	scenario.requireFailure(repeat)
	scenario.requireContains(repeat.Stdout, "totto2727/c-plugin.AddLocalError.InvalidInput")
	scenario.requireDigest(lockPath, beforeRepeat)
	scenario.requireDigest(statePath, stateBeforeRepeat)
	scenario.requireRegularFile(foreign)
	scenario.requireFile(foreign, "foreign\n")
	scenario.requireSymlink(link, plugin+"/skills/beta")

	removed := scenario.run(project+"/nested", "skill", "remove",
		"--skill", "demo/alpha",
		"--skill", "demo/beta",
	)
	scenario.requireSuccess(removed)
	scenario.requireRegularFile(foreign)
	scenario.requireMissing(link)
	scenario.mkdirAll(link)
	scenario.writeFile(link+"/keep", "directory-content\n")
	neighbor := project + "/.agents/skills/neighbor"
	scenario.writeFile(neighbor, "neighbor\n")

	forced := scenario.run(project+"/nested", "skill", "add",
		"--local", "./plugin",
		"--skill", "alpha",
		"--skill", "beta",
		"--force",
	)
	scenario.requireSuccess(forced)
	scenario.requireContains(forced.Stdout, "Added "+repository+" to "+lockPath+": partial")
	scenario.requireSymlink(foreign, plugin+"/skills/alpha")
	scenario.requireDirectory(link)
	scenario.requireFile(link+"/keep", "directory-content\n")
	scenario.requireFile(neighbor, "neighbor\n")
	state = string(scenario.readFile(statePath))
	scenario.requireContains(state, `"skill": "alpha"`)
	scenario.requireNotContains(state, `"skill": "beta"`)
}
