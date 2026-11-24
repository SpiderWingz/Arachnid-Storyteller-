Config = {}

-- Access the gamemaster console with /STTool.
Config.Command = 'STTool'

-- Both ACE permissions are required. Keeping them separate lets server owners
-- grant console visibility and story editing deliberately.
Config.Ace = {
  open = 'arachnid.storyteller.open',
  manage = 'arachnid.storyteller.manage',
  playerActions = 'arachnid.storyteller.playeractions'
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
Config.Limits.teleportLabel = 100

Config.Areas = {
  minRadius = 1,
  maxRadius = 500,
  minDimension = 1,
  maxDimension = 1000
}

-- Server-side flow execution limits. Flows are snapshotted when a session starts.
Config.Flow = {
  maxNodes = 100,
  maxLinks = 200,
  maxStepsPerTick = 32,
  tickMs = 500,
  maxDelaySeconds = 3600,
  maxVariableNumber = 1000000000
}

-- Player actions are opt-in except for narrative messages. Whitelists are
-- intentionally empty so weapon and VORP job nodes cannot run by accident.
Config.PlayerActions = {
  enabled = {
    sendMessage = true,
    freeze = false,
    unfreeze = false,
    health = false,
    armor = false,
    giveWeapon = false,
    removeWeapon = false,
    stripAllWeapons = false,
    teleport = false,
    kill = false,
    respawn = false,
    changeJob = false
  },
  maxMessageLength = 1000,
  maxHealth = 500,
  maxArmor = 100,
  maxAmmo = 1000,
  teleportZOffset = 1.0,
  weapons = {},
  jobs = {}
}

-- Replace the empty allowlists above with entries like these:
-- Config.PlayerActions.weapons = {
--   WEAPON_REVOLVER_CATTLEMAN = { label = 'Cattleman Revolver', maxAmmo = 120, defaultAmmo = 6 }
-- }
-- Config.PlayerActions.jobs = {
--   sheriff = { label = 'Sheriff', grades = { 0, 1, 2 } }
-- }
