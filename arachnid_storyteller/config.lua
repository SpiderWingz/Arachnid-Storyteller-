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

-- A session is a single, server-authoritative live story. The initial runtime
-- broadcasts scene titles and objectives only; it does not control players.
Config.Session = {
  broadcastToPlayers = true,
  overlayDuration = 12000,
  requirePublishedStory = true,
  maxParticipants = 64
}

-- Camera rails are authored as ordered, persistent shot points. Playback and
-- interpolation deliberately remain a later phase; these settings define safe
-- capture defaults for the editor now.
Config.Camera = {
  captureHeight = 1.6,
  defaultFov = 75,
  defaultHoldDuration = 3,
  defaultTransitionDuration = 2,
  maxFov = 120,
  maxHoldDuration = 300,
  maxTransitionDuration = 60
}

-- Leave `weapon` empty for panel-only camera-point capture. Set it to a weapon
-- hash or weapon name to require that the storyteller has that gun/tool equipped
-- when capturing a point from the panel. The distance slider decides how far
-- forward from the storyteller the node is saved.
Config.Camera.Tool = {
  weapon = '',
  defaultPlacementDistance = 0,
  maxPlacementDistance = 75
}

Config.Limits.cameraLabel = 100
Config.Limits.cameraMessage = 500
Config.Limits.activeObjective = 1000
Config.Limits.areaLabel = 100

Config.Areas = {
  minRadius = 1,
  maxRadius = 500,
  minDimension = 1,
  maxDimension = 1000
}
