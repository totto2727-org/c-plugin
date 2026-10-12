package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/go/cli"
)

func TestCLI(t *testing.T) {
	const imageName = "c-plugin-e2e:local"
	t.Logf("image=%s", imageName)
	for _, scenario := range []struct {
		name string
		run  func(*testing.T, *cli.Environment)
	}{
		{name: "unified_help_hierarchy", run: unifiedHelpHierarchyScenario},
		{name: "separated_removal", run: separatedRemovalScenario},
		{name: "list_read_only", run: listReadOnlyScenario},
		{name: "list_missing_corrupt", run: listMissingCorruptScenario},
		{name: "github_list_unavailable", run: githubListUnavailableScenario},
		{name: "plugin_toggle", run: pluginToggleScenario},
		{name: "top_level_sync_update_recursive", run: topLevelSyncUpdateRecursiveScenario},
		{name: "github_parser_invalid", run: githubParserInvalidScenario},
		{name: "github_source_failure", run: githubSourceFailureScenario},
		{name: "github_plugin_lifecycle", run: githubPluginLifecycleScenario},
		{name: "github_standalone_offline", run: githubStandaloneOfflineScenario},
		{name: "github_global", run: githubGlobalScenario},
		{name: "github_cache_safety", run: githubCacheSafetyScenario},
		{name: "github_force_safety", run: githubForceSafetyScenario},
		{name: "error_help", run: errorHelpScenario},
		{name: "init_project", run: initProjectScenario},
		{name: "init_global", run: initGlobalScenario},
		{name: "sync", run: syncScenario},
		{name: "sync_recursive", run: syncRecursiveScenario},
		{name: "add", run: addScenario},
		{name: "remove", run: removeScenario},
		{name: "target_add", run: targetAddScenario},
		{name: "target_remove", run: targetRemoveScenario},
		{name: "interactive_selection", run: interactiveSelectionScenario},
		{name: "interactive_global", run: interactiveGlobalScenario},
		{name: "interactive_cancel", run: interactiveCancelScenario},
		{name: "interactive_empty", run: interactiveEmptyScenario},
		{name: "interactive_invalid", run: interactiveInvalidScenario},
		{name: "interactive_no_input", run: interactiveNoInputScenario},
		{name: "interactive_pipe", run: interactivePipeScenario},
		{name: "interactive_interrupt", run: interactiveInterruptScenario},
		{name: "interactive_eof", run: interactiveEOFScenario},
		{name: "standalone_lifecycle", run: standaloneLifecycleScenario},
		{name: "standalone_global", run: standaloneGlobalScenario},
		{name: "explicit_root", run: explicitRootScenario},
		{name: "standalone_duplicate", run: standaloneDuplicateScenario},
		{name: "standalone_unavailable", run: standaloneUnavailableScenario},
		{name: "standalone_invalid", run: standaloneInvalidScenario},
		{name: "standalone_escape", run: standaloneEscapeScenario},
		{name: "standalone_plugin_conflict", run: standalonePluginConflictScenario},
		{name: "plugin_enabled_set", run: pluginEnabledSetScenario},
		{name: "standard_minimal", run: standardMinimalScenario},
		{name: "standard_empty", run: standardEmptyScenario},
		{name: "standard_unknown_field", run: standardUnknownFieldScenario},
		{name: "standard_wrong_schema", run: standardWrongSchemaScenario},
		{name: "standard_invalid_skill", run: standardInvalidSkillScenario},
		{name: "standard_shallow_discovery", run: standardShallowDiscoveryScenario},
		{name: "standard_manifest_escape", run: standardManifestEscapeScenario},
		{name: "standard_skills_escape", run: standardSkillsEscapeScenario},
		{name: "standard_skill_file_escape", run: standardSkillFileEscapeScenario},
	} {
		t.Run(scenario.name, func(t *testing.T) {
			t.Parallel()
			environment := cli.NewEnvironment(t, imageName)
			scenario.run(t, environment)
		})
	}
}
