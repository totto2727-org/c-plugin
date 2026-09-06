package cplugine2e

const emptyLock = `{"version":"2","targets":[],"repositories":[]}`

func (s *scenarioEnvironment) writeMarketplace(root string, skill string) {
	s.t.Helper()
	repository := root + "/marketplace"
	plugin := repository + "/plugins/demo"
	s.writeFile(repository+"/.claude-plugin/marketplace.json", marketplaceJSON())
	s.writeFile(plugin+"/skills/"+skill+"/SKILL.md", "# "+skill+"\n")
}

func (s *scenarioEnvironment) writeMarketplaceSkills(root string, skills ...string) {
	s.t.Helper()
	repository := root + "/marketplace"
	plugin := repository + "/plugins/demo"
	s.writeFile(repository+"/.claude-plugin/marketplace.json", marketplaceJSON())
	for _, skill := range skills {
		s.writeFile(plugin+"/skills/"+skill+"/SKILL.md", "# "+skill+"\n")
	}
}
