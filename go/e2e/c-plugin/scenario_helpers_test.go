package cplugine2e

import (
	"bytes"
	"crypto/sha256"
	"encoding/json"
	"github.com/totto2727-org/e2e/cli"
	"strings"
	"testing"
)

const cPlugin = "/sandbox/.local/bin/c-plugin"

type scenarioEnvironment struct {
	t           *testing.T
	environment *cli.Environment
	home        string
}

func newScenarioEnvironment(t *testing.T, environment *cli.Environment, home string) *scenarioEnvironment {
	t.Helper()
	return &scenarioEnvironment{t: t, environment: environment, home: home}
}

func (s *scenarioEnvironment) run(directory string, arguments ...string) cli.Result {
	s.t.Helper()
	command := append([]string{cPlugin}, arguments...)
	result, err := s.environment.Run(cli.Command{
		Args:       command,
		WorkingDir: directory,
		Env:        []string{"HOME=" + s.home},
	})
	if err != nil {
		s.t.Fatal(err)
	}
	return result
}

func (s *scenarioEnvironment) runInfrastructure(directory string, arguments ...string) cli.Result {
	s.t.Helper()
	result, err := s.environment.Run(cli.Command{Args: arguments, WorkingDir: directory})
	if err != nil {
		s.t.Fatal(err)
	}
	return result
}

func (s *scenarioEnvironment) mkdirAll(paths ...string) {
	s.t.Helper()
	result := s.runInfrastructure("", append([]string{"mkdir", "-p"}, paths...)...)
	s.requireExit(result, 0)
}

func (s *scenarioEnvironment) readFile(filePath string) []byte {
	s.t.Helper()
	content, err := s.environment.ReadFile(filePath)
	if err != nil {
		s.t.Fatal(err)
	}
	return content
}

func (s *scenarioEnvironment) digest(filePath string) [sha256.Size]byte {
	s.t.Helper()
	return sha256.Sum256(s.readFile(filePath))
}

func (s *scenarioEnvironment) requireExit(result cli.Result, expected int) {
	s.t.Helper()
	if result.ExitCode != expected {
		s.t.Fatalf("exit_code=%d want=%d output=%q", result.ExitCode, expected, result.Stdout)
	}
}

func (s *scenarioEnvironment) requireSuccess(result cli.Result) {
	s.t.Helper()
	s.requireExit(result, 0)
}

func (s *scenarioEnvironment) requireFailure(result cli.Result) {
	s.t.Helper()
	if result.ExitCode == 0 {
		s.t.Fatalf("expected failure, output=%q", result.Stdout)
	}
}

func (s *scenarioEnvironment) requireOutput(result cli.Result, expected string) {
	s.t.Helper()
	if result.Stdout != expected {
		s.t.Fatalf("output=%q want=%q", result.Stdout, expected)
	}
}

func (s *scenarioEnvironment) requireContains(value string, expected string) {
	s.t.Helper()
	if !strings.Contains(value, expected) {
		s.t.Fatalf("value=%q does not contain %q", value, expected)
	}
}

func (s *scenarioEnvironment) requireJSON(filePath string, expected string) {
	s.t.Helper()
	var actualValue any
	if err := json.Unmarshal(s.readFile(filePath), &actualValue); err != nil {
		s.t.Fatalf("decode %s: %v", filePath, err)
	}
	var expectedValue any
	if err := json.Unmarshal([]byte(expected), &expectedValue); err != nil {
		s.t.Fatalf("decode expected JSON: %v", err)
	}
	actualJSON, err := json.Marshal(actualValue)
	if err != nil {
		s.t.Fatal(err)
	}
	expectedJSON, err := json.Marshal(expectedValue)
	if err != nil {
		s.t.Fatal(err)
	}
	if !bytes.Equal(actualJSON, expectedJSON) {
		s.t.Fatalf("JSON %s=%s want=%s", filePath, actualJSON, expectedJSON)
	}
}

func (s *scenarioEnvironment) pathExists(filePath string) bool {
	s.t.Helper()
	regular := s.runInfrastructure("", "test", "-e", filePath)
	if regular.ExitCode == 0 {
		return true
	}
	symlink := s.runInfrastructure("", "test", "-L", filePath)
	return symlink.ExitCode == 0
}

func (s *scenarioEnvironment) requireMissing(filePath string) {
	s.t.Helper()
	if s.pathExists(filePath) {
		s.t.Fatalf("path %s exists", filePath)
	}
}

func (s *scenarioEnvironment) requireDigest(filePath string, expected [sha256.Size]byte) {
	s.t.Helper()
	if actual := s.digest(filePath); actual != expected {
		s.t.Fatalf("digest %s=%x want=%x", filePath, actual, expected)
	}
}
