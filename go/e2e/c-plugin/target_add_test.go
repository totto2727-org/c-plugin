package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/cli"
)

func targetAddScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	root := "/tmp/c-plugin-v2-target-add-e2e"
	home := root + "/home"
	project := home + "/project"
	projectPlugin := project + "/plugin"
	projectLock := project + "/c-plugin-lock.json"
	projectState := project + "/.agents/c-plugin-state.json"
	scenario := newScenarioEnvironment(t, environment, home)
	scenario.writePlugin(project, "alpha")
	scenario.writeFile(projectLock, localLock([]string{}, "plugin", []string{"alpha"}))

	projectResult := scenario.run(project, "skill", "target", "add", ".cursor/skills")
	scenario.requireSuccess(projectResult)
	scenario.requireContains(projectResult.Stdout, "Added target .cursor/skills to "+projectLock+": partial")
	scenario.requireJSON(projectLock, localLock([]string{".cursor/skills"}, "plugin", []string{"alpha"}))
	for _, targetRoot := range []string{project + "/.agents/skills", project + "/.cursor/skills"} {
		scenario.requireSymlink(targetRoot+"/alpha", projectPlugin+"/skills/alpha")
	}
	state := string(scenario.readFile(projectState))
	scenario.requireContains(state, `"managedRoot": "`+project+`/.agents/skills"`)
	scenario.requireContains(state, `"managedRoot": "`+project+`/.cursor/skills"`)
	lockDigest := scenario.digest(projectLock)
	stateDigest := scenario.digest(projectState)

	repeat := scenario.run(project, "skill", "target", "add", ".cursor/./skills")
	scenario.requireSuccess(repeat)
	scenario.requireOutput(repeat, "Target .cursor/skills already registered in "+projectLock+"\n")
	scenario.requireDigest(projectLock, lockDigest)
	scenario.requireDigest(projectState, stateDigest)

	globalRepository := home + "/plugin"
	globalPlugin := globalRepository
	globalLock := home + "/c-plugin-lock.json"
	globalState := home + "/.agents/c-plugin-state.json"
	scenario.writeFile(globalRepository+"/plugin.json", pluginJSON())
	scenario.writeFile(globalPlugin+"/skills/beta/SKILL.md", skillMarkdown("beta"))
	scenario.writeFile(globalLock, localLock([]string{}, "plugin", []string{"beta"}))
	scenario.mkdirAll(project + "/nested")

	global := scenario.run(project+"/nested", "skill", "target", "add", ".claude/skills", "--global")
	scenario.requireSuccess(global)
	scenario.requireContains(global.Stdout, "Added target .claude/skills to "+globalLock+": partial")
	for _, targetRoot := range []string{home + "/.agents/skills", home + "/.claude/skills"} {
		scenario.requireSymlink(targetRoot+"/beta", globalPlugin+"/skills/beta")
	}
	scenario.requireJSON(globalLock, localLock([]string{".claude/skills"}, "plugin", []string{"beta"}))
	scenario.requireContains(string(scenario.readFile(globalState)), `"managedRoot": "`+home+`/.claude/skills"`)
}
