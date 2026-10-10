package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/cli"
)

func standardEnvironment(t *testing.T, environment *cli.Environment, name string, skills ...string) (*scenarioEnvironment, string) {
	t.Helper()
	home := "/tmp/c-plugin-standard-" + name + "/home"
	project := home + "/project"
	s := newScenarioEnvironment(t, environment, home)
	s.writePlugin(project, skills...)
	s.requireSuccess(s.run(project, "init"))
	return s, project
}

func standardMinimalScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "minimal", "alpha", "beta")
	result := s.run(project, "skill", "add", "--local", "./plugin")
	s.requireSuccess(result)
	s.requireContains(result.Stdout, "Added "+project+"/plugin to "+project+"/c-plugin-lock.json: partial")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"alpha", "beta"}))
	for _, skill := range []string{"alpha", "beta"} {
		s.requireSymlink(project+"/.agents/skills/"+skill, project+"/plugin/skills/"+skill)
		s.requireContains(string(s.readFile(project+"/.agents/c-plugin-state.json")), `"skill": "`+skill+`"`)
	}
	removed := s.run(project, "skill", "remove", "--plugin", "demo")
	s.requireSuccess(removed)
	s.requireContains(removed.Stdout, "Removed plugins demo from "+project+"/c-plugin-lock.json:")
	s.requireJSON(project+"/c-plugin-lock.json", emptyLock)
	s.requireMissing(project + "/.agents/skills/alpha")
	s.requireMissing(project + "/.agents/skills/beta")
	s.requireJSON(project+"/.agents/c-plugin-state.json", `{"version":"1","entries":[]}`)
}

func standardEmptyScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "empty")
	result := s.run(project, "skill", "add", "--local", "./plugin")
	s.requireSuccess(result)
	s.requireContains(result.Stdout, "Added "+project+"/plugin")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{}))
	s.requireJSON(project+"/.agents/c-plugin-state.json", `{"version":"1","entries":[]}`)
	s.requireMissing(project + "/.agents/skills/alpha")
	s.requireMissing(project + "/.agents/skills/beta")
}

func standardUnknownFieldScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "unknown", "alpha")
	s.writeFile(project+"/plugin/plugin.json", `{"$schema":"`+pluginSchema+`","name":"demo","skills":"./elsewhere","custom":true}`)
	s.writeFile(project+"/plugin/elsewhere/beta/SKILL.md", skillMarkdown("beta"))
	result := s.run(project, "skill", "add", "--local", "./plugin")
	s.requireSuccess(result)
	s.requireContains(result.Stdout, "Warning: unknown top-level field: skills")
	s.requireContains(result.Stdout, "Warning: unknown top-level field: custom")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"alpha"}))
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
	s.requireMissing(project + "/.agents/skills/beta")
}

func standardWrongSchemaScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "wrong-schema", "alpha")
	s.writeFile(project+"/plugin/plugin.json", `{"$schema":"https://example.invalid/plugin.schema.json","name":"demo"}`)
	s.writeFile(project+"/.agents/skills/foreign", "foreign\n")
	before := s.digest(project + "/c-plugin-lock.json")
	result := s.run(project, "skill", "add", "--local", "./plugin")
	s.requireFailure(result)
	s.requireContains(result.Stdout, "totto2727/c-plugin.AddLocalError.InvalidInput")
	s.requireDigest(project+"/c-plugin-lock.json", before)
	s.requireMissing(project + "/.agents/c-plugin-state.json")
	s.requireMissing(project + "/.agents/skills/alpha")
	s.requireFile(project+"/.agents/skills/foreign", "foreign\n")
}

func standardInvalidSkillScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "invalid-skill", "alpha")
	s.writeFile(project+"/plugin/skills/beta/SKILL.md", "---\nname: beta\n---\n")
	result := s.run(project, "skill", "add", "--local", "./plugin")
	s.requireSuccess(result)
	s.requireContains(result.Stdout, "Warning: invalid skill beta:")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"alpha"}))
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
	s.requireMissing(project + "/.agents/skills/beta")
	s.requireNotContains(string(s.readFile(project+"/.agents/c-plugin-state.json")), `"skill": "beta"`)
}

func standardShallowDiscoveryScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "shallow", "alpha")
	s.writeFile(project+"/plugin/skills/group/beta/SKILL.md", skillMarkdown("beta"))
	result := s.run(project, "skill", "add", "--local", "./plugin")
	s.requireSuccess(result)
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"alpha"}))
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
	s.requireMissing(project + "/.agents/skills/beta")
	s.requireMissing(project + "/.agents/skills/group")
}

func standardManifestEscapeScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "manifest-escape", "alpha")
	outside := project + "/outside/plugin.json"
	s.writeFile(outside, pluginJSON())
	outsideDigest := s.digest(outside)
	s.remove(project + "/plugin/plugin.json")
	s.requireSuccess(s.runInfrastructure("", "ln", "-s", outside, project+"/plugin/plugin.json"))
	s.writeFile(project+"/.agents/skills/foreign", "foreign\n")
	before := s.digest(project + "/c-plugin-lock.json")
	result := s.run(project, "skill", "add", "--local", "./plugin")
	s.requireFailure(result)
	s.requireContains(result.Stdout, "outside plugin root")
	s.requireDigest(project+"/c-plugin-lock.json", before)
	s.requireDigest(outside, outsideDigest)
	s.requireMissing(project + "/.agents/c-plugin-state.json")
	s.requireMissing(project + "/.agents/skills/alpha")
	s.requireFile(project+"/.agents/skills/foreign", "foreign\n")
}

func standardSkillsEscapeScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "skills-escape")
	outside := project + "/outside/alpha/SKILL.md"
	s.writeFile(outside, skillMarkdown("alpha"))
	outsideDigest := s.digest(outside)
	s.requireSuccess(s.runInfrastructure("", "ln", "-s", project+"/outside", project+"/plugin/skills"))
	result := s.run(project, "skill", "add", "--local", "./plugin")
	s.requireSuccess(result)
	s.requireContains(result.Stdout, "outside plugin root")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{}))
	s.requireJSON(project+"/.agents/c-plugin-state.json", `{"version":"1","entries":[]}`)
	s.requireMissing(project + "/.agents/skills/alpha")
	s.requireDigest(outside, outsideDigest)
}

func standardSkillFileEscapeScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "skill-file-escape", "alpha")
	outside := project + "/outside/SKILL.md"
	s.writeFile(outside, skillMarkdown("beta"))
	outsideDigest := s.digest(outside)
	s.mkdirAll(project + "/plugin/skills/beta")
	s.requireSuccess(s.runInfrastructure("", "ln", "-s", outside, project+"/plugin/skills/beta/SKILL.md"))
	result := s.run(project, "skill", "add", "--local", "./plugin")
	s.requireSuccess(result)
	s.requireContains(result.Stdout, "Warning: invalid skill beta:")
	s.requireContains(result.Stdout, "outside plugin root")
	s.requireJSON(project+"/c-plugin-lock.json", localLock([]string{}, "plugin", []string{"alpha"}))
	s.requireSymlink(project+"/.agents/skills/alpha", project+"/plugin/skills/alpha")
	s.requireMissing(project + "/.agents/skills/beta")
	s.requireDigest(outside, outsideDigest)
}
