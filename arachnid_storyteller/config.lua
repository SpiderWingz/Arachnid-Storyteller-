Config = {}

-- Access the gamemaster console with /STTool.
Config.Command = 'STTool'

-- Both ACE permissions are required. Keeping them separate lets server owners
-- grant console visibility and story editing deliberately.
Config.Ace = {
  open = 'arachnid.storyteller.open',
  manage = 'arachnid.storyteller.manage'
}

Config.Limits = {
  storyTitle = 100,
  storySummary = 4000,
  sceneTitle = 100,
  sceneObjective = 1000,
  sceneOrder = 10000
}
