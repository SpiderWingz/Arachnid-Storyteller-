Config = {}

-- Access the gamemaster console with /STTool.
Config.Command = 'STTool'

-- Console access is separate from the ACE permission for each optional feature
-- family, so server owners can grant editing and world authority deliberately.
Config.Ace = {
  open = 'arachnid.storyteller.open',
  manage = 'arachnid.storyteller.manage',
  playerActions = 'arachnid.storyteller.playeractions',
  cutscenes = 'arachnid.storyteller.cutscenes',
  encounters = 'arachnid.storyteller.encounters',
  world = 'arachnid.storyteller.world',
  effects = 'arachnid.storyteller.effects'
}

Config.Limits = {
  storyTitle = 100,
  storySummary = 4000,
  sceneTitle = 100,
  sceneObjective = 1000,
  sceneOrder = 10000
}

-- A session is a single, server-authoritative live story. Optional player,
-- world, encounter, cutscene, and effect controls each have separate gates.
Config.Session = {
  broadcastToPlayers = true,
  overlayDuration = 12000,
  requirePublishedStory = true,
  maxParticipants = 64
}

-- Camera rails are authored as ordered, persistent shot points and can be
-- previewed or played as cutscenes for a session audience.
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

Config.Cutscenes = {
  enabled = false,
  maxPoints = 100,
  maxDuration = 1800,
  minFov = 20,
  maxFov = 120,
  maxFadeSeconds = 30,
  letterbox = true,
  freezePlayers = false,
  hideHud = false,
  loop = false,
  defaultFov = 75,
  fadeIn = 0,
  fadeOut = 0
}

Config.Encounters = {
  enabled = false,
  cleanupOnEnd = true,
  maxNpcsPerSession = 32,
  maxPropsPerSession = 64,
  maxGroupCount = 12,
  maxNpcHealth = 1000,
  maxWeaponAmmo = 1000,
  maxPatrolWaitSeconds = 300,
  minPatrolSpeed = 0.5,
  maxPatrolSpeed = 3.0,
  defaultPatrolSpeed = 1.0,
  patrolArrivalRadius = 2.0,
  patrolPathTimeoutSeconds = 180,
  defaultStance = 'fire_at_will',
  spawnPointLabel = 100,
  weapons = {},
  pedModels = {},
  propModels = {}
}

-- The tactical command view is a separate live-session tool. It only controls
-- NPCs spawned and tracked by this resource, and requires the encounters ACE.
Config.Rts = {
  enabled = false,
  snapshotIntervalMs = 1200,
  maxOrderDistance = 1000,
  autoEngage = true,
  autoEngageRange = 75,
  autoEngageIntervalMs = 1200
}

-- World targets are stable map references maintained by the server owner.
-- Each entry must define a supported type, a position and its allowed actions.
-- `restoreOnSessionEnd` selects whether Arachnid restores the observed prior
-- state or keeps the requested final state when a story finishes.
Config.World = {
  enabled = false,
  targets = {}
}

Config.Effects = {
  enabled = false,
  sounds = {},
  maxDurationSeconds = 30,
  maxVolume = 1.0,
  minPitch = 50,
  maxPitch = 150,
  maxShakeAmplitude = 10,
  maxShakeFrequency = 10,
  maxMessageLength = 1000
}

-- Replace the empty allowlists above with entries like these:
-- Config.PlayerActions.weapons = {
--   WEAPON_REVOLVER_CATTLEMAN = { label = 'Cattleman Revolver', maxAmmo = 120, defaultAmmo = 6 }
-- }
-- Config.PlayerActions.jobs = {
--   sheriff = { label = 'Sheriff', grades = { 0, 1, 2 } }
-- }
