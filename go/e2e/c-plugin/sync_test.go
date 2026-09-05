package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/cli"
)

func syncScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	root := "/tmp/c-plugin-v2-sync-e2e"
	home := root + "/home"
	project := home + "/project"
	repository := project + "/marketplace"
	plugin := repository + "/plugins/demo"
	lockPath := project + "/c-plugin-lock.json"
	statePath := project + "/.agents/c-plugin-state.json"
	scenario := newScenarioEnvironment(t, environment, home)
	scenario.writeMarketplaceSkills(project, "alpha", "beta")
	scenario.writeFile(lockPath, localLock([]string{".cursor/skills"}, "marketplace", []string{"alpha", "beta"}))
	initialDigest := scenario.digest(lockPath)

	initial := scenario.run(project, "skill", "sync")
	scenario.requireSuccess(initial)
	scenario.requireContains(initial.Stdout, "Synced "+lockPath+": partial (1 notices, 0 unavailable repositories)")
	scenario.requireDigest(lockPath, initialDigest)
	for _, targetRoot := range []string{project + "/.agents/skills", project + "/.cursor/skills"} {
		for _, skill := range []string{"alpha", "beta"} {
			scenario.requireSymlink(targetRoot+"/"+skill, plugin+"/skills/"+skill)
		}
	}
	state := string(scenario.readFile(statePath))
	scenario.requireContains(state, `"skill": "alpha"`)
	scenario.requireContains(state, `"skill": "beta"`)

	primaryRoot := project + "/.agents/skills"
	scenario.remove(primaryRoot + "/beta")
	scenario.writeFile(primaryRoot+"/beta", "foreign\n")
	scenario.writeFile(primaryRoot+"/neighbor", "neighbor\n")
	scenario.writeFile(lockPath, localLock([]string{".cursor/skills"}, "marketplace", []string{}))
	editedDigest := scenario.digest(lockPath)

	edited := scenario.run(project, "skill", "sync")
	scenario.requireSuccess(edited)
	scenario.requireContains(edited.Stdout, "Synced "+lockPath+": partial (1 notices, 0 unavailable repositories)")
	scenario.requireDigest(lockPath, editedDigest)
	scenario.requireMissing(primaryRoot + "/alpha")
	scenario.requireMissing(project + "/.cursor/skills/alpha")
	scenario.requireMissing(project + "/.cursor/skills/beta")
	scenario.requireRegularFile(primaryRoot + "/beta")
	scenario.requireFile(primaryRoot+"/beta", "foreign\n")
	scenario.requireFile(primaryRoot+"/neighbor", "neighbor\n")
	scenario.requireJSON(statePath, `{"version":"1","entries":[]}`)
}
