package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/cli"
)

func TestCLI(t *testing.T) {
	const imageName = "c-plugin-e2e:local"
	t.Logf("image=%s", imageName)
	cli.Run(t, imageName, []cli.Case{
		{Name: "init_project", Run: initProjectScenario},
		{Name: "init_global", Run: initGlobalScenario},
		{Name: "sync", Run: syncScenario},
		{Name: "sync_recursive", Run: syncRecursiveScenario},
		{Name: "add", Run: addScenario},
		{Name: "remove", Run: removeScenario},
		{Name: "target_add", Run: targetAddScenario},
		{Name: "target_remove", Run: targetRemoveScenario},
	})
}
