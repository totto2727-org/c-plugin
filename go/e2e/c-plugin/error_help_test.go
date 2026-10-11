package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/go/cli"
)

func errorHelpScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	root := "/tmp/c-plugin-error-help-e2e"
	home := root + "/home"
	project := home + "/project"
	scenario := newScenarioEnvironment(t, environment, home)
	scenario.mkdirAll(home, project)
	scenario.requireSuccess(scenario.run(project, "init"))
	lock := project + "/c-plugin-lock.json"
	before := scenario.digest(lock)

	cases := []struct {
		name      string
		arguments []string
		context   []string
		errorText string
	}{
		{name: "root command", errorText: "Missing: COMMAND"},
		{name: "plugin command", arguments: []string{"plugin"}, context: []string{"plugin"}, errorText: "Missing: COMMAND"},
		{name: "skill command", arguments: []string{"skill"}, context: []string{"skill"}, errorText: "Missing: COMMAND"},
		{name: "target command", arguments: []string{"skill", "target"}, context: []string{"skill", "target"}, errorText: "Missing: COMMAND"},
		{name: "plugin source option", arguments: []string{"plugin", "add"}, context: []string{"plugin", "add"}, errorText: "Missing:"},
		{name: "standalone source option", arguments: []string{"skill", "add"}, context: []string{"skill", "add"}, errorText: "Missing:"},
		{name: "target argument", arguments: []string{"skill", "target", "add"}, context: []string{"skill", "target", "add"}, errorText: "Missing: PATH"},
		{name: "ref option value", arguments: []string{"plugin", "add", "github:owner/repo", "--ref"}, context: []string{"plugin", "add"}, errorText: "The option `--ref` expects an argument."},
		{name: "skill option value", arguments: []string{"plugin", "add", "local:./plugin", "--skill"}, context: []string{"plugin", "add"}, errorText: "The option `--skill` expects an argument."},
	}
	for _, test := range cases {
		t.Logf("checking %s", test.name)
		help := scenario.run(project, append(test.context, "--help")...)
		scenario.requireSuccess(help)
		scenario.requireContains(help.Stdout, "Available options:")
		failure := scenario.run(project, test.arguments...)
		scenario.requireExit(failure, 1)
		scenario.requireContains(failure.Stderr, test.errorText)
		scenario.requireContains(failure.Stderr, help.Stdout)
		scenario.requireDigest(lock, before)
	}
	scenario.requireMissing(home + "/c-plugin-lock.json")
	scenario.requireMissing(project + "/.agents")
	scenario.requireMissing(home + "/.agents")
}
