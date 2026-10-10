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
		{Name: "standard_minimal", Run: standardMinimalScenario},
		{Name: "standard_empty", Run: standardEmptyScenario},
		{Name: "standard_unknown_field", Run: standardUnknownFieldScenario},
		{Name: "standard_wrong_schema", Run: standardWrongSchemaScenario},
		{Name: "standard_invalid_skill", Run: standardInvalidSkillScenario},
		{Name: "standard_shallow_discovery", Run: standardShallowDiscoveryScenario},
		{Name: "standard_manifest_escape", Run: standardManifestEscapeScenario},
		{Name: "standard_skills_escape", Run: standardSkillsEscapeScenario},
		{Name: "standard_skill_file_escape", Run: standardSkillFileEscapeScenario},
	})
}
