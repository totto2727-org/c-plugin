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
	scenario.writeMarketplaceSkills(project, "alpha", "beta")
	scenario.writeFile(lockPath, localLock([]string{}, "marketplace", []string{"alpha", "beta"}))
	scenario.requireSuccess(scenario.run(project, "skill", "sync"))
	scenario.remove(skillsRoot + "/alpha")
	scenario.writeFile(skillsRoot+"/alpha", "replacement\n")
	scenario.writeFile(skillsRoot+"/neighbor", "foreign\n")
	lockDigest := scenario.digest(lockPath)
	stateDigest := scenario.digest(statePath)

	empty := scenario.run(project, "skill", "remove")
	scenario.requireSuccess(empty)
	scenario.requireOutput(empty, "No skill changes for "+lockPath+"\n")
	unknown := scenario.run(project, "skill", "remove", "--skill", "marketplace/demo/unknown")
	scenario.requireSuccess(unknown)
	scenario.requireOutput(unknown, "No skill changes for "+lockPath+"\n")
	scenario.requireDigest(lockPath, lockDigest)
	scenario.requireDigest(statePath, stateDigest)

	alpha := scenario.run(project, "skill", "remove", "--skill", "marketplace/./demo/alpha")
	scenario.requireSuccess(alpha)
	scenario.requireOutput(alpha, "Removed skills marketplace/demo/alpha from "+lockPath+": partial (1 notices, 0 unavailable repositories)\n")
	scenario.requireJSON(lockPath, localLock([]string{}, "marketplace", []string{"beta"}))
	scenario.requireFile(skillsRoot+"/alpha", "replacement\n")
	scenario.requireFile(skillsRoot+"/neighbor", "foreign\n")
	scenario.requireSymlink(skillsRoot+"/beta", project+"/marketplace/plugins/demo/skills/beta")
	state := string(scenario.readFile(statePath))
	scenario.requireNotContains(state, `"skill": "alpha"`)
	scenario.requireContains(state, `"skill": "beta"`)
	lockDigest = scenario.digest(lockPath)
	stateDigest = scenario.digest(statePath)

	repeat := scenario.run(project, "skill", "remove", "--skill", "marketplace/demo/alpha")
	scenario.requireSuccess(repeat)
	scenario.requireOutput(repeat, "No skill changes for "+lockPath+"\n")
	scenario.requireDigest(lockPath, lockDigest)
	scenario.requireDigest(statePath, stateDigest)

	beta := scenario.run(project, "skill", "remove", "--skill", "marketplace/demo/beta")
	scenario.requireSuccess(beta)
	scenario.requireOutput(beta, "Removed skills marketplace/demo/beta from "+lockPath+": complete (0 notices, 0 unavailable repositories)\n")
	scenario.requireJSON(lockPath, emptyLock)
	scenario.requireMissing(skillsRoot + "/beta")
	scenario.requireFile(skillsRoot+"/alpha", "replacement\n")
	scenario.requireFile(skillsRoot+"/neighbor", "foreign\n")

	globalRepository := home + "/global-marketplace"
	globalLock := home + "/c-plugin-lock.json"
	globalState := home + "/.agents/c-plugin-state.json"
	scenario.writeFile(globalRepository+"/.claude-plugin/marketplace.json", marketplaceJSON())
	scenario.writeFile(globalRepository+"/plugins/demo/skills/gamma/SKILL.md", "# gamma\n")
	scenario.writeFile(globalLock, localLock([]string{}, "global-marketplace", []string{"gamma"}))
	scenario.mkdirAll(project + "/nested")
	scenario.requireSuccess(scenario.run(project+"/nested", "skill", "sync", "--global"))
	global := scenario.run(project+"/nested", "skill", "remove", "--global", "--skill", "global-marketplace/demo/gamma")
	scenario.requireSuccess(global)
	scenario.requireOutput(global, "Removed skills global-marketplace/demo/gamma from "+globalLock+": complete (0 notices, 0 unavailable repositories)\n")
	scenario.requireJSON(globalLock, emptyLock)
	scenario.requireMissing(home + "/.agents/skills/gamma")
	scenario.requireNotContains(string(scenario.readFile(globalState)), `"skill": "gamma"`)
}
