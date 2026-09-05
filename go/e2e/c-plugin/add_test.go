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
	repository := project + "/marketplace"
	plugin := repository + "/plugins/demo"
	lockPath := project + "/c-plugin-lock.json"
	statePath := project + "/.agents/c-plugin-state.json"
	foreign := project + "/.agents/skills/alpha"
	link := project + "/.agents/skills/beta"
	scenario := newScenarioEnvironment(t, environment, home)
	scenario.writeMarketplaceSkills(project, "alpha", "beta")
	scenario.mkdirAll(project)
	scenario.requireSuccess(scenario.run(project, "init"))
	scenario.writeFile(foreign, "foreign\n")
	scenario.mkdirAll(project + "/nested")

	added := scenario.run(project+"/nested", "skill", "add",
		"--local", "./marketplace",
		"--kind", "claude",
		"--skill", "demo/alpha",
		"--skill", "demo/beta",
	)
	scenario.requireSuccess(added)
	scenario.requireOutput(added, "Added "+repository+" to "+lockPath+": partial (2 notices, 0 unavailable repositories)\n")
	scenario.requireJSON(lockPath, localLock([]string{}, "marketplace", []string{"alpha", "beta"}))
	scenario.requireSymlink(link, plugin+"/skills/beta")
	scenario.requireRegularFile(foreign)
	scenario.requireFile(foreign, "foreign\n")
	state := string(scenario.readFile(statePath))
	scenario.requireContains(state, `"skill": "beta"`)
	scenario.requireNotContains(state, `"skill": "alpha"`)
	beforeRepeat := scenario.digest(lockPath)

	repeat := scenario.run(project+"/nested", "skill", "add",
		"--local", "./marketplace",
		"--kind", "claude",
		"--skill", "demo/alpha",
		"--skill", "demo/beta",
	)
	scenario.requireFailure(repeat)
	scenario.requireContains(repeat.Stdout, "totto2727/c-plugin.AddLocalError.InvalidInput")
	scenario.requireDigest(lockPath, beforeRepeat)
	scenario.requireSymlink(link, plugin+"/skills/beta")
	scenario.requireContains(string(scenario.readFile(statePath)), `"skill": "beta"`)

	removed := scenario.run(project+"/nested", "skill", "remove",
		"--skill", "marketplace/demo/alpha",
		"--skill", "marketplace/demo/beta",
	)
	scenario.requireSuccess(removed)
	scenario.requireRegularFile(foreign)
	scenario.requireMissing(link)
	scenario.mkdirAll(link)
	scenario.writeFile(link+"/keep", "directory-content\n")
	neighbor := project + "/.agents/skills/neighbor"
	scenario.writeFile(neighbor, "neighbor\n")

	forced := scenario.run(project+"/nested", "skill", "add",
		"--local", "./marketplace",
		"--kind", "claude",
		"--skill", "demo/alpha",
		"--skill", "demo/beta",
		"--force",
	)
	scenario.requireSuccess(forced)
	scenario.requireOutput(forced, "Added "+repository+" to "+lockPath+": partial (1 notices, 0 unavailable repositories)\n")
	scenario.requireSymlink(foreign, plugin+"/skills/alpha")
	scenario.requireDirectory(link)
	scenario.requireFile(link+"/keep", "directory-content\n")
	scenario.requireFile(neighbor, "neighbor\n")
	state = string(scenario.readFile(statePath))
	scenario.requireContains(state, `"skill": "alpha"`)
	scenario.requireNotContains(state, `"skill": "beta"`)
}
