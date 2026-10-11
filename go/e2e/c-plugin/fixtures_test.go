package cplugine2e

const emptyLock = `{"version":"3","targets":[],"plugins":[]}`

const pluginSchema = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"

func (s *scenarioEnvironment) writePlugin(root string, skills ...string) {
	s.t.Helper()
	plugin := root + "/plugin"
	s.writeFile(plugin+"/plugin.json", pluginJSON())
	for _, skill := range skills {
		s.writeFile(plugin+"/skills/"+skill+"/SKILL.md", skillMarkdown(skill))
	}
}

func skillMarkdown(name string) string {
	return "---\nname: " + name + "\ndescription: Fixture " + name + " skill.\n---\n"
}
