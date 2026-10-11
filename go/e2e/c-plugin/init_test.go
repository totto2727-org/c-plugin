package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/cli"
)

func initProjectScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	runInitWorkflow(t, environment, false)
}

func initGlobalScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	runInitWorkflow(t, environment, true)
}

func runInitWorkflow(t *testing.T, environment *cli.Environment, global bool) {
	t.Helper()
	root := "/tmp/c-plugin-v2-init-e2e"
	home := root + "/home"
	project := root + "/totto2727-org/monorepo"
	scenario := newScenarioEnvironment(t, environment, home)
	scenario.mkdirAll(home, project)

	lockPath := project + "/c-plugin-lock.json"
	oppositeLock := home + "/c-plugin-lock.json"
	initialArguments := []string{"init"}
	repeatArguments := []string{"init"}
	if global {
		lockPath, oppositeLock = oppositeLock, lockPath
		initialArguments = append(initialArguments, "-g")
		repeatArguments = append(repeatArguments, "--global")
	}

	initial := scenario.run(project, initialArguments...)
	scenario.requireSuccess(initial)
	scenario.requireOutput(initial, "Created "+lockPath+"\n")
	scenario.requireJSON(lockPath, emptyLock)
	scenario.requireMissing(oppositeLock)
	originalDigest := scenario.digest(lockPath)

	repeat := scenario.run(project, repeatArguments...)
	scenario.requireFailure(repeat)
	scenario.requireContains(repeat.Stdout, "totto2727/c-plugin.StateStoreError.AlreadyExists")
	scenario.requireDigest(lockPath, originalDigest)
	scenario.requireMissing(oppositeLock)
	scenario.requireMissing(project + "/.agents")
	scenario.requireMissing(home + "/.agents")
	scenario.requireMissing(home + "/.cache/c-plugin")
}
