package cplugine2e

import (
	"path"
	"testing"

	"github.com/totto2727-org/e2e/go/cli"
)

const pluginsHeading = "Plugins\nname\tsource\tenabled-skills\n"
const skillsHeading = "Skills\nname\towner\tsource\n"

func listReadOnlyScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := standardEnvironment(t, environment, "list-read-only", "alpha", "beta")
	s.writeFile(project+"/disabled/plugin.json", `{"$schema":"`+pluginSchema+`","name":"disabled"}`)
	s.writeFile(project+"/standalone/solo/SKILL.md", skillMarkdown("solo"))
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--skill", "alpha"))
	s.requireSuccess(s.run(project, "plugin", "add", "local:./disabled", "--none"))
	s.requireSuccess(s.run(project, "skill", "add", "local:./standalone/solo"))
	s.requireSuccess(s.run(project, "init", "--global"))
	s.writePlugin(s.home, "gamma")
	s.requireSuccess(s.run(project, "plugin", "add", "local:./plugin", "--all", "--global"))
	s.mkdirAll(project + "/nested")
	projectLock := s.digest(project + "/c-plugin-lock.json")
	globalLock := s.digest(s.home + "/c-plugin-lock.json")
	globalState := s.digest(s.home + "/.agents/c-plugin-state.json")
	// Listing is desired-state inspection, even with unavailable sources/links and corrupt ownership.
	s.remove(project+"/plugin", project+"/disabled", project+"/standalone", project+"/.agents/skills/alpha")
	s.writeFile(project+"/.agents/c-plugin-state.json", "corrupt ownership\n")
	s.writeFile(project+"/.agents/skills/neighbor", "foreign\n")
	plugins := pluginsHeading + "demo\tlocal:./plugin\talpha\ndisabled\tlocal:./disabled\t-\n"
	skills := skillsHeading + "alpha\tplugin:demo\tlocal:./plugin\nsolo\tstandalone\tlocal:./standalone/solo\n"
	globalPlugins := pluginsHeading + "demo\tlocal:./plugin\tgamma\n"
	globalSkills := skillsHeading + "gamma\tplugin:demo\tlocal:./plugin\n"
	for _, test := range []struct {
		arguments []string
		output    string
	}{
		{[]string{"list"}, plugins + "\n" + skills},
		{[]string{"plugin", "list"}, plugins},
		{[]string{"skill", "list"}, skills},
		{[]string{"list", "-g"}, globalPlugins + "\n" + globalSkills},
		{[]string{"plugin", "list", "-g"}, globalPlugins},
		{[]string{"skill", "list", "-g"}, globalSkills},
	} {
		result := s.run(project+"/nested", test.arguments...)
		s.requireSuccess(result)
		s.requireOutput(result, test.output)
		s.requireDigest(project+"/c-plugin-lock.json", projectLock)
		s.requireDigest(s.home+"/c-plugin-lock.json", globalLock)
		s.requireDigest(s.home+"/.agents/c-plugin-state.json", globalState)
		s.requireFile(project+"/.agents/c-plugin-state.json", "corrupt ownership\n")
		s.requireFile(project+"/.agents/skills/neighbor", "foreign\n")
		s.requireMissing(project + "/.agents/skills/alpha")
		s.requireMissing(project + "/plugin")
		s.requireMissing(project + "/disabled")
		s.requireMissing(project + "/standalone")
		s.requireSuccess(s.runInfrastructure("", "test", "-L", project+"/.agents/skills/solo"))
		s.requireSymlink(s.home+"/.agents/skills/gamma", s.home+"/plugin/skills/gamma")
	}
}

func listMissingCorruptScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	home := "/tmp/c-plugin-list-missing-corrupt/home"
	project := home + "/project"
	s := newScenarioEnvironment(t, environment, home)
	s.mkdirAll(project)
	for _, content := range []string{"", "not JSON\n", `{"version":"2","targets":[],"plugins":[]}`} {
		for _, root := range []string{project, home} {
			if content != "" {
				s.writeFile(root+"/c-plugin-lock.json", content)
			}
		}
		for _, arguments := range [][]string{{"list"}, {"plugin", "list"}, {"skill", "list"}, {"list", "-g"}, {"plugin", "list", "-g"}, {"skill", "list", "-g"}} {
			result := s.run(project, arguments...)
			s.requireFailure(result)
			for _, root := range []string{project, home} {
				if content == "" {
					s.requireMissing(root + "/c-plugin-lock.json")
				} else {
					s.requireFile(root+"/c-plugin-lock.json", content)
				}
				s.requireMissing(root + "/.agents")
			}
		}
	}
	for _, root := range []string{project, home} {
		s.writeFile(root+"/c-plugin-lock.json", emptyLock)
	}
	for _, test := range []struct {
		arguments []string
		output    string
	}{
		{[]string{"list"}, pluginsHeading + "\n" + skillsHeading},
		{[]string{"plugin", "list"}, pluginsHeading},
		{[]string{"skill", "list"}, skillsHeading},
		{[]string{"list", "-g"}, pluginsHeading + "\n" + skillsHeading},
		{[]string{"plugin", "list", "-g"}, pluginsHeading},
		{[]string{"skill", "list", "-g"}, skillsHeading},
	} {
		result := s.run(project, test.arguments...)
		s.requireSuccess(result)
		s.requireOutput(result, test.output)
		for _, root := range []string{project, home} {
			s.requireFile(root+"/c-plugin-lock.json", emptyLock)
			s.requireMissing(root + "/.agents")
		}
	}
}

