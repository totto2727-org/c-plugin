package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/cli"
)

func targetRemoveScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	root := "/tmp/c-plugin-v2-target-remove-e2e"
	home := root + "/home"
	project := home + "/project"
	projectPlugin := project + "/plugin"
	projectLock := project + "/c-plugin-lock.json"
	projectState := project + "/.agents/c-plugin-state.json"
	scenario := newScenarioEnvironment(t, environment, home)
	scenario.writePlugin(project, "alpha")
	scenario.writeFile(projectLock, localLock([]string{".cursor/skills", ".claude/skills"}, "plugin", []string{"alpha"}))
	scenario.requireSuccess(scenario.run(project, "skill", "sync"))
	scenario.writeFile(project+"/.cursor/skills/neighbor", "foreign\n")
	lockDigest := scenario.digest(projectLock)
	stateDigest := scenario.digest(projectState)

	unknown := scenario.run(project, "skill", "target", "remove", "--target", ".vscode/skills")
	scenario.requireSuccess(unknown)
	scenario.requireOutput(unknown, "No target changes for "+projectLock+"\n")
	empty := scenario.run(project, "skill", "target", "remove")
	scenario.requireSuccess(empty)
	scenario.requireOutput(empty, "No target changes for "+projectLock+"\n")
	scenario.requireDigest(projectLock, lockDigest)
	scenario.requireDigest(projectState, stateDigest)

	cursor := scenario.run(project, "skill", "target", "remove", "--target", ".cursor/./skills")
	scenario.requireSuccess(cursor)
	scenario.requireContains(cursor.Stdout, "Removed targets .cursor/skills from "+projectLock+": complete")
	scenario.requireJSON(projectLock, localLock([]string{".claude/skills"}, "plugin", []string{"alpha"}))
	scenario.requireMissing(project + "/.cursor/skills/alpha")
	scenario.requireFile(project+"/.cursor/skills/neighbor", "foreign\n")
	for _, targetRoot := range []string{project + "/.agents/skills", project + "/.claude/skills"} {
		scenario.requireSymlink(targetRoot+"/alpha", projectPlugin+"/skills/alpha")
	}
	state := string(scenario.readFile(projectState))
	scenario.requireNotContains(state, `"managedRoot": "`+project+`/.cursor/skills"`)
	scenario.requireContains(state, `"managedRoot": "`+project+`/.claude/skills"`)

	claude := scenario.run(project, "skill", "target", "remove", "--target", ".claude/skills")
	scenario.requireSuccess(claude)
	scenario.requireContains(claude.Stdout, "Removed targets .claude/skills from "+projectLock+": complete")
	scenario.requireJSON(projectLock, localLock([]string{}, "plugin", []string{"alpha"}))
	scenario.requireMissing(project + "/.claude/skills/alpha")
	scenario.requireSymlink(project+"/.agents/skills/alpha", projectPlugin+"/skills/alpha")
	scenario.requireFile(project+"/.cursor/skills/neighbor", "foreign\n")
	state = string(scenario.readFile(projectState))
	scenario.requireNotContains(state, project+"/.cursor/skills")
	scenario.requireNotContains(state, project+"/.claude/skills")

	globalRepository := home + "/plugin"
	globalPlugin := globalRepository
	globalLock := home + "/c-plugin-lock.json"
	globalState := home + "/.agents/c-plugin-state.json"
	scenario.writeFile(globalRepository+"/plugin.json", pluginJSON())
	scenario.writeFile(globalPlugin+"/skills/beta/SKILL.md", skillMarkdown("beta"))
	scenario.writeFile(globalLock, localLock([]string{".cursor/skills"}, "plugin", []string{"beta"}))
	scenario.mkdirAll(project + "/nested")
	scenario.requireSuccess(scenario.run(project+"/nested", "skill", "sync", "--global"))
	global := scenario.run(project+"/nested", "skill", "target", "remove", "--global", "--target", ".cursor/skills")
	scenario.requireSuccess(global)
	scenario.requireContains(global.Stdout, "Removed targets .cursor/skills from "+globalLock+": complete")
	scenario.requireJSON(globalLock, localLock([]string{}, "plugin", []string{"beta"}))
	scenario.requireMissing(home + "/.cursor/skills/beta")
	scenario.requireSymlink(home+"/.agents/skills/beta", globalPlugin+"/skills/beta")
	scenario.requireNotContains(string(scenario.readFile(globalState)), home+"/.cursor/skills")
}
