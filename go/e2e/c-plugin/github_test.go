package cplugine2e

import (
	"encoding/json"
	"path"
	"regexp"
	"strings"
	"testing"

	"github.com/totto2727-org/e2e/go/cli"
)

const (
	githubFixtureRepository = "totto2727-org/c-plugin"
	githubFixtureURL        = "https://github.com/" + githubFixtureRepository
	githubFixtureRef        = "test/e2e-unified-api"
	githubPluginPath        = "hs/test/fixtures/github/plugin"
	githubSoloPath          = "hs/test/fixtures/github/solo"
	githubRootSource        = "github:" + githubFixtureRepository
	githubPluginSource      = githubRootSource + "/" + githubPluginPath
	githubSoloSource        = githubRootSource + "/" + githubSoloPath
	githubPluginURLSource   = "github:" + githubFixtureURL + "/" + githubPluginPath
	githubSoloURLSource     = "github:" + githubFixtureURL + "/" + githubSoloPath
)

func githubEnvironment(t *testing.T, environment *cli.Environment, name string) (*scenarioEnvironment, string) {
	t.Helper()
	home := "/tmp/c-plugin-github-" + name + "/home"
	project := home + "/project"
	s := newScenarioEnvironment(t, environment, home)
	s.mkdirAll(project)
	s.requireSuccess(s.run(project, "init"))
	return s, project
}

// Decode only the public lock fields used by these scenarios, without imposing
// an unrelated whole-lock representation on the existing runner.
type githubRegistration struct {
	Name   string          `json:"pluginName"`
	Source string          `json:"pluginSource"`
	Skills []string        `json:"enabledSkills"`
	Origin json.RawMessage `json:"pluginOrigin"`
}

func githubRegisteredSource(s *scenarioEnvironment, root string, kind string, name string) githubRegistration {
	s.t.Helper()
	var lock struct {
		Plugins map[string]githubRegistration `json:"plugins"`
		Skills  map[string]struct {
			Name   string          `json:"installedSkillName"`
			Source string          `json:"installedSkillSource"`
			Origin json.RawMessage `json:"installedSkillOrigin"`
		} `json:"standaloneSkills"`
	}
	if err := json.Unmarshal(s.readFile(root+"/c-plugin-lock.json"), &lock); err != nil {
		s.t.Fatal(err)
	}
	entries := lock.Plugins
	if kind == "skill" {
		entries = make(map[string]githubRegistration, len(lock.Skills))
		for key, skill := range lock.Skills {
			entries[key] = githubRegistration{Name: skill.Name, Source: skill.Source, Origin: skill.Origin}
		}
	}
	entry, exists := entries[name]
	if len(entries) != 1 || !exists || entry.Name != name {
		s.t.Fatalf("%s registrations=%+v want exactly %s", kind, entries, name)
	}
	if !strings.HasPrefix(entry.Source, ".agents/c-plugin/sources/") || path.Clean(entry.Source) != entry.Source || strings.Contains(entry.Source, "..") {
		s.t.Fatalf("GitHub source is not a contained relative snapshot: %q", entry.Source)
	}
	s.requireDirectory(path.Join(root, entry.Source))
	return entry
}

func githubPinnedCommit(s *scenarioEnvironment, entry githubRegistration) string {
	s.t.Helper()
	var origin struct {
		Repository string `json:"githubOriginRepository"`
		Ref        string `json:"githubOriginRef"`
		Commit     string `json:"githubOriginCommit"`
		Subpath    string `json:"githubOriginSubpath"`
	}
	if err := json.Unmarshal(entry.Origin, &origin); err != nil {
		s.t.Fatalf("decode GitHub origin %s: %v", entry.Origin, err)
	}
	if origin.Repository != githubFixtureRepository || origin.Ref == "" {
		s.t.Fatalf("GitHub origin identity=%s", entry.Origin)
	}
	if !regexp.MustCompile(`^[0-9a-f]{40}$`).MatchString(origin.Commit) {
		s.t.Fatalf("GitHub origin commit=%q is not an immutable SHA-1", origin.Commit)
	}
	expected := ".agents/c-plugin/sources/" + origin.Repository + "/" + origin.Commit + "/tree/" + origin.Subpath
	if entry.Source != expected {
		s.t.Fatalf("GitHub source=%q want=%q", entry.Source, expected)
	}
	return origin.Commit
}

func githubParserInvalidScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := githubEnvironment(t, environment, "parser-invalid")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	for _, arguments := range [][]string{
		{"plugin", "add", "--github", githubFixtureRepository, "--all"},
		{"skill", "add", "--local", "./solo"},
		{"plugin", "add", githubPluginSource, "--path", githubPluginPath, "--all"},
		{"plugin", "add", githubPluginSource, "--local", "./plugin", "--all"},
		{"skill", "add", githubSoloSource, "--local", "./solo"},
		{"plugin", "add", githubPluginSource, "local:./plugin", "--all"},
		{"skill", "add", githubSoloSource, "local:./solo"},
		{"plugin", "add", "local:./plugin", "--ref", githubFixtureRef, "--all"},
		{"skill", "add", "local:./solo", "--path", githubSoloPath},
		{"plugin", "add", "--ref", githubFixtureRef, "--all"},
		{"skill", "add", "--ref", githubFixtureRef},
		{"plugin", "add", githubFixtureRepository, "--all"},
		{"skill", "add", githubFixtureURL},
		{"skill", "add", "./solo"},
		{"plugin", "add", "github:owner", "--all"},
		{"skill", "add", "github:https://example.com/owner/repo"},
		{"skill", "add", "github:https://github.com/owner/repo?ref=main"},
		{"plugin", "add", githubRootSource + "/../plugin", "--all"},
		{"skill", "add", githubRootSource + "//tmp/solo"},
		{"skill", "add", githubRootSource + "/.git"},
		{"skill", "add", "local:/tmp/solo"},
		{"skill", "add", "local:solo"},
		{"skill", "add", githubSoloSource, "--ref", "HEAD^{commit}"},
		{"plugin", "add", githubPluginSource, "--all", "--none"},
		{"plugin", "add", githubPluginSource, "--all", "--skill", "alpha"},
	} {
		result := s.run(project, arguments...)
		s.requireFailure(result)
		s.requireFile(project+"/c-plugin-lock.json", lock)
		s.requireMissing(project + "/.agents/c-plugin-state.json")
		s.requireMissing(project + "/.agents/skills/alpha")
		s.requireMissing(project + "/.agents/skills/solo")
	}
}

func githubSourceFailureScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := githubEnvironment(t, environment, "source-failure")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	for _, arguments := range [][]string{
		{"plugin", "add", githubRootSource, "--ref", githubFixtureRef, "--all"},
		{"skill", "add", githubRootSource + "/hs/test/fixtures/github", "--ref", githubFixtureRef},
		{"plugin", "add", githubRootSource + "/hs/test/fixtures/github/missing", "--ref", githubFixtureRef, "--all"},
		{"plugin", "add", githubPluginSource, "--ref", "c-plugin-e2e-ref-that-does-not-exist", "--all"},
		{"skill", "add", "github:totto2727-org/c-plugin-e2e-repository-that-does-not-exist/" + githubSoloPath},
	} {
		result := s.run(project, arguments...)
		s.requireFailure(result)
		s.requireFile(project+"/c-plugin-lock.json", lock)
		s.requireMissing(project + "/.agents/c-plugin-state.json")
		s.requireMissing(project + "/.agents/skills/alpha")
		s.requireMissing(project + "/.agents/skills/solo")
	}
}

func githubPluginLifecycleScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := githubEnvironment(t, environment, "plugin-lifecycle")
	s.mkdirAll(project + "/nested")
	s.requireSuccess(s.run(project+"/nested", "plugin", "add", githubPluginSource,
		"--ref", githubFixtureRef, "--all"))
	entry := githubRegisteredSource(s, project, "plugin", "github-demo")
	githubPinnedCommit(s, entry)
	source := path.Join(project, entry.Source)
	s.requireJSON(source+"/plugin.json", `{"$schema":"`+pluginSchema+`","name":"github-demo"}`)
	s.requireSymlink(project+"/.agents/skills/alpha", source+"/skills/alpha")
	s.requireSymlink(project+"/.agents/skills/beta", source+"/skills/beta")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	s.remove(project + "/.agents/skills/alpha")
	repeat := s.run(project, "plugin", "add", githubPluginURLSource,
		"--ref", githubFixtureRef, "--all")
	s.requireSuccess(repeat)
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireFile(project+"/.agents/c-plugin-state.json", state)
	s.requireMissing(project + "/.agents/skills/alpha")
	s.requireSuccess(s.run(project, "sync"))
	s.requireSymlink(project+"/.agents/skills/alpha", source+"/skills/alpha")
	s.requireSuccess(s.run(project, "plugin", "add", githubPluginSource,
		"--ref", githubFixtureRef, "--skill", "beta"))
	selected := githubRegisteredSource(s, project, "plugin", "github-demo")
	if len(selected.Skills) != 1 || selected.Skills[0] != "beta" {
		t.Fatalf("selected skills=%v want=[beta]", selected.Skills)
	}
	s.requireMissing(project + "/.agents/skills/alpha")
	s.requireSymlink(project+"/.agents/skills/beta", source+"/skills/beta")
	s.requireSuccess(s.run(project, "plugin", "add", githubPluginSource,
		"--ref", githubFixtureRef, "--none"))
	disabled := githubRegisteredSource(s, project, "plugin", "github-demo")
	if len(disabled.Skills) != 0 {
		t.Fatalf("disabled skills=%v want=[]", disabled.Skills)
	}
	s.requireMissing(project + "/.agents/skills/beta")
	s.requireSuccess(s.run(project, "plugin", "remove", "--plugin", "github-demo"))
	s.requireJSON(project+"/c-plugin-lock.json", emptyLock)
	s.requireJSON(project+"/.agents/c-plugin-state.json", `{"ownershipEntries":{}}`)
	s.requireRegularFile(source + "/plugin.json")
}

func githubStandaloneOfflineScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := githubEnvironment(t, environment, "standalone-offline")
	s.requireSuccess(s.run(project, "skill", "add", githubSoloURLSource,
		"--ref", githubFixtureRef))
	entry := githubRegisteredSource(s, project, "skill", "solo")
	githubPinnedCommit(s, entry)
	source := path.Join(project, entry.Source)
	s.requireSymlink(project+"/.agents/skills/solo", source)
	s.requireMissing(source + "/plugin.json")
	digest := s.digest(source + "/SKILL.md")
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	s.remove(project + "/.agents/skills/solo")
	s.requireSuccess(s.run(project, "skill", "add", githubSoloSource,
		"--ref", githubFixtureRef))
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireFile(project+"/.agents/c-plugin-state.json", state)
	s.requireMissing(project + "/.agents/skills/solo")
	// A real Git network probe must fail with the same unreachable proxies used
	// for sync. Local Git integrity verification remains available.
	offlineEnv := []string{"HOME=" + s.home,
		"HTTPS_PROXY=http://127.0.0.1:1", "https_proxy=http://127.0.0.1:1",
		"HTTP_PROXY=http://127.0.0.1:1", "http_proxy=http://127.0.0.1:1",
		"ALL_PROXY=http://127.0.0.1:1", "all_proxy=http://127.0.0.1:1", "NO_PROXY=", "no_proxy="}
	probe, err := environment.Run(cli.Command{
		Args:       []string{"git", "ls-remote", githubFixtureURL, "refs/heads/" + githubFixtureRef},
		WorkingDir: project,
		Env:        offlineEnv,
	})
	if err != nil {
		t.Fatal(err)
	}
	s.requireFailure(probe)
	offline, err := environment.Run(cli.Command{
		Args:       []string{cPlugin, "sync"},
		WorkingDir: project,
		Env:        offlineEnv,
	})
	if err != nil {
		t.Fatal(err)
	}
	s.requireSuccess(offline)
	s.requireSymlink(project+"/.agents/skills/solo", source)
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireDigest(source+"/SKILL.md", digest)
	s.requireSuccess(s.run(project, "skill", "remove", "--skill", "solo"))
	s.requireJSON(project+"/c-plugin-lock.json", emptyLock)
	s.requireMissing(project + "/.agents/skills/solo")
	s.requireDigest(source+"/SKILL.md", digest)
}

func githubGlobalScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := githubEnvironment(t, environment, "global")
	s.requireSuccess(s.run(project, "init", "--global"))
	s.requireSuccess(s.run(project, "skill", "add", githubSoloSource,
		"--ref", githubFixtureRef))
	projectEntry := githubRegisteredSource(s, project, "skill", "solo")
	commit := githubPinnedCommit(s, projectEntry)
	projectLock := string(s.readFile(project + "/c-plugin-lock.json"))
	projectState := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	s.mkdirAll(project + "/nested")
	s.requireSuccess(s.run(project+"/nested", "skill", "add", "--global", githubSoloURLSource,
		"--ref", commit))
	globalEntry := githubRegisteredSource(s, s.home, "skill", "solo")
	globalSource := path.Join(s.home, globalEntry.Source)
	projectSource := path.Join(project, projectEntry.Source)
	if globalSource == projectSource || !strings.HasPrefix(globalSource, s.home+"/") || strings.HasPrefix(globalSource, project+"/") {
		t.Fatalf("global source=%s project source=%s are not isolated", globalSource, projectSource)
	}
	s.requireSymlink(s.home+"/.agents/skills/solo", globalSource)
	s.requireSuccess(s.run(project+"/nested", "sync", "--global"))
	s.requireSuccess(s.run(project+"/nested", "skill", "remove", "--global", "--skill", "solo"))
	s.requireJSON(s.home+"/c-plugin-lock.json", emptyLock)
	s.requireMissing(s.home + "/.agents/skills/solo")
	s.requireFile(project+"/c-plugin-lock.json", projectLock)
	s.requireFile(project+"/.agents/c-plugin-state.json", projectState)
	s.requireSymlink(project+"/.agents/skills/solo", projectSource)
}

func githubCacheSafetyScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := githubEnvironment(t, environment, "cache-safety")
	outside := s.home + "/outside"
	s.writeFile(outside+"/sentinel", "foreign cache must survive\n")
	s.mkdirAll(project + "/.agents/c-plugin")
	s.requireSuccess(s.runInfrastructure("", "ln", "-s", outside, project+"/.agents/c-plugin/sources"))
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	rejected := s.run(project, "skill", "add", githubSoloSource,
		"--ref", githubFixtureRef, "--force")
	s.requireFailure(rejected)
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireMissing(project + "/.agents/c-plugin-state.json")
	s.requireMissing(outside + "/totto2727-org")
	s.requireFile(outside+"/sentinel", "foreign cache must survive\n")
	s.requireSymlink(project+"/.agents/c-plugin/sources", outside)
	s.remove(project + "/.agents/c-plugin/sources")
	s.requireSuccess(s.run(project, "skill", "add", githubSoloSource,
		"--ref", githubFixtureRef))
	entry := githubRegisteredSource(s, project, "skill", "solo")
	commit := githubPinnedCommit(s, entry)
	cache := project + "/.agents/c-plugin/sources/" + githubFixtureRepository + "/" + commit
	source := path.Join(project, entry.Source)
	s.requireJSON(cache+"/origin.json", `{"snapshotRepository":"`+githubFixtureRepository+`","snapshotCommit":"`+commit+`"}`)
	origin := string(s.readFile(cache + "/origin.json"))
	lock = string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	digest := s.digest(source + "/SKILL.md")
	s.writeFile(cache+"/origin.json", `{"snapshotRepository":"foreign/repository","snapshotCommit":"`+commit+`"}`)
	foreignOrigin := string(s.readFile(cache + "/origin.json"))
	partial := s.run(project, "sync")
	s.requireSuccess(partial)
	s.requireContains(partial.Stdout, "partial")
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireFile(project+"/.agents/c-plugin-state.json", state)
	s.requireFile(cache+"/origin.json", foreignOrigin)
	s.requireSymlink(project+"/.agents/skills/solo", source)
	s.requireDigest(source+"/SKILL.md", digest)
	s.writeFile(cache+"/origin.json", origin)
	s.requireSuccess(s.runInfrastructure("", "git", "-C", cache+"/tree", "remote", "set-url", "origin", "https://github.com/foreign/repository.git"))
	partial = s.run(project, "sync")
	s.requireSuccess(partial)
	s.requireContains(partial.Stdout, "partial")
	s.requireFile(project+"/c-plugin-lock.json", lock)
	s.requireFile(project+"/.agents/c-plugin-state.json", state)
	s.requireSymlink(project+"/.agents/skills/solo", source)
	s.requireDigest(source+"/SKILL.md", digest)
	remote := s.runInfrastructure("", "git", "-C", cache+"/tree", "remote", "get-url", "origin")
	s.requireSuccess(remote)
	s.requireOutput(remote, "https://github.com/foreign/repository.git\n")
	s.requireFile(outside+"/sentinel", "foreign cache must survive\n")
}

func githubForceSafetyScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := githubEnvironment(t, environment, "force-safety")
	s.writeFile(project+"/.agents/skills/alpha/keep", "foreign directory\n")
	s.writeFile(project+"/.agents/skills/beta", "replace eligible file\n")
	s.writeFile(project+"/.agents/skills/neighbor", "foreign neighbor\n")
	s.requireSuccess(s.run(project, "plugin", "add", githubPluginSource,
		"--ref", githubFixtureRef, "--all", "--force"))
	entry := githubRegisteredSource(s, project, "plugin", "github-demo")
	githubPinnedCommit(s, entry)
	source := path.Join(project, entry.Source)
	s.requireDirectory(project + "/.agents/skills/alpha")
	s.requireFile(project+"/.agents/skills/alpha/keep", "foreign directory\n")
	s.requireFile(project+"/.agents/skills/neighbor", "foreign neighbor\n")
	s.requireSymlink(project+"/.agents/skills/beta", source+"/skills/beta")
	s.requireSuccess(s.run(project, "plugin", "remove", "--plugin", "github-demo"))
	s.requireJSON(project+"/c-plugin-lock.json", emptyLock)
	s.requireMissing(project + "/.agents/skills/beta")
	s.requireFile(project+"/.agents/skills/alpha/keep", "foreign directory\n")
	s.requireFile(project+"/.agents/skills/neighbor", "foreign neighbor\n")
}

func topLevelSyncUpdateRecursiveScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := githubEnvironment(t, environment, "top-level-recursive")
	remote := s.runInfrastructure("", "git", "ls-remote", githubFixtureURL, "refs/heads/"+githubFixtureRef)
	s.requireSuccess(remote)
	fields := strings.Fields(remote.Stdout)
	if len(fields) != 2 || fields[1] != "refs/heads/"+githubFixtureRef || !regexp.MustCompile(`^[0-9a-f]{40}$`).MatchString(fields[0]) {
		t.Fatalf("fixture ref resolution=%q", remote.Stdout)
	}
	commit := fields[0]
	s.requireSuccess(s.run(project, "plugin", "add", "github:"+githubFixtureURL+".git/"+githubPluginPath,
		"--ref", commit, "--all"))
	s.requireSuccess(s.run(project, "skill", "add", githubSoloSource,
		"--ref", commit))
	plugin := githubRegisteredSource(s, project, "plugin", "github-demo")
	solo := githubRegisteredSource(s, project, "skill", "solo")
	if githubPinnedCommit(s, plugin) != commit || githubPinnedCommit(s, solo) != commit {
		t.Fatal("both domains must pin the observed fixture commit")
	}
	pluginSource := path.Join(project, plugin.Source)
	soloSource := path.Join(project, solo.Source)
	lock := string(s.readFile(project + "/c-plugin-lock.json"))
	state := string(s.readFile(project + "/.agents/c-plugin-state.json"))
	lockIdentity := s.runInfrastructure("", "stat", "-c", "%i:%Y", project+"/c-plugin-lock.json")
	s.requireSuccess(lockIdentity)
	s.mkdirAll(project + "/nested")
	for _, command := range []string{"sync", "update"} {
		s.remove(project+"/.agents/skills/alpha", project+"/.agents/skills/beta", project+"/.agents/skills/solo")
		result := s.run(project+"/nested", command)
		s.requireSuccess(result)
		s.requireContains(result.Stdout, project+"/c-plugin-lock.json")
		s.requireSymlink(project+"/.agents/skills/alpha", pluginSource+"/skills/alpha")
		s.requireSymlink(project+"/.agents/skills/beta", pluginSource+"/skills/beta")
		s.requireSymlink(project+"/.agents/skills/solo", soloSource)
		s.requireFile(project+"/c-plugin-lock.json", lock)
		s.requireFile(project+"/.agents/c-plugin-state.json", state)
		identity := s.runInfrastructure("", "stat", "-c", "%i:%Y", project+"/c-plugin-lock.json")
		s.requireSuccess(identity)
		s.requireOutput(identity, lockIdentity.Stdout)
	}

	child := project + "/child"
	s.writePlugin(child, "child-skill")
	s.writeFile(child+"/standalone/solo/SKILL.md", skillMarkdown("solo"))
	childLock := `{"targets":[],"plugins":{"demo":{"pluginName":"demo","pluginSource":"plugin","enabledSkills":["child-skill"],"pluginOrigin":null}},"standaloneSkills":{"solo":{"installedSkillName":"solo","installedSkillSource":"standalone/solo","installedSkillOrigin":null}}}`
	s.writeFile(child+"/c-plugin-lock.json", childLock)
	// Admiral 0.6.2's actual matcher trims rules, ignores negations, strips
	// anchors, and matches '*' only within individual path segments.
	s.writeFile(project+"/.gitignore", "  # comment-visible/  \n  .hidden-excluded/  \n  ignored-*/  \n!ignored-keep/\n/anchored/\nglobstar/**/blocked/\npatterns/a*/blocked/\nquestion?/\nc-plugin-lock.json\n")
	s.writeFile(project+"/directory-scope/.gitignore", "  scoped/  \n")
	visibleRoots := []string{
		project, child, project + "/.hidden-included", project + "/comment-visible",
		project + "/globstar/a/b/blocked", project + "/other/scoped", project + "/questionx",
	}
	for _, root := range visibleRoots[2:] {
		s.writeFile(root+"/c-plugin-lock.json", emptyLock)
	}
	skippedRoots := []string{
		project + "/.git/trap", project + "/.hidden-excluded", project + "/ignored-alpha",
		project + "/ignored-keep", project + "/anchored", project + "/wrapped/anchored",
		project + "/globstar/a/blocked", project + "/wrapped/patterns/alpha/blocked",
		project + "/directory-scope/scoped", project + "/question?",
		project + "/.agents/c-plugin/sources/discovery-trap",
	}
	for _, root := range skippedRoots {
		s.writeFile(root+"/c-plugin-lock.json", "{invalid discovery trap\n")
	}
	outside := s.home + "/outside-project"
	s.writeFile(outside+"/c-plugin-lock.json", emptyLock)
	s.requireSuccess(s.runInfrastructure("", "ln", "-s", outside, project+"/symlinked-project"))
	for _, command := range []string{"sync", "update"} {
		s.remove(project+"/.agents/skills/alpha", project+"/.agents/skills/beta", project+"/.agents/skills/solo",
			child+"/.agents/skills/child-skill", child+"/.agents/skills/solo")
		result := s.run(project+"/nested", command, "-r")
		s.requireSuccess(result)
		parentIndex := strings.Index(result.Stdout, project+"/c-plugin-lock.json")
		for _, root := range visibleRoots {
			s.requireContains(result.Stdout, root+"/c-plugin-lock.json")
			if root != project && strings.Index(result.Stdout, root+"/c-plugin-lock.json") < parentIndex {
				t.Fatalf("recursive discovery did not report owning root first: %q", result.Stdout)
			}
		}
		for _, root := range skippedRoots {
			s.requireNotContains(result.Stdout, root+"/c-plugin-lock.json")
			s.requireFile(root+"/c-plugin-lock.json", "{invalid discovery trap\n")
			s.requireMissing(root + "/.agents/c-plugin-state.json")
		}
		s.requireNotContains(result.Stdout, "symlinked-project")
		s.requireMissing(outside + "/.agents/c-plugin-state.json")
		s.requireJSON(outside+"/c-plugin-lock.json", emptyLock)
		s.requireSymlink(project+"/.agents/skills/alpha", pluginSource+"/skills/alpha")
		s.requireSymlink(project+"/.agents/skills/beta", pluginSource+"/skills/beta")
		s.requireSymlink(project+"/.agents/skills/solo", soloSource)
		s.requireSymlink(child+"/.agents/skills/child-skill", child+"/plugin/skills/child-skill")
		s.requireSymlink(child+"/.agents/skills/solo", child+"/standalone/solo")
		s.requireFile(project+"/c-plugin-lock.json", lock)
		s.requireFile(child+"/c-plugin-lock.json", childLock)
		identity := s.runInfrastructure("", "stat", "-c", "%i:%Y", project+"/c-plugin-lock.json")
		s.requireSuccess(identity)
		s.requireOutput(identity, lockIdentity.Stdout)
	}

	missingRoot := s.home + "/missing-root"
	s.writeFile(missingRoot+"/child/c-plugin-lock.json", emptyLock)
	for _, command := range []string{"sync", "update"} {
		missing := s.run(missingRoot, command, "-r")
		s.requireFailure(missing)
		s.requireContains(missing.Stdout, "LockFileNotFound")
		s.requireMissing(missingRoot + "/c-plugin-lock.json")
		s.requireMissing(missingRoot + "/child/.agents/c-plugin-state.json")
		s.requireJSON(missingRoot+"/child/c-plugin-lock.json", emptyLock)
		global := s.run(project, command, "--global", "-r")
		s.requireFailure(global)
		s.requireContains(global.Stdout, "--global cannot be combined with --recursive")
		s.requireMissing(s.home + "/c-plugin-lock.json")
		s.requireMissing(s.home + "/.agents/c-plugin-state.json")
		s.requireFile(project+"/c-plugin-lock.json", lock)
		s.requireFile(child+"/c-plugin-lock.json", childLock)
	}
}
