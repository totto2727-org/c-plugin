package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/cli"
)

func removeScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	root := "/tmp/c-plugin-v2-remove-e2e"
	home := root + "/home"
	project := home + "/project"
	lockPath := project + "/c-plugin-lock.json"
	statePath := project + "/.agents/c-plugin-state.json"
	skillsRoot := project + "/.agents/skills"
	scenario := newScenarioEnvironment(t, environment, home)
	scenario.writePlugin(project, "alpha", "beta")
	scenario.writeFile(lockPath, localLock([]string{}, "plugin", []string{"alpha", "beta"}))
	scenario.requireSuccess(scenario.run(project, "skill", "sync"))
	scenario.remove(skillsRoot + "/alpha")
	scenario.writeFile(skillsRoot+"/alpha", "replacement\n")
	scenario.writeFile(skillsRoot+"/neighbor", "foreign\n")
	lockDigest := scenario.digest(lockPath)
	stateDigest := scenario.digest(statePath)

	empty := scenario.run(project, "skill", "remove")
	scenario.requireSuccess(empty)
	scenario.requireOutput(empty, "No skill changes for "+lockPath+"\n")
	unknown := scenario.run(project, "skill", "remove", "--skill", "demo/unknown")
	scenario.requireSuccess(unknown)
	scenario.requireOutput(unknown, "No skill changes for "+lockPath+"\n")
	scenario.requireDigest(lockPath, lockDigest)
	scenario.requireDigest(statePath, stateDigest)

	alpha := scenario.run(project, "skill", "remove", "--skill", "demo/./alpha")
	scenario.requireSuccess(alpha)
	scenario.requireContains(alpha.Stdout, "Removed skills demo/alpha from "+lockPath+": partial")
	scenario.requireJSON(lockPath, localLock([]string{}, "plugin", []string{"beta"}))
	scenario.requireFile(skillsRoot+"/alpha", "replacement\n")
	scenario.requireFile(skillsRoot+"/neighbor", "foreign\n")
	scenario.requireSymlink(skillsRoot+"/beta", project+"/plugin/skills/beta")
	state := string(scenario.readFile(statePath))
	scenario.requireNotContains(state, `"skill": "alpha"`)
	scenario.requireContains(state, `"skill": "beta"`)
	lockDigest = scenario.digest(lockPath)
	stateDigest = scenario.digest(statePath)

	repeat := scenario.run(project, "skill", "remove", "--skill", "demo/alpha")
	scenario.requireSuccess(repeat)
	scenario.requireOutput(repeat, "No skill changes for "+lockPath+"\n")
	scenario.requireDigest(lockPath, lockDigest)
	scenario.requireDigest(statePath, stateDigest)

	beta := scenario.run(project, "skill", "remove", "--skill", "demo/beta")
	scenario.requireSuccess(beta)
	scenario.requireContains(beta.Stdout, "Removed skills demo/beta from "+lockPath+": complete")
	scenario.requireJSON(lockPath, emptyLock)
	scenario.requireMissing(skillsRoot + "/beta")
	scenario.requireFile(skillsRoot+"/alpha", "replacement\n")
	scenario.requireFile(skillsRoot+"/neighbor", "foreign\n")

	globalRepository := home + "/plugin"
	globalLock := home + "/c-plugin-lock.json"
	globalState := home + "/.agents/c-plugin-state.json"
	scenario.writeFile(globalRepository+"/plugin.json", pluginJSON())
	scenario.writeFile(globalRepository+"/skills/gamma/SKILL.md", skillMarkdown("gamma"))
	scenario.writeFile(globalLock, localLock([]string{}, "plugin", []string{"gamma"}))
	scenario.mkdirAll(project + "/nested")
	scenario.requireSuccess(scenario.run(project+"/nested", "skill", "sync", "--global"))
	global := scenario.run(project+"/nested", "skill", "remove", "--global", "--skill", "demo/gamma")
	scenario.requireSuccess(global)
	scenario.requireContains(global.Stdout, "Removed skills demo/gamma from "+globalLock+": complete")
	scenario.requireJSON(globalLock, emptyLock)
	scenario.requireMissing(home + "/.agents/skills/gamma")
	scenario.requireNotContains(string(scenario.readFile(globalState)), `"skill": "gamma"`)
}
