package cplugine2e

import (
	"testing"

	"github.com/totto2727-org/e2e/go/cli"
)

func TestCLI(t *testing.T) {
	const imageName = "c-plugin-e2e:local"
	t.Logf("image=%s", imageName)
	cli.Run(t, imageName, []cli.Case{
		{Name: "unified_help_hierarchy", Run: unifiedHelpHierarchyScenario},
		{Name: "separated_removal", Run: separatedRemovalScenario},
		{Name: "list_read_only", Run: listReadOnlyScenario},
		{Name: "list_missing_corrupt", Run: listMissingCorruptScenario},
		{Name: "github_list_unavailable", Run: githubListUnavailableScenario},
		{Name: "plugin_toggle", Run: pluginToggleScenario},
		{Name: "top_level_sync_update_recursive", Run: topLevelSyncUpdateRecursiveScenario},
		{Name: "github_parser_invalid", Run: githubParserInvalidScenario},
		{Name: "github_source_failure", Run: githubSourceFailureScenario},
		{Name: "github_plugin_lifecycle", Run: githubPluginLifecycleScenario},
		{Name: "github_standalone_offline", Run: githubStandaloneOfflineScenario},
		{Name: "github_global", Run: githubGlobalScenario},
		{Name: "github_cache_safety", Run: githubCacheSafetyScenario},
		{Name: "github_force_safety", Run: githubForceSafetyScenario},
		{Name: "error_help", Run: errorHelpScenario},
		{Name: "init_project", Run: initProjectScenario},
		{Name: "init_global", Run: initGlobalScenario},
		{Name: "sync", Run: syncScenario},
		{Name: "sync_recursive", Run: syncRecursiveScenario},
		{Name: "add", Run: addScenario},
		{Name: "remove", Run: removeScenario},
		{Name: "target_add", Run: targetAddScenario},
		{Name: "target_remove", Run: targetRemoveScenario},
		{Name: "interactive_selection", Run: interactiveSelectionScenario},
		{Name: "interactive_global", Run: interactiveGlobalScenario},
		{Name: "interactive_cancel", Run: interactiveCancelScenario},
		{Name: "interactive_empty", Run: interactiveEmptyScenario},
		{Name: "interactive_invalid", Run: interactiveInvalidScenario},
		{Name: "interactive_no_input", Run: interactiveNoInputScenario},
		{Name: "interactive_pipe", Run: interactivePipeScenario},
		{Name: "interactive_interrupt", Run: interactiveInterruptScenario},
		{Name: "interactive_eof", Run: interactiveEOFScenario},
		{Name: "standalone_lifecycle", Run: standaloneLifecycleScenario},
		{Name: "standalone_global", Run: standaloneGlobalScenario},
		{Name: "explicit_root", Run: explicitRootScenario},
		{Name: "standalone_duplicate", Run: standaloneDuplicateScenario},
		{Name: "standalone_unavailable", Run: standaloneUnavailableScenario},
		{Name: "standalone_invalid", Run: standaloneInvalidScenario},
		{Name: "standalone_escape", Run: standaloneEscapeScenario},
		{Name: "standalone_plugin_conflict", Run: standalonePluginConflictScenario},
		{Name: "plugin_enabled_set", Run: pluginEnabledSetScenario},
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
