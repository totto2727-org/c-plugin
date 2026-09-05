package cplugine2e

import (
	"strings"
	"testing"

	"github.com/totto2727-org/e2e/cli"
)

func syncRecursiveScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	root := "/tmp/c-plugin-v2-sync-recursive-e2e"
	home := root + "/home"
	project := home + "/project"
	child := project + "/child"
	ignored := project + "/ignored"
	scenario := newScenarioEnvironment(t, environment, home)
	scenario.writeMarketplace(project, "alpha")
	scenario.writeMarketplace(child, "beta")
	scenario.writeFile(project+"/c-plugin-lock.json", localLock([]string{}, "marketplace", []string{"alpha"}))
	scenario.writeFile(child+"/c-plugin-lock.json", localLock([]string{}, "marketplace", []string{"beta"}))
	scenario.writeFile(project+"/.gitignore", "ignored/\n")
	scenario.writeFile(ignored+"/c-plugin-lock.json", "{invalid\n")
	scenario.writeFile(project+"/.agents/skills/foreign", "foreign\n")
	parentDigest := scenario.digest(project + "/c-plugin-lock.json")
	childDigest := scenario.digest(child + "/c-plugin-lock.json")

	initial := scenario.run(project, "skill", "sync", "-r")
	scenario.requireSuccess(initial)
	if count := strings.Count(initial.Stdout, "Synced "); count != 2 {
		t.Fatalf("synced_count=%d output=%q", count, initial.Stdout)
	}
	scenario.requireContains(initial.Stdout, "Synced "+project+"/c-plugin-lock.json:")
	scenario.requireContains(initial.Stdout, "Synced "+child+"/c-plugin-lock.json:")
	scenario.requireNotContains(initial.Stdout, ignored+"/c-plugin-lock.json")
	scenario.requireSymlink(project+"/.agents/skills/alpha", project+"/marketplace/plugins/demo/skills/alpha")
	scenario.requireSymlink(child+"/.agents/skills/beta", child+"/marketplace/plugins/demo/skills/beta")
	if !scenario.pathExists(project+"/.agents/c-plugin-state.json") || !scenario.pathExists(child+"/.agents/c-plugin-state.json") {
		t.Fatal("expected parent and child ownership state")
	}
	scenario.requireFile(project+"/.agents/skills/foreign", "foreign\n")
	scenario.requireDigest(project+"/c-plugin-lock.json", parentDigest)
	scenario.requireDigest(child+"/c-plugin-lock.json", childDigest)

	scenario.writeFile(project+"/c-plugin-lock.json", localLock([]string{}, "marketplace", []string{}))
	editedParentDigest := scenario.digest(project + "/c-plugin-lock.json")
	edited := scenario.run(project, "skill", "sync", "--recursive")
	scenario.requireSuccess(edited)
	if count := strings.Count(edited.Stdout, "Synced "); count != 2 {
		t.Fatalf("synced_count=%d output=%q", count, edited.Stdout)
	}
	scenario.requireMissing(project + "/.agents/skills/alpha")
	scenario.requireSymlink(child+"/.agents/skills/beta", child+"/marketplace/plugins/demo/skills/beta")
	scenario.requireContains(string(scenario.readFile(child+"/.agents/c-plugin-state.json")), `"skill": "beta"`)
	scenario.requireFile(project+"/.agents/skills/foreign", "foreign\n")
	scenario.requireDigest(project+"/c-plugin-lock.json", editedParentDigest)
	scenario.requireDigest(child+"/c-plugin-lock.json", childDigest)

	invalid := scenario.run(project, "skill", "sync", "-g", "-r")
	scenario.requireFailure(invalid)
	scenario.requireContains(invalid.Stdout, "totto2727/c-plugin.SyncError.Planning")
}