func githubListUnavailableScenario(t *testing.T, environment *cli.Environment) {
	t.Helper()
	s, project := githubEnvironment(t, environment, "list-unavailable")
	s.requireSuccess(s.run(project, "plugin", "add", githubPluginSource, "--ref", githubFixtureRef, "--all"))
	entry := githubRegisteredSource(s, project, "plugin", "github-demo")
	commit := githubPinnedCommit(s, entry)
	s.requireSuccess(s.run(project, "skill", "add", githubSoloSource, "--ref", commit))
	source := path.Join(project, entry.Source)
	// Toggle pinned content offline before making the cache unavailable for listing.
	blockedNetwork := []string{"HOME=" + s.home,
		"HTTPS_PROXY=http://127.0.0.1:1", "https_proxy=http://127.0.0.1:1",
		"HTTP_PROXY=http://127.0.0.1:1", "http_proxy=http://127.0.0.1:1",
		"ALL_PROXY=http://127.0.0.1:1", "all_proxy=http://127.0.0.1:1", "NO_PROXY=", "no_proxy="}
	probe, err := environment.Run(cli.Command{Args: []string{"git", "ls-remote", githubFixtureURL, "refs/heads/" + githubFixtureRef}, WorkingDir: project, Env: blockedNetwork})
	if err != nil {
		t.Fatal(err)
	}
	s.requireFailure(probe)
	originalLock := s.digest(project + "/c-plugin-lock.json")
	manifest := s.digest(source + "/plugin.json")
	for _, arguments := range [][]string{
		{"plugin", "skill", "disable", "github-demo", "--all"},
		{"plugin", "skill", "enable", "github-demo", "--skill", "alpha"},
		{"plugin", "skill", "enable", "github-demo", "--all"},
	} {
		result, runErr := environment.Run(cli.Command{Args: append([]string{cPlugin}, arguments...), WorkingDir: project, Env: blockedNetwork})
		if runErr != nil {
			t.Fatal(runErr)
		}
		s.requireSuccess(result)
		current := githubRegisteredSource(s, project, "plugin", "github-demo")
		if actual := githubPinnedCommit(s, current); actual != commit {
			t.Fatalf("toggle moved pin: %s want %s", actual, commit)
		}
		s.requireDigest(source+"/plugin.json", manifest)
		if arguments[2] == "disable" {
			if len(current.Skills) != 0 {
				t.Fatalf("disabled plugin skills=%v", current.Skills)
			}
			s.requireMissing(project + "/.agents/skills/alpha")
			s.requireMissing(project + "/.agents/skills/beta")
		} else {
			s.requireSymlink(project+"/.agents/skills/alpha", source+"/skills/alpha")
		}
	}
	s.requireDigest(project+"/c-plugin-lock.json", originalLock)
	s.requireSymlink(project+"/.agents/skills/beta", source+"/skills/beta")
	cacheRoot := project + "/.agents/c-plugin/sources"
	// A rejecting git wrapper detects even attempted offline transport or verification.
	gitCalled := s.home + "/git-called"
	s.writeFile(s.home+"/bin/git-template", "#!/bin/sh\nprintf called > '"+gitCalled+"'\nexit 99\n")
	// Archive-written fixtures are root-owned. Copy into a new sandbox-owned file.
	s.requireSuccess(s.runInfrastructure("", "cp", s.home+"/bin/git-template", s.home+"/bin/git"))
	s.requireSuccess(s.runInfrastructure("", "chmod", "+x", s.home+"/bin/git"))
	offlineEnv := []string{"HOME=" + s.home, "PATH=" + s.home + "/bin:/usr/bin:/bin",
		"HTTPS_PROXY=http://127.0.0.1:1", "https_proxy=http://127.0.0.1:1",
		"HTTP_PROXY=http://127.0.0.1:1", "http_proxy=http://127.0.0.1:1",
		"ALL_PROXY=http://127.0.0.1:1", "all_proxy=http://127.0.0.1:1", "NO_PROXY=", "no_proxy="}
	s.remove(cacheRoot, project+"/.agents/skills/alpha")
	lock := s.digest(project + "/c-plugin-lock.json")
	state := s.digest(project + "/.agents/c-plugin-state.json")
	plugins := pluginsHeading + "github-demo\t" + githubPluginSource + "@" + commit + "\talpha,beta\n"
	skills := skillsHeading + "alpha\tplugin:github-demo\t" + githubPluginSource + "@" + commit + "\n" +
		"beta\tplugin:github-demo\t" + githubPluginSource + "@" + commit + "\n" +
		"solo\tstandalone\t" + githubSoloSource + "@" + commit + "\n"
	for _, test := range []struct {
		arguments []string
		output    string
	}{
		{[]string{"list"}, plugins + "\n" + skills},
		{[]string{"plugin", "list"}, plugins},
		{[]string{"skill", "list"}, skills},
	} {
		result, err := environment.Run(cli.Command{Args: append([]string{cPlugin}, test.arguments...), WorkingDir: project, Env: offlineEnv})
		if err != nil {
			t.Fatal(err)
		}
		s.requireSuccess(result)
		s.requireOutput(result, test.output)
		s.requireDigest(project+"/c-plugin-lock.json", lock)
		s.requireDigest(project+"/.agents/c-plugin-state.json", state)
		s.requireMissing(cacheRoot)
		s.requireMissing(source)
		s.requireMissing(gitCalled)
		s.requireMissing(project + "/.agents/skills/alpha")
		s.requireSuccess(s.runInfrastructure("", "test", "-L", project+"/.agents/skills/beta"))
		s.requireSuccess(s.runInfrastructure("", "test", "-L", project+"/.agents/skills/solo"))
	}
}
