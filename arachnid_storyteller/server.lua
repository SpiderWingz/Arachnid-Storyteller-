local databaseReady = false
local activeSession = nil
local statuses = { draft = true, published = true, archived = true }
local objectiveStatuses = { active = true, completed = true, failed = true }
local areaShapes = { sphere = true, box = true }
local frozenByArachnid = {}
local trackedEncounterEntities = {}
local cleanupSessionEncounters
local stopSessionNpcOrders
local cleanupSessionWorld
local cleanupSessionEffects

MySQL.ready(function()
  local ok, err = pcall(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS arachnid_storyteller_audit (
      id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      actor_name VARCHAR(100) NOT NULL,
      actor_identifier VARCHAR(160) NOT NULL,
      action VARCHAR(255) NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_arachnid_audit_created (created_at)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS arachnid_storyteller_stories (
      id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      title VARCHAR(100) NOT NULL,
      summary TEXT NOT NULL,
      status VARCHAR(16) NOT NULL DEFAULT 'draft',
      created_by VARCHAR(100) NOT NULL,
      updated_by VARCHAR(100) NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_arachnid_story_status (status),
      INDEX idx_arachnid_story_updated (updated_at)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS arachnid_storyteller_scenes (
      id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      story_id BIGINT UNSIGNED NOT NULL,
      title VARCHAR(100) NOT NULL,
      objective TEXT NOT NULL,
      sort_order INT UNSIGNED NOT NULL DEFAULT 1,
      x DOUBLE NULL,
      y DOUBLE NULL,
      z DOUBLE NULL,
      created_by VARCHAR(100) NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_arachnid_scene_story_order (story_id, sort_order, id)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS arachnid_storyteller_camera_points (
      id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      scene_id BIGINT UNSIGNED NOT NULL,
      label VARCHAR(100) NOT NULL,
      message VARCHAR(500) NOT NULL DEFAULT '',
      sort_order INT UNSIGNED NOT NULL DEFAULT 1,
      x DOUBLE NOT NULL,
      y DOUBLE NOT NULL,
      z DOUBLE NOT NULL,
      heading DOUBLE NOT NULL DEFAULT 0,
      fov DOUBLE NOT NULL DEFAULT 75,
      hold_duration DOUBLE NOT NULL DEFAULT 3,
      transition_duration DOUBLE NOT NULL DEFAULT 2,
      created_by VARCHAR(100) NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_arachnid_camera_scene_order (scene_id, sort_order, id)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS arachnid_storyteller_areas (
      id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      label VARCHAR(100) NOT NULL,
      shape VARCHAR(16) NOT NULL DEFAULT 'sphere',
      x DOUBLE NOT NULL,
      y DOUBLE NOT NULL,
      z DOUBLE NOT NULL,
      radius DOUBLE NOT NULL DEFAULT 10,
      width DOUBLE NOT NULL DEFAULT 10,
      depth DOUBLE NOT NULL DEFAULT 10,
      height DOUBLE NOT NULL DEFAULT 10,
      created_by VARCHAR(100) NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_arachnid_area_shape (shape)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS arachnid_storyteller_flows (
      story_id BIGINT UNSIGNED PRIMARY KEY,
      graph_json LONGTEXT NOT NULL,
      updated_by VARCHAR(100) NOT NULL,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS arachnid_storyteller_teleports (
      id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      story_id BIGINT UNSIGNED NOT NULL,
      label VARCHAR(100) NOT NULL,
      x DOUBLE NOT NULL,
      y DOUBLE NOT NULL,
      z DOUBLE NOT NULL,
      heading DOUBLE NOT NULL DEFAULT 0,
      created_by VARCHAR(100) NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_arachnid_teleport_story (story_id,id)
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS arachnid_storyteller_cutscene_settings (
      scene_id BIGINT UNSIGNED PRIMARY KEY,
      settings_json LONGTEXT NOT NULL,
      updated_by VARCHAR(100) NOT NULL,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS arachnid_storyteller_spawn_points (
      id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      story_id BIGINT UNSIGNED NOT NULL,
      label VARCHAR(100) NOT NULL,
      kind VARCHAR(20) NOT NULL,
      x DOUBLE NOT NULL,
      y DOUBLE NOT NULL,
      z DOUBLE NOT NULL,
      heading DOUBLE NOT NULL DEFAULT 0,
      created_by VARCHAR(100) NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_arachnid_spawn_story (story_id,kind,id)
    )]])
  end)
  databaseReady = ok
  if not ok then print('[arachnid_storyteller] Database setup failed: ' .. tostring(err)) end
end)

local function canManage(src)
  return src > 0
    and IsPlayerAceAllowed(src, Config.Ace.open)
    and IsPlayerAceAllowed(src, Config.Ace.manage)
end

local function cleanText(value, maxLength, required)
  if type(value) ~= 'string' then return nil end
  value = value:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if #value > maxLength or (required and value == '') then return nil end
  return value
end

local function positiveInteger(value)
  local number = tonumber(value)
  if not number or number % 1 ~= 0 or number < 1 then return nil end
  return math.floor(number)
end

local function boundedNumber(value, minimum, maximum)
  local number = tonumber(value)
  if not number or number ~= number or number < minimum or number > maximum then return nil end
  return number
end

local function defaultCutsceneSettings()
  return {
    freezePlayers = Config.Cutscenes.freezePlayers == true,
    hideHud = Config.Cutscenes.hideHud == true,
    letterbox = Config.Cutscenes.letterbox ~= false,
    loop = Config.Cutscenes.loop == true,
    fadeIn = tonumber(Config.Cutscenes.fadeIn) or 0,
    fadeOut = tonumber(Config.Cutscenes.fadeOut) or 0,
    defaultFov = tonumber(Config.Cutscenes.defaultFov) or 75
  }
end

local function normalizedCutsceneSettings(raw)
  local defaults = defaultCutsceneSettings()
  raw = type(raw) == 'table' and raw or {}
  local settings = {}
  for _, key in ipairs({ 'freezePlayers', 'hideHud', 'letterbox', 'loop' }) do
    if raw[key] ~= nil and type(raw[key]) ~= 'boolean' then return nil, 'Cutscene toggles must be true or false.' end
    settings[key] = raw[key] == nil and defaults[key] or raw[key]
  end
  settings.fadeIn = boundedNumber(raw.fadeIn == nil and defaults.fadeIn or raw.fadeIn, 0, Config.Cutscenes.maxFadeSeconds)
  settings.fadeOut = boundedNumber(raw.fadeOut == nil and defaults.fadeOut or raw.fadeOut, 0, Config.Cutscenes.maxFadeSeconds)
  settings.defaultFov = boundedNumber(raw.defaultFov == nil and defaults.defaultFov or raw.defaultFov, Config.Cutscenes.minFov, Config.Cutscenes.maxFov)
  if settings.fadeIn == nil or settings.fadeOut == nil or settings.defaultFov == nil then
    return nil, 'Cutscene fade and FOV values exceed the server limits.'
  end
  return settings
end

local function sceneCutsceneSettings(sceneId)
  local rows = MySQL.query.await('SELECT settings_json FROM arachnid_storyteller_cutscene_settings WHERE scene_id=? LIMIT 1', { sceneId }) or {}
  if rows[1] then
    local ok, decoded = pcall(json.decode, rows[1].settings_json)
    if ok and type(decoded) == 'table' then return normalizedCutsceneSettings(decoded) end
  end
  return defaultCutsceneSettings()
end

local function cutscenePayload(scene, settings)
  local points = scene.camera_points
  if type(points) ~= 'table' then
    points = MySQL.query.await([[SELECT id,label,message,sort_order,x,y,z,heading,fov,hold_duration,transition_duration
      FROM arachnid_storyteller_camera_points WHERE scene_id=? ORDER BY sort_order ASC,id ASC]], { scene.id }) or {}
  end
  if #points < 1 or #points > Config.Cutscenes.maxPoints then return nil, 'This scene needs a valid camera rail before it can play.' end
  local normalized, reason = normalizedCutsceneSettings(settings or scene.cutscene_settings)
  if not normalized then return nil, reason end
  local duration = 0
  for _, point in ipairs(points) do
    point.x, point.y, point.z = tonumber(point.x), tonumber(point.y), tonumber(point.z)
    point.heading = tonumber(point.heading) or 0
    point.fov = boundedNumber(point.fov, Config.Cutscenes.minFov, Config.Cutscenes.maxFov) or normalized.defaultFov
    point.hold_duration = boundedNumber(point.hold_duration, 0, 300) or 0
    point.transition_duration = boundedNumber(point.transition_duration, 0, 60) or 0
    duration = duration + point.hold_duration
    if point ~= points[#points] then duration = duration + point.transition_duration end
  end
  if duration <= 0 then duration = 0.1 end
  if duration > Config.Cutscenes.maxDuration then return nil, 'This camera rail is longer than the configured cutscene limit.' end
  return { sceneId = scene.id, title = scene.title, points = points, settings = normalized, duration = duration }
end

local function actorName(src)
  return (GetPlayerName(src) or ('Storyteller #' .. tostring(src))):sub(1, 100)
end

local function logAction(src, action)
  local identifier = GetPlayerIdentifierByType(src, 'license') or GetPlayerIdentifier(src, 0) or tostring(src)
  MySQL.insert('INSERT INTO arachnid_storyteller_audit (actor_name,actor_identifier,action) VALUES (?,?,?)', {
    actorName(src), identifier, action:sub(1, 255)
  })
  print(('[arachnid_storyteller] %s (%s): %s'):format(actorName(src), src, action))
end

local function currentPosition(src)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil end
  local position = GetEntityCoords(ped)
  if not position then return nil end
  return {
    x = math.floor(position.x * 100) / 100,
    y = math.floor(position.y * 100) / 100,
    z = math.floor(position.z * 100) / 100
  }
end

local function storyExists(id)
  local rows = MySQL.query.await('SELECT id FROM arachnid_storyteller_stories WHERE id=? LIMIT 1', { id })
  return type(rows) == 'table' and rows[1] ~= nil
end

local function sceneRecord(id)
  local rows = MySQL.query.await([[SELECT scenes.id,scenes.story_id
    FROM arachnid_storyteller_scenes AS scenes WHERE scenes.id=? LIMIT 1]], { id })
  return type(rows) == 'table' and rows[1] or nil
end

local function onlinePlayers()
  local players = {}
  for _, rawId in ipairs(GetPlayers()) do
    local id = tonumber(rawId)
    if id and GetPlayerName(rawId) then
      players[#players + 1] = { id = id, name = GetPlayerName(rawId) }
    end
  end
  table.sort(players, function(left, right) return left.id < right.id end)
  return players
end

local function areaRecord(id)
  local rows = MySQL.query.await([[SELECT id,label,shape,x,y,z,radius,width,depth,height
    FROM arachnid_storyteller_areas WHERE id=? LIMIT 1]], { id })
  return type(rows) == 'table' and rows[1] or nil
end

local function teleportRecord(id, storyId)
  local rows = MySQL.query.await([[SELECT id,story_id,label,x,y,z,heading
    FROM arachnid_storyteller_teleports WHERE id=? AND story_id=? LIMIT 1]], { id, storyId })
  return type(rows) == 'table' and rows[1] or nil
end

local function areaContains(area, position)
  if not area or not position then return false end
  local x, y, z = tonumber(area.x), tonumber(area.y), tonumber(area.z)
  if not x or not y or not z or x ~= x or y ~= y or z ~= z then return false end
  local dx, dy, dz = position.x - x, position.y - y, position.z - z
  if area.shape == 'sphere' then
    local radius = tonumber(area.radius) or 0
    return (dx * dx) + (dy * dy) + (dz * dz) <= radius * radius
  end
  if area.shape ~= 'box' then return false end
  return math.abs(dx) <= (tonumber(area.width) or 0) / 2
    and math.abs(dy) <= (tonumber(area.depth) or 0) / 2
    and math.abs(dz) <= (tonumber(area.height) or 0) / 2
end

local flowNodeTypes = {
  start = true, scene = true, delay = true, branch = true, random_branch = true,
  set_variable = true, add_variable = true, subtract_variable = true, objective = true,
  complete_objective = true, fail_objective = true, wait_objective = true,
  wait_area = true, wait_all_in_area = true, wait_area_empty = true,
  check_player_count = true, check_job = true, check_entity_alive = true,
  and_node = true, or_node = true, not_node = true,
  play_cutscene = true, wait_cutscene = true, stop_cutscene = true,
  spawn_npc = true, spawn_npc_group = true, remove_npc = true,
  wait_npc_death = true, wait_npcs_dead = true, make_npc_hostile = true,
  set_npc_target = true, patrol_route = true, stop_patrol = true, spawn_prop = true, delete_prop = true,
  door_open = true, door_close = true, door_lock = true, door_unlock = true,
  entity_enable = true, entity_disable = true, trigger_entity = true,
  play_sound = true, stop_sound = true, screen_fade = true,
  announcement = true, subtitle = true, screen_shake = true,
  ['end'] = true,
  send_message = true, freeze_players = true, unfreeze_players = true, set_health = true,
  set_armor = true, give_weapon = true, strip_weapon = true, strip_all_weapons = true,
  teleport_players = true, kill_players = true, respawn_players = true, change_job = true
}
local flowOutputs = {
  start = { next = true }, scene = { next = true }, delay = { next = true },
  branch = { ['true'] = true, ['false'] = true }, random_branch = { success = true, failure = true },
  set_variable = { next = true }, add_variable = { next = true }, subtract_variable = { next = true },
  objective = { next = true }, wait_objective = { completed = true, failed = true },
  complete_objective = { next = true }, fail_objective = { next = true },
  wait_area = { next = true }, wait_all_in_area = { next = true }, wait_area_empty = { next = true },
  check_player_count = { ['true'] = true, ['false'] = true }, check_job = { ['true'] = true, ['false'] = true },
  check_entity_alive = { ['true'] = true, ['false'] = true },
  and_node = { next = true }, or_node = { next = true }, not_node = { next = true },
  play_cutscene = { next = true }, wait_cutscene = { next = true }, stop_cutscene = { next = true },
  spawn_npc = { next = true }, spawn_npc_group = { next = true }, remove_npc = { next = true },
  wait_npc_death = { next = true }, wait_npcs_dead = { next = true }, make_npc_hostile = { next = true },
  set_npc_target = { next = true }, patrol_route = { next = true }, stop_patrol = { next = true }, spawn_prop = { next = true }, delete_prop = { next = true },
  door_open = { next = true }, door_close = { next = true }, door_lock = { next = true }, door_unlock = { next = true },
  entity_enable = { next = true }, entity_disable = { next = true }, trigger_entity = { next = true },
  play_sound = { next = true }, stop_sound = { next = true }, screen_fade = { next = true },
  announcement = { next = true }, subtitle = { next = true }, screen_shake = { next = true },
  ['end'] = {},
  send_message = { next = true }, freeze_players = { next = true }, unfreeze_players = { next = true },
  set_health = { next = true }, set_armor = { next = true }, give_weapon = { next = true },
  strip_weapon = { next = true }, strip_all_weapons = { next = true }, teleport_players = { next = true },
  kill_players = { next = true }, respawn_players = { next = true }, change_job = { next = true }
}
local flowOperators = { ['=='] = true, ['~='] = true, ['!='] = true, ['>'] = true, ['<'] = true, ['>='] = true, ['<='] = true }
local flowActionSettings = {
  send_message = 'sendMessage', freeze_players = 'freeze', unfreeze_players = 'unfreeze',
  set_health = 'health', set_armor = 'armor', give_weapon = 'giveWeapon', strip_weapon = 'removeWeapon',
  strip_all_weapons = 'stripAllWeapons', teleport_players = 'teleport', kill_players = 'kill',
  respawn_players = 'respawn', change_job = 'changeJob'
}
local flowVorpActions = { respawn_players = true, change_job = true }
local flowFeatureNodes = {
  cutscenes = { play_cutscene = true, wait_cutscene = true, stop_cutscene = true },
  encounters = {
    spawn_npc = true, spawn_npc_group = true, remove_npc = true, wait_npc_death = true,
    wait_npcs_dead = true, make_npc_hostile = true, set_npc_target = true, patrol_route = true, stop_patrol = true,
    spawn_prop = true, delete_prop = true
  },
  world = { check_entity_alive = true, door_open = true, door_close = true, door_lock = true, door_unlock = true, entity_enable = true, entity_disable = true, trigger_entity = true },
  effects = { play_sound = true, stop_sound = true, screen_fade = true, announcement = true, subtitle = true, screen_shake = true }
}
local flowInputPorts = { and_node = { a = true, b = true }, or_node = { a = true, b = true } }
local flowWorldActions = {
  door_open = 'open', door_close = 'close', door_lock = 'lock', door_unlock = 'unlock',
  entity_enable = 'enable', entity_disable = 'disable', trigger_entity = 'trigger'
}
local configuredWorldTarget
local applyWorldAction

local function getVorpCore()
  if GetResourceState('vorp_core') ~= 'started' then return nil, 'vorp_core is not started.' end
  local ok, core = pcall(function() return exports['vorp_core']:GetCore() end)
  if not ok or type(core) ~= 'table' then return nil, 'VORP Core API is unavailable.' end
  return core
end

local function isDenseArray(value, maximum)
  if type(value) ~= 'table' then return false end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return false end
    count = count + 1
    if count > maximum then return false end
  end
  return count == #value
end

local function variableName(value)
  return type(value) == 'string' and #value <= 32 and value:match('^[%a_][%w_]*$') ~= nil
end

local function validateFlowValue(kind, value)
  if kind == 'number' then
    local number = boundedNumber(value, -Config.Flow.maxVariableNumber, Config.Flow.maxVariableNumber)
    if number == nil then return nil end
    return number
  end
  if kind == 'text' then
    if type(value) ~= 'string' or #value > 1000 then return nil end
    return value
  end
  if kind == 'boolean' and type(value) == 'boolean' then return value end
  return nil
end

local function allowedWeapon(name)
  local weapons = type(Config.PlayerActions.weapons) == 'table' and Config.PlayerActions.weapons or {}
  local entry = type(name) == 'string' and weapons[name] or nil
  if type(entry) ~= 'table' then return nil end
  local configuredMax = positiveInteger(entry.maxAmmo)
  local serverMax = positiveInteger(Config.PlayerActions.maxAmmo) or 1000
  local maxAmmo = configuredMax and math.min(configuredMax, serverMax) or nil
  local defaultAmmo = tonumber(entry.defaultAmmo) or 0
  if not maxAmmo or defaultAmmo < 0 or defaultAmmo > maxAmmo then return nil end
  return entry, maxAmmo, defaultAmmo
end

local function allowedJob(name, grade)
  local jobs = type(Config.PlayerActions.jobs) == 'table' and Config.PlayerActions.jobs or {}
  local entry = type(name) == 'string' and jobs[name] or nil
  if type(entry) ~= 'table' or type(entry.grades) ~= 'table' then return nil end
  local numericGrade = tonumber(grade)
  if not numericGrade or numericGrade % 1 ~= 0 or numericGrade < 0 then return nil end
  local found = false
  for key, value in pairs(entry.grades) do
    if tonumber(key) == numericGrade or tonumber(value) == numericGrade then found = true break end
  end
  if not found then return nil end
  return entry
end

local function allowedEncounterModel(kind, model)
  local config = Config.Encounters or {}
  local list = kind == 'ped' and config.pedModels or config.propModels
  local entry = type(list) == 'table' and type(model) == 'string' and list[model] or nil
  if entry == true then entry = {} end
  if type(entry) ~= 'table' or #model < 1 or #model > 100 then return nil end
  return entry
end

local function allowedEncounterWeapon(name)
  local weapons = type(Config.Encounters.weapons) == 'table' and Config.Encounters.weapons or {}
  local entry = type(name) == 'string' and weapons[name] or nil
  if type(entry) ~= 'table' then return nil end
  local ammo = boundedNumber(entry.ammo or 60, 1, Config.Encounters.maxWeaponAmmo or 1000)
  if ammo == nil or ammo % 1 ~= 0 then return nil end
  return { name = name, label = cleanText(entry.label or name, 100, true) or name, ammo = ammo }
end

local function encounterLoadout(modelEntry)
  local raw = type(modelEntry) == 'table' and modelEntry.weapons or nil
  if raw == nil then return {} end
  if not isDenseArray(raw, 16) then return nil, 'The configured NPC weapon loadout must be a list of allowlisted weapons.' end
  local result, seen = {}, {}
  for _, name in ipairs(raw) do
    local weapon = allowedEncounterWeapon(name)
    if not weapon or seen[name] then return nil, 'The NPC loadout contains a missing or repeated weapon allowlist entry.' end
    seen[name] = true
    result[#result + 1] = weapon
  end
  return result
end

local function maxPedHealth(entry)
  local configured = type(entry) == 'table' and tonumber(entry.maxHealth) or nil
  local serverLimit = tonumber(Config.Encounters.maxNpcHealth) or 1000
  if not configured then return serverLimit end
  return math.max(1, math.min(serverLimit, configured))
end

local function allowedEffectSound(soundId)
  local sounds = type(Config.Effects.sounds) == 'table' and Config.Effects.sounds or {}
  local entry = type(soundId) == 'string' and sounds[soundId] or nil
  if type(entry) ~= 'table' or type(entry.name) ~= 'string' or type(entry.set) ~= 'string' then return nil end
  if not entry.name:match('^[%w_%-]+$') or not entry.set:match('^[%w_%-]+$') then return nil end
  return entry
end

local function normalizeEffectData(kind, raw)
  raw = type(raw) == 'table' and raw or {}
  local data = {}
  if kind == 'play_sound' or kind == 'stop_sound' then
    local soundId = type(raw.soundId) == 'string' and raw.soundId or ''
    if not allowedEffectSound(soundId) then return nil, 'Choose an owner-allowlisted sound.' end
    data.soundId = soundId
    if kind == 'play_sound' then
      data.volume = boundedNumber(raw.volume == nil and 1 or raw.volume, 0, Config.Effects.maxVolume)
      data.pitch = boundedNumber(raw.pitch == nil and 100 or raw.pitch, Config.Effects.minPitch, Config.Effects.maxPitch)
      if data.volume == nil or data.pitch == nil then return nil, 'Sound volume or pitch exceeds the configured limits.' end
    end
  elseif kind == 'screen_fade' then
    local direction = raw.direction == 'out' and 'out' or raw.direction == 'in' and 'in' or nil
    data.duration = boundedNumber(raw.duration == nil and 1 or raw.duration, 0, Config.Effects.maxDurationSeconds)
    if not direction or data.duration == nil then return nil, 'Screen fade direction or duration is invalid.' end
    data.direction = direction
  elseif kind == 'announcement' or kind == 'subtitle' then
    data.text = cleanText(raw.text or '', Config.Effects.maxMessageLength, true)
    data.duration = boundedNumber(raw.duration == nil and 5 or raw.duration, 1, Config.Effects.maxDurationSeconds)
    if not data.text or data.duration == nil then return nil, 'Effect text or duration is invalid.' end
  elseif kind == 'screen_shake' then
    data.amplitude = boundedNumber(raw.amplitude == nil and 1 or raw.amplitude, 0, Config.Effects.maxShakeAmplitude)
    data.frequency = boundedNumber(raw.frequency == nil and 1 or raw.frequency, 0, Config.Effects.maxShakeFrequency)
    data.duration = boundedNumber(raw.duration == nil and 2 or raw.duration, 1, Config.Effects.maxDurationSeconds)
    if data.amplitude == nil or data.frequency == nil or data.duration == nil then return nil, 'Screen shake values exceed the configured limits.' end
  else
    return nil, 'Unknown effect action.'
  end
  return data
end

local function validateFlowGraph(rawGraph, storyId, requireRunnable)
  if type(rawGraph) ~= 'table' or not isDenseArray(rawGraph.nodes, Config.Flow.maxNodes) or not isDenseArray(rawGraph.links, Config.Flow.maxLinks) then
    return nil, 'Flow graph must contain node and link lists.'
  end
  if #rawGraph.nodes > Config.Flow.maxNodes or #rawGraph.links > Config.Flow.maxLinks then
    return nil, ('Flow is limited to %d nodes and %d links.'):format(Config.Flow.maxNodes, Config.Flow.maxLinks)
  end
  local scenes = MySQL.query.await('SELECT id FROM arachnid_storyteller_scenes WHERE story_id=?', { storyId }) or {}
  local sceneIds = {}
  for _, row in ipairs(scenes) do sceneIds[tostring(row.id)] = true end
  local areas = MySQL.query.await('SELECT id,label,shape,x,y,z,radius,width,depth,height FROM arachnid_storyteller_areas') or {}
  local areaById = {}
  for _, area in ipairs(areas) do areaById[tostring(area.id)] = area end
  local teleportRows = MySQL.query.await([[SELECT id,story_id,label,x,y,z,heading FROM arachnid_storyteller_teleports WHERE story_id=?]], { storyId }) or {}
  local teleportById = {}
  for _, marker in ipairs(teleportRows) do teleportById[tostring(marker.id)] = marker end
  local railRows = MySQL.query.await([[SELECT scene_id,id,label,message,sort_order,x,y,z,heading,fov,hold_duration,transition_duration
    FROM arachnid_storyteller_camera_points WHERE scene_id IN
      (SELECT id FROM arachnid_storyteller_scenes WHERE story_id=?) ORDER BY scene_id,sort_order,id]], { storyId }) or {}
  local cutscenePoints = {}
  for _, point in ipairs(railRows) do
    cutscenePoints[tostring(point.scene_id)] = cutscenePoints[tostring(point.scene_id)] or {}
    cutscenePoints[tostring(point.scene_id)][#cutscenePoints[tostring(point.scene_id)] + 1] = point
  end
  local cutsceneRows = MySQL.query.await([[SELECT settings.scene_id,settings.settings_json FROM arachnid_storyteller_cutscene_settings AS settings
    INNER JOIN arachnid_storyteller_scenes AS scenes ON scenes.id=settings.scene_id WHERE scenes.story_id=?]], { storyId }) or {}
  local cutsceneSettings = {}
  for _, row in ipairs(cutsceneRows) do
    local ok, decoded = pcall(json.decode, row.settings_json)
    if ok and type(decoded) == 'table' then cutsceneSettings[tostring(row.scene_id)] = normalizedCutsceneSettings(decoded) end
  end
  local spawnRows = MySQL.query.await([[SELECT id,story_id,label,kind,x,y,z,heading FROM arachnid_storyteller_spawn_points WHERE story_id=?]], { storyId }) or {}
  local spawnById = {}
  for _, point in ipairs(spawnRows) do spawnById[tostring(point.id)] = point end

  local graph = { nodes = {}, links = {} }
  local nodes, starts, ends, hasPlayerActions, hasVorpActions, hasRespawn, hasChangeJob, hasVorpChecks = {}, 0, 0, false, false, false, false, false
  local featureFamilies = { cutscenes = false, encounters = false, world = false, effects = false }
  for _, rawNode in ipairs(rawGraph.nodes) do
    if type(rawNode) ~= 'table' or type(rawNode.id) ~= 'string' or #rawNode.id < 1 or #rawNode.id > 64 or
      not flowNodeTypes[rawNode.type] or nodes[rawNode.id] then
      return nil, 'Flow contains an invalid or duplicate node.'
    end
    local x = boundedNumber(rawNode.x, 0, 100000) or 80
    local y = boundedNumber(rawNode.y, 0, 100000) or 80
    local rawData = type(rawNode.data) == 'table' and rawNode.data or {}
    local data = {}
    local kind = rawNode.type
    if kind == 'scene' then
      local sceneId = positiveInteger(rawData.sceneId)
      if not sceneId or not sceneIds[tostring(sceneId)] then return nil, 'A scene node references a missing scene in this story.' end
      data.sceneId = sceneId
    elseif kind == 'delay' then
      local seconds = boundedNumber(rawData.seconds, 0, Config.Flow.maxDelaySeconds)
      if seconds == nil then return nil, 'Delay nodes must use a duration from 0 to ' .. Config.Flow.maxDelaySeconds .. ' seconds.' end
      data.seconds = seconds
    elseif kind == 'branch' then
      if not variableName(rawData.variable) or not flowOperators[rawData.operator] then return nil, 'Branch nodes need a valid variable and comparison operator.' end
      local value = validateFlowValue(rawData.valueType, rawData.value)
      if value == nil then return nil, 'Branch comparison value does not match its selected type.' end
      if (rawData.operator == '>' or rawData.operator == '<' or rawData.operator == '>=' or rawData.operator == '<=') and rawData.valueType ~= 'number' then
        return nil, 'Ordered comparisons require a number value.'
      end
      data.variable, data.operator, data.valueType, data.value = rawData.variable, rawData.operator == '~=' and '!=' or rawData.operator, rawData.valueType, value
    elseif kind == 'random_branch' then
      local chance = boundedNumber(rawData.chance, 0, 100)
      if chance == nil then return nil, 'Random branch chance must be from 0 to 100 percent.' end
      data.chance = chance
    elseif kind == 'set_variable' then
      if not variableName(rawData.variable) then return nil, 'Set variable nodes need a variable name.' end
      local value = validateFlowValue(rawData.valueType, rawData.value)
      if value == nil then return nil, 'Set variable value does not match its selected type.' end
      data.variable, data.valueType, data.value = rawData.variable, rawData.valueType, value
    elseif kind == 'add_variable' or kind == 'subtract_variable' then
      local amount = boundedNumber(rawData.amount, -Config.Flow.maxVariableNumber, Config.Flow.maxVariableNumber)
      if not variableName(rawData.variable) or amount == nil then return nil, 'Add/subtract nodes need a valid variable name and numeric amount.' end
      data.variable, data.amount = rawData.variable, amount
    elseif kind == 'objective' then
      local text = cleanText(rawData.text or '', Config.Limits.activeObjective, true)
      if not text then return nil, 'Objective nodes need objective text.' end
      data.text = text
    elseif kind == 'wait_area' or kind == 'wait_all_in_area' or kind == 'wait_area_empty' then
      local areaId = positiveInteger(rawData.areaId)
      if not areaId or not areaById[tostring(areaId)] then return nil, 'An area wait references a missing saved area.' end
      data.areaId = areaId
    elseif kind == 'check_player_count' then
      local operator = rawData.operator
      local count = boundedNumber(rawData.count, 0, Config.Session.maxParticipants)
      if not flowOperators[operator] or count == nil or count % 1 ~= 0 then return nil, 'Player count checks need a supported operator and whole number.' end
      data.operator, data.count = operator == '~=' and '!=' or operator, count
    elseif kind == 'check_job' then
      if type(rawData.jobName) ~= 'string' or #rawData.jobName < 1 or #rawData.jobName > 64 then return nil, 'Choose an allowlisted VORP job to check.' end
      local jobs = type(Config.PlayerActions.jobs) == 'table' and Config.PlayerActions.jobs or {}
      if requireRunnable and type(jobs[rawData.jobName]) ~= 'table' then return nil, 'That job is not in the server allowlist.' end
      data.jobName = rawData.jobName
      hasVorpChecks = true
    elseif kind == 'check_entity_alive' then
      local targetId = type(rawData.targetId) == 'string' and rawData.targetId or ''
      if #targetId < 1 or #targetId > 64 or type(Config.World.targets) ~= 'table' or type(Config.World.targets[targetId]) ~= 'table' then
        return nil, 'Choose a registered world target for the entity check.'
      end
      data.targetId = targetId
    elseif flowWorldActions[kind] then
      local targetId = type(rawData.targetId) == 'string' and rawData.targetId or ''
      local target = configuredWorldTarget(targetId)
      local action = flowWorldActions[kind]
      if #targetId < 1 or #targetId > 64 or type(target) ~= 'table' or type(target.actions) ~= 'table' or target.actions[action] ~= true then
        return nil, 'Choose a registered world target with this action explicitly enabled.'
      end
      if type(target.restoreOnSessionEnd) ~= 'boolean' then return nil, 'Each registered world target needs a restoreOnSessionEnd true/false policy.' end
      if (action == 'open' or action == 'close' or action == 'lock' or action == 'unlock') and target.kind ~= 'door' then
        return nil, 'Door operations require a target configured with kind = door.'
      end
      if (action == 'enable' or action == 'disable') and target.kind ~= 'entity' then
        return nil, 'Enable/disable operations require a target configured with kind = entity.'
      end
      if action == 'trigger' and (type(target.triggerEvent) ~= 'string' or target.triggerEvent == '' or target.restoreOnSessionEnd) then
        return nil, 'Trigger targets need an owner-configured event and a persistent target policy.'
      end
      data.targetId = targetId
      if requireRunnable and target.kind == 'door' and (type(DoorSystemGetDoorState) ~= 'function' or type(DoorSystemGetOpenRatio) ~= 'function' or type(DoorSystemSetDoorState) ~= 'function' or type(DoorSystemSetOpenRatio) ~= 'function') then
        return nil, 'RedM door-system state controls are unavailable on this server.'
      end
    elseif kind == 'play_cutscene' then
      local sceneId = positiveInteger(rawData.sceneId)
      if not sceneId or not sceneIds[tostring(sceneId)] then return nil, 'A cutscene node references a missing scene in this story.' end
      if #(cutscenePoints[tostring(sceneId)] or {}) < 1 then return nil, 'A cutscene node requires a scene with a saved camera rail.' end
      if #cutscenePoints[tostring(sceneId)] > Config.Cutscenes.maxPoints then return nil, 'The scene camera rail exceeds the configured cutscene point limit.' end
      data.sceneId = sceneId
    elseif flowFeatureNodes.cutscenes[kind] then
      -- Wait and Stop use only their execution ports.
    elseif kind == 'spawn_npc' or kind == 'spawn_npc_group' then
      local model = type(rawData.model) == 'string' and rawData.model or ''
      local markerId = positiveInteger(rawData.spawnPointId)
      local marker = markerId and spawnById[tostring(markerId)] or nil
      local modelEntry = allowedEncounterModel('ped', model)
      local health = boundedNumber(rawData.health or 150, 1, maxPedHealth(modelEntry))
      if not modelEntry or not marker or marker.kind ~= 'npc' or health == nil or health % 1 ~= 0 then
        return nil, 'NPC nodes need an allowlisted model, valid NPC spawn marker, and whole-number health within the server limit.'
      end
      data.model, data.spawnPointId, data.health = model, markerId, health
      if kind == 'spawn_npc_group' then
        local count = boundedNumber(rawData.count, 1, Config.Encounters.maxGroupCount)
        if count == nil or count % 1 ~= 0 then return nil, 'NPC group count exceeds the configured limit.' end
        data.count = count
      end
      if requireRunnable and type(CreatePed) ~= 'function' then return nil, 'Server ped creation is unavailable; verify OneSync and RedM entity support.' end
    elseif kind == 'spawn_prop' then
      local model = type(rawData.model) == 'string' and rawData.model or ''
      local markerId = positiveInteger(rawData.spawnPointId)
      local marker = markerId and spawnById[tostring(markerId)] or nil
      if not allowedEncounterModel('prop', model) or not marker or marker.kind ~= 'prop' then
        return nil, 'Prop nodes need an allowlisted model and a valid prop spawn marker.'
      end
      data.model, data.spawnPointId = model, markerId
      if requireRunnable and type(CreateObjectNoOffset) ~= 'function' then return nil, 'Server object creation is unavailable; verify OneSync and RedM entity support.' end
    elseif kind == 'set_npc_target' then
      local target = rawData.target == nil and 'random' or rawData.target
      if target ~= 'all' and target ~= 'random' then return nil, 'NPC target mode must be all or random.' end
      data.target = target
    elseif kind == 'patrol_route' then
      if not isDenseArray(rawData.markerIds, 20) or #rawData.markerIds < 2 then return nil, 'A patrol route needs at least two saved waypoint markers.' end
      local route = {}
      for _, rawMarkerId in ipairs(rawData.markerIds) do
        local markerId = positiveInteger(rawMarkerId)
        local marker = markerId and spawnById[tostring(markerId)] or nil
        if not marker or marker.kind ~= 'patrol' then return nil, 'A patrol route references a missing waypoint marker.' end
        route[#route + 1] = markerId
      end
      local speed = boundedNumber(rawData.speed or Config.Encounters.defaultPatrolSpeed, Config.Encounters.minPatrolSpeed, Config.Encounters.maxPatrolSpeed)
      local waitSeconds = boundedNumber(rawData.waitSeconds == nil and 3 or rawData.waitSeconds, 0, Config.Encounters.maxPatrolWaitSeconds)
      if speed == nil or waitSeconds == nil then return nil, 'Patrol pace or waypoint dwell time exceeds the server limits.' end
      data.markerIds, data.speed, data.waitSeconds = route, speed, waitSeconds
    elseif flowFeatureNodes.effects[kind] then
      local normalized, reason = normalizeEffectData(kind, rawData)
      if not normalized then return nil, reason end
      data = normalized
    elseif flowFeatureNodes.encounters[kind] then
      -- Remove, wait, and hostility nodes do not need additional settings.
    elseif flowActionSettings[kind] then
      hasPlayerActions = true
      if flowVorpActions[kind] then hasVorpActions = true end
      if kind == 'respawn_players' then hasRespawn = true end
      if kind == 'change_job' then hasChangeJob = true end
      local enabledActions = type(Config.PlayerActions.enabled) == 'table' and Config.PlayerActions.enabled or {}
      if requireRunnable and not enabledActions[flowActionSettings[kind]] then
        return nil, ('The %s action is disabled by the server owner.'):format(kind:gsub('_', ' '))
      end
      local target = rawData.target == nil and 'all' or rawData.target
      if target ~= 'all' and target ~= 'random' then return nil, 'Player action target must be all or random.' end
      data.target = target
      if kind == 'send_message' then
        local message = cleanText(rawData.message or '', Config.PlayerActions.maxMessageLength, true)
        if not message then return nil, 'Send Message nodes need non-empty message text.' end
        data.message = message
      elseif kind == 'set_health' then
        local health = boundedNumber(rawData.health, 1, Config.PlayerActions.maxHealth)
        if health == nil or health % 1 ~= 0 then return nil, ('Health must be a whole number from 1 to %s.'):format(Config.PlayerActions.maxHealth) end
        data.health = health
      elseif kind == 'set_armor' then
        local armor = boundedNumber(rawData.armor, 0, Config.PlayerActions.maxArmor)
        if armor == nil or armor % 1 ~= 0 then return nil, ('Armor must be a whole number from 0 to %s.'):format(Config.PlayerActions.maxArmor) end
        data.armor = armor
      elseif kind == 'give_weapon' or kind == 'strip_weapon' then
        if type(rawData.weapon) ~= 'string' or #rawData.weapon < 1 or #rawData.weapon > 100 then return nil, 'Choose a configured weapon.' end
        data.weapon = rawData.weapon
        if requireRunnable and not allowedWeapon(data.weapon) then return nil, 'That weapon is not in the server allowlist.' end
        if kind == 'give_weapon' then
          local weapon, maxAmmo, defaultAmmo = allowedWeapon(data.weapon)
          if not weapon and requireRunnable then return nil, 'That weapon is not in the server allowlist.' end
          local ammo = rawData.ammo == nil and (defaultAmmo or 0) or boundedNumber(rawData.ammo, 0, maxAmmo or Config.PlayerActions.maxAmmo)
          if ammo == nil or ammo % 1 ~= 0 or ammo > (maxAmmo or Config.PlayerActions.maxAmmo) then return nil, 'Weapon ammunition exceeds the configured limit.' end
          data.ammo = ammo
        end
      elseif kind == 'teleport_players' then
        local markerId = positiveInteger(rawData.markerId)
        if not markerId or not teleportById[tostring(markerId)] then return nil, 'A teleport node references a missing marker in this story.' end
        data.markerId = markerId
      elseif kind == 'change_job' then
        if type(rawData.jobName) ~= 'string' or #rawData.jobName < 1 or #rawData.jobName > 64 then return nil, 'Choose a configured VORP job.' end
        local grade = tonumber(rawData.grade)
        local job = grade ~= nil and allowedJob(rawData.jobName, grade) or nil
        if requireRunnable and not job then return nil, 'That VORP job and grade are not in the server allowlist.' end
        if grade == nil or grade % 1 ~= 0 or grade < 0 then return nil, 'VORP job grade must be a non-negative whole number.' end
        data.jobName, data.grade = rawData.jobName, grade
      end
    end
    for family, nodeSet in pairs(flowFeatureNodes) do
      if nodeSet[kind] then
        featureFamilies[family] = true
        local familyConfig = Config[family == 'cutscenes' and 'Cutscenes' or family == 'encounters' and 'Encounters' or family == 'world' and 'World' or 'Effects']
        if requireRunnable and (not familyConfig or familyConfig.enabled ~= true) then
          return nil, ('The %s feature family is disabled by the server owner.'):format(family)
        end
      end
    end
    local node = { id = rawNode.id, type = kind, x = x, y = y, data = data }
    nodes[node.id] = node
    graph.nodes[#graph.nodes + 1] = node
    if kind == 'start' then starts = starts + 1 end
    if kind == 'end' then ends = ends + 1 end
  end
  if starts > 1 then return nil, 'A flow can have only one Start node.' end
  local outgoing, incoming, adjacency, linkIds = {}, {}, {}, {}
  for _, rawLink in ipairs(rawGraph.links) do
    if type(rawLink) ~= 'table' or type(rawLink.id) ~= 'string' or #rawLink.id < 1 or #rawLink.id > 64 or linkIds[rawLink.id] or
      type(rawLink.fromNode) ~= 'string' or type(rawLink.toNode) ~= 'string' or type(rawLink.fromSocket) ~= 'string' or type(rawLink.toSocket) ~= 'string' then
      return nil, 'Flow contains an invalid connection.'
    end
    linkIds[rawLink.id] = true
    local from, to = nodes[rawLink.fromNode], nodes[rawLink.toNode]
    local inputAllowed = to and ((flowInputPorts[to.type] and flowInputPorts[to.type][rawLink.toSocket]) or
      (not flowInputPorts[to.type] and rawLink.toSocket == 'in'))
    if not from or not to or from.type == 'end' or not inputAllowed or to.type == 'start' or
      not flowOutputs[from.type][rawLink.fromSocket] then
      return nil, 'A flow connection uses a missing node or invalid port.'
    end
    local outputKey = rawLink.fromNode .. ':' .. rawLink.fromSocket
    local inputKey = rawLink.toNode .. ':' .. rawLink.toSocket
    if incoming[inputKey] then return nil, 'Each input port can have only one connection.' end
    outgoing[outputKey] = outgoing[outputKey] or {}
    outgoing[outputKey][#outgoing[outputKey] + 1] = { nodeId = rawLink.toNode, inputPort = rawLink.toSocket }
    incoming[inputKey] = true
    adjacency[rawLink.fromNode] = adjacency[rawLink.fromNode] or {}
    adjacency[rawLink.fromNode][#adjacency[rawLink.fromNode] + 1] = rawLink.toNode
    graph.links[#graph.links + 1] = {
      id = rawLink.id, fromNode = rawLink.fromNode, fromSocket = rawLink.fromSocket,
      toNode = rawLink.toNode, toSocket = rawLink.toSocket
    }
  end
  local marks = {}
  local function hasCycle(nodeId)
    if marks[nodeId] == 1 then return true end
    if marks[nodeId] == 2 then return false end
    marks[nodeId] = 1
    for _, nextId in ipairs(adjacency[nodeId] or {}) do if hasCycle(nextId) then return true end end
    marks[nodeId] = 2
    return false
  end
  for id in pairs(nodes) do if hasCycle(id) then return nil, 'Flow connections cannot contain cycles.' end end
  if requireRunnable then
    if #graph.nodes == 0 then return nil, 'This story has no flow graph.' end
    if starts ~= 1 then return nil, 'A flow must have exactly one Start node.' end
    if hasVorpActions or hasVorpChecks then
      local core, coreError = getVorpCore()
      if not core then return nil, coreError end
      if (hasRespawn and (type(core.Player) ~= 'table' or type(core.Player.Respawn) ~= 'function')) or
        ((hasChangeJob or hasVorpChecks) and type(core.getUser) ~= 'function') then
        return nil, 'The required VORP Player API is unavailable.'
      end
    end
    if ends == 0 then return nil, 'Add at least one reachable End node.' end
    local visited = {}
    local function visit(id)
      if visited[id] then return end
      visited[id] = true
      for _, nextId in ipairs(adjacency[id] or {}) do visit(nextId) end
    end
    local startId
    for id, node in pairs(nodes) do if node.type == 'start' then startId = id break end end
    visit(startId)
    for id, node in pairs(nodes) do
      if not visited[id] then return nil, 'Every saved node must be reachable from Start before the flow can run.' end
      for port in pairs(flowOutputs[node.type]) do
        if not outgoing[id .. ':' .. port] then return nil, ('Connect the %s output on node %s.'):format(port, id) end
      end
      if node.type ~= 'start' then
        if flowInputPorts[node.type] then
          for port in pairs(flowInputPorts[node.type]) do
            if not incoming[id .. ':' .. port] then return nil, ('Connect the %s input on node %s.'):format(port, id) end
          end
        elseif not incoming[id .. ':in'] then
          return nil, ('Connect an input to node %s.'):format(id)
        end
      end
    end
  end
  return graph, nil, {
    nodes = nodes, outgoing = outgoing, areas = areaById, teleports = teleportById,
    hasPlayerActions = hasPlayerActions, hasVorpActions = hasVorpActions,
    hasVorpChecks = hasVorpChecks, featureFamilies = featureFamilies,
    cutscenePoints = cutscenePoints, cutsceneSettings = cutsceneSettings, spawnPoints = spawnById
  }
end

local function participantsInArea(area)
  local participants = {}
  for _, player in ipairs(onlinePlayers()) do
    local position = currentPosition(player.id)
    if areaContains(area, position) then
      participants[#participants + 1] = player.id
      if #participants > Config.Session.maxParticipants then return nil, 'Too many players are inside this area.' end
    end
  end
  if #participants == 0 then return nil, 'No online players are inside the selected area.' end
  return participants
end

local function validatedAudience(rawMode, rawIds, rawAreaId)
  local mode = rawMode == nil and 'all' or type(rawMode) == 'string' and rawMode:lower() or nil
  if not mode or (mode ~= 'all' and mode ~= 'selected' and mode ~= 'area') then
    return nil, 'Choose a valid session audience.'
  end
  if mode == 'all' then return { mode = 'all', participants = {} } end
  if mode == 'area' then
    local areaId = positiveInteger(rawAreaId)
    if not areaId then return nil, 'Choose a valid session area.' end
    local area = areaRecord(areaId)
    if not area then return nil, 'That session area no longer exists.' end
    local participants, reason = participantsInArea(area)
    if not participants then return nil, reason end
    return { mode = 'area', participants = participants, areaId = area.id, areaLabel = area.label }
  end
  if type(rawIds) ~= 'table' then return nil, 'Choose at least one online participant.' end
  local participants, seen = {}, {}
  for _, rawId in ipairs(rawIds) do
    local id = positiveInteger(rawId)
    if id and not seen[id] and GetPlayerName(id) then
      seen[id] = true
      participants[#participants + 1] = id
      if #participants > Config.Session.maxParticipants then
        return nil, 'Too many selected participants.'
      end
    end
  end
  if #participants == 0 then return nil, 'Choose at least one online participant.' end
  return { mode = 'selected', participants = participants }
end

local function isAudienceMember(session, src)
  if not session or not session.audience or session.audience.mode == 'all' then return true end
  for _, id in ipairs(session.audience.participants or {}) do
    if tonumber(id) == tonumber(src) then return true end
  end
  return false
end

local function sessionPayload(mode, session)
  local current = session or activeSession
  if not current then
    return { state = 'idle', mode = mode, duration = Config.Session.overlayDuration }
  end
  local scene = current.scenes[current.sceneIndex]
  return {
    state = 'active',
    mode = mode,
    duration = Config.Session.overlayDuration,
    story = { id = current.storyId, title = current.storyTitle },
    scene = scene and {
      id = scene.id,
      title = scene.title,
      objective = scene.objective,
      order = scene.sort_order,
      x = scene.x,
      y = scene.y,
      z = scene.z
    } or nil,
    objective = current.objective,
    encounters = {
      npcs = current.entities and #(current.entities.npcs or {}) or 0,
      props = current.entities and #(current.entities.props or {}) or 0
    },
    audience = {
      mode = current.audience and current.audience.mode or 'all',
      count = current.audience and current.audience.mode ~= 'all' and #(current.audience.participants or {}) or #GetPlayers(),
      areaLabel = current.audience and current.audience.areaLabel or nil
    },
    cutscene = current.cutscene and {
      sceneId = current.cutscene.sceneId,
      paused = current.cutscene.paused == true
    } or nil,
    startedAt = current.startedAt,
    startedBy = current.startedBy,
    flow = current.flowRuntime and {
      state = current.flowRuntime.paused and 'paused' or #current.flowRuntime.queue == 0 and #current.flowRuntime.waiters > 0 and 'waiting' or 'running',
      waiting = current.flowRuntime.waiters[1] and current.flowRuntime.waiters[1].kind or nil,
      nodeId = current.flowRuntime.queue[1] and current.flowRuntime.queue[1].nodeId or
        current.flowRuntime.waiters[1] and current.flowRuntime.waiters[1].nodeId or nil,
      error = current.flowRuntime.error
    } or nil
  }
end

local function activateSessionScene(index, actor)
  activeSession.sceneIndex = index
  local scene = activeSession.scenes[index]
  local text = scene and tostring(scene.objective or '') or ''
  activeSession.objective = {
    text = text,
    status = text ~= '' and 'active' or 'none',
    updatedAt = os.time(),
    updatedBy = actor
  }
  return scene
end

local function broadcastSession(mode, session)
  local current = session or activeSession
  local payload = mode == 'ended' and { state = 'idle', mode = mode, duration = Config.Session.overlayDuration } or sessionPayload(mode, current)
  if Config.Session.broadcastToPlayers then
    if current and current.audience and current.audience.mode ~= 'all' then
      for _, id in ipairs(current.audience.participants or {}) do
        if GetPlayerName(id) then TriggerClientEvent('arachnid_storyteller:session', id, payload) end
      end
    else
      TriggerClientEvent('arachnid_storyteller:session', -1, payload)
    end
  end
  for _, rawId in ipairs(GetPlayers()) do
    local id = tonumber(rawId)
    if id and canManage(id) and not isAudienceMember(current, id) then
      TriggerClientEvent('arachnid_storyteller:sessionAdmin', id, payload)
    end
  end
end

local function cleanupOwnedFreezes(runtimeId)
  for rawId, ownerRuntime in pairs(frozenByArachnid) do
    if runtimeId == nil or ownerRuntime == runtimeId then
      local id = tonumber(rawId)
      if id and GetPlayerName(id) then
        local ped = GetPlayerPed(id)
        if ped and ped ~= 0 then pcall(FreezeEntityPosition, ped, false) end
      end
      frozenByArachnid[rawId] = nil
    end
  end
end

local function stopSessionCutscene(session)
  if not session or not session.cutscene then return end
  local targets = {}
  if session.audience and session.audience.mode ~= 'all' then
    for _, id in ipairs(session.audience.participants or {}) do
      if GetPlayerName(id) then targets[#targets + 1] = tonumber(id) end
    end
  else
    for _, player in ipairs(onlinePlayers()) do targets[#targets + 1] = player.id end
  end
  for _, id in ipairs(targets) do TriggerClientEvent('arachnid_storyteller:cutsceneStop', id) end
  session.cutscene = nil
end

local function endActiveSession(mode, actor)
  if not activeSession then return end
  local ended = activeSession
  activeSession = nil
  stopSessionCutscene(ended)
  if stopSessionNpcOrders then stopSessionNpcOrders(ended) end
  cleanupSessionEncounters(ended, false)
  cleanupSessionWorld(ended)
  cleanupSessionEffects(ended)
  cleanupOwnedFreezes(ended.runtimeId)
  if actor then logAction(actor, ('Ended live session for story #%s: %s'):format(tostring(ended.storyId), ended.storyTitle:sub(1, 80))) end
  broadcastSession(mode or 'ended', ended)
end

local function flowRoute(runtime, nodeId, port)
  return runtime.outgoing[nodeId .. ':' .. port] or {}
end

local function flowEnqueueRoute(runtime, nodeId, port)
  for _, destination in ipairs(flowRoute(runtime, nodeId, port)) do
    runtime.queue[#runtime.queue + 1] = { nodeId = destination.nodeId, inputPort = destination.inputPort }
  end
end

local function flowAudiencePlayers(session)
  local output = {}
  if session.audience and session.audience.mode ~= 'all' then
    for _, id in ipairs(session.audience.participants or {}) do
      if GetPlayerName(id) then output[#output + 1] = tonumber(id) end
    end
  else
    for _, player in ipairs(onlinePlayers()) do output[#output + 1] = player.id end
  end
  return output
end

local function flowAreaSatisfied(session, area)
  for _, id in ipairs(flowAudiencePlayers(session)) do
    if areaContains(area, currentPosition(id)) then return true end
  end
  return false
end

local vorpCharacterFor

local function flowAreaCondition(session, area, condition)
  local players, inside = flowAudiencePlayers(session), 0
  for _, id in ipairs(players) do
    if areaContains(area, currentPosition(id)) then inside = inside + 1 end
  end
  if condition == 'any' then return inside > 0 end
  if condition == 'all' then return #players > 0 and inside == #players end
  if condition == 'empty' then return inside == 0 end
  return false
end

local function flowCountMatches(value, operator, expected)
  if operator == '==' then return value == expected end
  if operator == '!=' then return value ~= expected end
  if operator == '>' then return value > expected end
  if operator == '<' then return value < expected end
  if operator == '>=' then return value >= expected end
  if operator == '<=' then return value <= expected end
  return false
end

local function flowAudienceHasJob(session, jobName)
  local core = getVorpCore()
  if not core then return false end
  for _, id in ipairs(flowAudiencePlayers(session)) do
    local character = vorpCharacterFor(id, core)
    local job = character and (character.job or character.jobName or character.Job)
    if type(job) == 'table' then job = job.name or job.id end
    if type(job) == 'string' and job:lower() == tostring(jobName):lower() then return true end
  end
  return false
end

local function flowConfiguredEntityAlive(targetId)
  local target = type(Config.World.targets) == 'table' and Config.World.targets[targetId] or nil
  if type(target) ~= 'table' or type(target.coords) ~= 'table' then return false end
  local coords = target.coords
  local x, y, z = tonumber(coords.x), tonumber(coords.y), tonumber(coords.z)
  if not x or not y or not z then return false end
  local radius = boundedNumber(target.radius, 0.5, 100) or 5
  local model = target.model
  if type(model) == 'string' then model = GetHashKey(model) end
  if type(model) ~= 'number' then return false end
  local entity = 0
  if target.kind == 'ped' and type(GetClosestPed) == 'function' then
    local ok, result = pcall(GetClosestPed, x, y, z, radius, true, true, true, true, -1, model)
    if ok then entity = result end
  elseif type(GetClosestObjectOfType) == 'function' then
    local ok, result = pcall(GetClosestObjectOfType, x, y, z, radius, model, false, false, false)
    if ok then entity = result end
  end
  return entity and entity ~= 0 and type(DoesEntityExist) == 'function' and DoesEntityExist(entity)
    and (type(IsEntityDead) ~= 'function' or not IsEntityDead(entity))
end

local function encounterEntityExists(entity)
  if not entity or entity == 0 or type(DoesEntityExist) ~= 'function' then return false end
  local ok, exists = pcall(DoesEntityExist, entity)
  return ok and exists == true
end

local function encounterEntityDead(entity)
  if not encounterEntityExists(entity) then return true end
  if type(IsEntityDead) ~= 'function' then return false end
  local ok, dead = pcall(IsEntityDead, entity)
  return ok and dead == true
end

local function sessionEncounterList(session, kind)
  session.entities = session.entities or { npcs = {}, props = {} }
  session.entities.npcs = session.entities.npcs or {}
  session.entities.props = session.entities.props or {}
  return kind == 'npc' and session.entities.npcs or session.entities.props
end

local function encounterMarker(session, markerId, kind)
  local marker = session.spawnPoints and session.spawnPoints[tostring(markerId)] or nil
  if marker and marker.kind == kind then return marker end
  return nil
end

local function selectedEncounterNpcs(session, rawIds)
  local all = sessionEncounterList(session, 'npc')
  if rawIds == nil then return all end
  if not isDenseArray(rawIds, Config.Encounters.maxNpcsPerSession) then return nil, 'Select tracked NPC units in the active session.' end
  local byId = {}
  for _, npc in ipairs(all) do byId[tostring(npc.id)] = npc end
  local selected, seen = {}, {}
  for _, rawId in ipairs(rawIds) do
    if type(rawId) ~= 'string' or #rawId > 32 or seen[rawId] or not byId[rawId] then
      return nil, 'An NPC selection is invalid or no longer belongs to this session.'
    end
    seen[rawId] = true
    selected[#selected + 1] = byId[rawId]
  end
  if #selected == 0 then return nil, 'Select at least one tracked NPC.' end
  return selected
end

local function stopNpcOrder(npc, keepTarget)
  npc.orderToken = (npc.orderToken or 0) + 1
  if encounterEntityExists(npc.entity) then
    local clearTasks = type(ClearPedTasks) == 'function' and ClearPedTasks or ClearPedTasksImmediately
    if type(clearTasks) == 'function' then pcall(clearTasks, npc.entity) end
  end
  npc.order = { kind = 'hold', status = 'holding' }
  if not keepTarget then npc.targetId = nil; npc.autoTarget = false end
end

stopSessionNpcOrders = function(session)
  if not session or not session.entities or type(session.entities.npcs) ~= 'table' then return end
  for _, npc in ipairs(session.entities.npcs) do
    if npc.order then stopNpcOrder(npc, false) end
  end
end

local function npcHasEnabledWeapon(npc)
  local states = npc.weaponStates or {}
  if next(states) == nil then return true end
  for _, enabled in pairs(states) do if enabled then return true end end
  return false
end

local function taskNpcCombat(npc, targetId, allowReturnFire, automatic)
  if not encounterEntityExists(npc.entity) or encounterEntityDead(npc.entity) then return false, 'The selected NPC is no longer alive.' end
  if not targetId or not GetPlayerName(targetId) then return false, 'Choose a connected session participant as the target.' end
  if npc.stance == 'hold_fire' or (npc.stance == 'return_fire' and not allowReturnFire) then
    npc.targetId, npc.autoTarget = tonumber(targetId), automatic == true
    return true
  end
  if not npcHasEnabledWeapon(npc) then return false, 'All configured weapons are disabled for this NPC.' end
  local targetPed = GetPlayerPed(targetId)
  if not targetPed or targetPed == 0 or type(TaskCombatPed) ~= 'function' then return false, 'RedM combat orders are unavailable for this NPC.' end
  local ok, err = pcall(TaskCombatPed, npc.entity, targetPed, 0, 16)
  if not ok then return false, tostring(err) end
  if type(SetPedAsEnemy) == 'function' then pcall(SetPedAsEnemy, npc.entity, true) end
  npc.targetId, npc.autoTarget = tonumber(targetId), automatic == true
  npc.holdPosition = false
  npc.order = { kind = 'attack', status = 'engaging', targetId = tonumber(targetId) }
  return true
end

local function startNpcOrder(session, npc, route, settings)
  if type(TaskGoStraightToCoord) ~= 'function' then return false, 'RedM NPC movement orders are unavailable on this server.' end
  if not encounterEntityExists(npc.entity) or encounterEntityDead(npc.entity) then return false, 'The selected NPC is no longer alive.' end
  settings = settings or {}
  stopNpcOrder(npc, false)
  local token = npc.orderToken
  local copiedRoute = {}
  for _, marker in ipairs(route) do copiedRoute[#copiedRoute + 1] = marker end
  local orderKind = settings.loop and 'patrol' or 'move'
  local speed = boundedNumber(settings.speed or Config.Encounters.defaultPatrolSpeed, Config.Encounters.minPatrolSpeed, Config.Encounters.maxPatrolSpeed)
  local waitSeconds = boundedNumber(settings.waitSeconds == nil and 3 or settings.waitSeconds, 0, Config.Encounters.maxPatrolWaitSeconds)
  if not speed or not waitSeconds then return false, 'Movement pace or waypoint dwell time exceeds the configured limits.' end
  npc.order = { kind = orderKind, status = 'moving', markerId = copiedRoute[1].id, route = copiedRoute, routeIndex = 1, speed = speed, waitSeconds = waitSeconds }
  npc.order.targetCoords = { x = tonumber(copiedRoute[1].x), y = tonumber(copiedRoute[1].y), z = tonumber(copiedRoute[1].z) }
  npc.targetId, npc.holdPosition = nil, false

  CreateThread(function()
    local routeIndex = 1
    while activeSession == session and npc.orderToken == token and encounterEntityExists(npc.entity) and not encounterEntityDead(npc.entity) do
      local marker = copiedRoute[routeIndex]
      if not marker then break end
      npc.order.status, npc.order.routeIndex, npc.order.markerId = 'moving', routeIndex, marker.id
      npc.order.targetCoords = { x = tonumber(marker.x), y = tonumber(marker.y), z = tonumber(marker.z) }
      local callOk = pcall(TaskGoStraightToCoord, npc.entity, tonumber(marker.x) + 0.0, tonumber(marker.y) + 0.0,
        tonumber(marker.z) + 0.0, speed, -1, tonumber(marker.heading) or 0.0, tonumber(Config.Encounters.patrolArrivalRadius) or 2.0)
      if not callOk then
        npc.order.status = 'stuck'
        local clearTasks = type(ClearPedTasks) == 'function' and ClearPedTasks or ClearPedTasksImmediately
        if type(clearTasks) == 'function' then pcall(clearTasks, npc.entity) end
        return
      end
      local arrived, deadline = false, GetGameTimer() + math.floor((tonumber(Config.Encounters.patrolPathTimeoutSeconds) or 180) * 1000)
      while activeSession == session and npc.orderToken == token and GetGameTimer() < deadline do
        if not encounterEntityExists(npc.entity) or encounterEntityDead(npc.entity) then return end
        local okPosition, position = pcall(GetEntityCoords, npc.entity)
        if okPosition and position then
          local dx, dy, dz = position.x - tonumber(marker.x), position.y - tonumber(marker.y), position.z - tonumber(marker.z)
          if math.sqrt(dx * dx + dy * dy + dz * dz) <= (tonumber(Config.Encounters.patrolArrivalRadius) or 2.0) then
            arrived = true
            break
          end
        end
        Wait(500)
      end
      if activeSession ~= session or npc.orderToken ~= token then return end
      if not arrived then
        npc.order.status = 'stuck'
        local clearTasks = type(ClearPedTasks) == 'function' and ClearPedTasks or ClearPedTasksImmediately
        if type(clearTasks) == 'function' then pcall(clearTasks, npc.entity) end
        return
      end
      if not settings.loop and routeIndex >= #copiedRoute then
        npc.order = { kind = 'hold', status = 'holding', markerId = marker.id }
        return
      end
      npc.order.status = 'waiting'
      local dwellUntil = GetGameTimer() + math.floor(waitSeconds * 1000)
      while activeSession == session and npc.orderToken == token and GetGameTimer() < dwellUntil do Wait(250) end
      if activeSession ~= session or npc.orderToken ~= token then return end
      routeIndex = routeIndex % #copiedRoute + 1
    end
  end)
  return true
end

local function npcOrderWithinLimit(npc, route)
  local maxDistance = boundedNumber(Config.Rts.maxOrderDistance, 1, 100000) or 1000
  if type(GetEntityCoords) ~= 'function' or not encounterEntityExists(npc.entity) then
    return false, 'NPC position is unavailable for validating that order.'
  end
  local ok, position = pcall(GetEntityCoords, npc.entity)
  if not ok or not position then return false, 'NPC position is unavailable for validating that order.' end
  local from = { x = tonumber(position.x), y = tonumber(position.y), z = tonumber(position.z) }
  if not from.x or not from.y or not from.z then return false, 'NPC position is invalid.' end
  for _, marker in ipairs(route) do
    local to = { x = tonumber(marker.x), y = tonumber(marker.y), z = tonumber(marker.z) }
    if not to.x or not to.y or not to.z then return false, 'A saved waypoint has invalid coordinates.' end
    local dx, dy, dz = from.x - to.x, from.y - to.y, from.z - to.z
    if math.sqrt(dx * dx + dy * dy + dz * dz) > maxDistance then
      return false, ('The waypoint is farther than the configured RTS order limit (%s meters).'):format(tostring(maxDistance))
    end
    from = to
  end
  return true
end

local function deleteEncounterRecord(record)
  if not record or not encounterEntityExists(record.entity) then
    if record and record.entity then trackedEncounterEntities[tostring(record.entity)] = nil end
    return
  end
  if type(DeleteEntity) == 'function' then pcall(DeleteEntity, record.entity) end
  trackedEncounterEntities[tostring(record.entity)] = nil
end

cleanupSessionEncounters = function(session, force)
  if not session or not session.entities then return end
  if not force and Config.Encounters.cleanupOnEnd ~= true then return end
  for _, kind in ipairs({ 'npcs', 'props' }) do
    for index = #session.entities[kind], 1, -1 do
      deleteEncounterRecord(session.entities[kind][index])
      table.remove(session.entities[kind], index)
    end
  end
end

local function cleanupAllEncounterEntities()
  for _, entity in pairs(trackedEncounterEntities) do
    if encounterEntityExists(entity) and type(DeleteEntity) == 'function' then pcall(DeleteEntity, entity) end
  end
  trackedEncounterEntities = {}
end

local function createEncounterNpc(session, model, marker, health, offsetIndex)
  if type(CreatePed) ~= 'function' then return nil, 'Server ped creation is unavailable.' end
  local npcs = sessionEncounterList(session, 'npc')
  if #npcs >= Config.Encounters.maxNpcsPerSession then return nil, 'The session reached its configured NPC limit.' end
  local entry = allowedEncounterModel('ped', model)
  if not entry then return nil, 'The ped model is not in the server allowlist.' end
  local loadout, loadoutError = encounterLoadout(entry)
  if not loadout then return nil, loadoutError end
  if #loadout > 0 and type(GiveWeaponToPed) ~= 'function' then return nil, 'RedM NPC weapon control is unavailable on this server.' end
  local hash = type(model) == 'number' and model or GetHashKey(model)
  local index = tonumber(offsetIndex) or 1
  local angle = (index - 1) * 2.399963229728653
  local distance = index == 1 and 0 or math.min(3, 0.8 + index * 0.2)
  local x = tonumber(marker.x) + math.cos(angle) * distance
  local y = tonumber(marker.y) + math.sin(angle) * distance
  local ok, ped = pcall(CreatePed, 4, hash, x, y, tonumber(marker.z), tonumber(marker.heading) or 0, true, true)
  if not ok or not ped or ped == 0 then return nil, 'RedM could not create the configured ped.' end
  if type(SetEntityAsMissionEntity) == 'function' then pcall(SetEntityAsMissionEntity, ped, true, true) end
  if type(SetEntityOrphanMode) == 'function' then pcall(SetEntityOrphanMode, ped, 2) end
  if type(SetEntityMaxHealth) == 'function' then pcall(SetEntityMaxHealth, ped, health) end
  if type(SetEntityHealth) == 'function' then pcall(SetEntityHealth, ped, health) end
  session.nextNpcId = (session.nextNpcId or 0) + 1
  local record = {
    id = 'npc-' .. tostring(session.nextNpcId), entity = ped, model = model,
    groupId = session.runtimeId .. ':npc:' .. tostring(session.nextNpcId),
    stance = Config.Encounters.defaultStance or 'fire_at_will', weaponStates = {}
  }
  for _, weapon in ipairs(loadout) do
    local okWeapon = pcall(GiveWeaponToPed, ped, GetHashKey(weapon.name), weapon.ammo, false, true)
    if not okWeapon then
      if type(DeleteEntity) == 'function' then pcall(DeleteEntity, ped) end
      return nil, 'RedM could not apply the configured NPC weapon loadout.'
    end
    record.weaponStates[weapon.name] = true
  end
  npcs[#npcs + 1] = record
  trackedEncounterEntities[tostring(ped)] = ped
  return record
end

local function createEncounterProp(session, model, marker)
  if type(CreateObjectNoOffset) ~= 'function' then return nil, 'Server object creation is unavailable.' end
  local props = sessionEncounterList(session, 'prop')
  if #props >= Config.Encounters.maxPropsPerSession then return nil, 'The session reached its configured prop limit.' end
  if not allowedEncounterModel('prop', model) then return nil, 'The prop model is not in the server allowlist.' end
  local hash = type(model) == 'number' and model or GetHashKey(model)
  local ok, entity = pcall(CreateObjectNoOffset, hash, tonumber(marker.x), tonumber(marker.y), tonumber(marker.z), true, true, false)
  if not ok or not entity or entity == 0 then return nil, 'RedM could not create the configured prop.' end
  if type(SetEntityHeading) == 'function' then pcall(SetEntityHeading, entity, tonumber(marker.heading) or 0) end
  if type(SetEntityAsMissionEntity) == 'function' then pcall(SetEntityAsMissionEntity, entity, true, true) end
  if type(SetEntityOrphanMode) == 'function' then pcall(SetEntityOrphanMode, entity, 2) end
  local record = { entity = entity, model = model }
  props[#props + 1] = record
  trackedEncounterEntities[tostring(entity)] = entity
  return record
end

local function applyEncounterAction(session, kind, data)
  data = type(data) == 'table' and data or {}
  if kind == 'spawn_npc' or kind == 'spawn_npc_group' then
    local marker = encounterMarker(session, data.spawnPointId, 'npc')
    if not marker then return false, 'Choose a saved NPC spawn marker for this story.' end
    local count = kind == 'spawn_npc_group' and (tonumber(data.count) or 1) or 1
    if #sessionEncounterList(session, 'npc') + count > Config.Encounters.maxNpcsPerSession then return false, 'The NPC count exceeds the remaining session limit.' end
    local startingCount = #sessionEncounterList(session, 'npc')
    for index = 1, count do
      local record, reason = createEncounterNpc(session, data.model, marker, data.health or 150, startingCount + index)
      if not record then return false, reason end
    end
    return true
  elseif kind == 'spawn_prop' then
    local marker = encounterMarker(session, data.spawnPointId, 'prop')
    if not marker then return false, 'Choose a saved prop spawn marker for this story.' end
    local record, reason = createEncounterProp(session, data.model, marker)
    return record ~= nil, reason
  elseif kind == 'remove_npc' then
    local npcs = sessionEncounterList(session, 'npc')
    for index = #npcs, 1, -1 do deleteEncounterRecord(npcs[index]); table.remove(npcs, index) end
    return true
  elseif kind == 'delete_prop' then
    local props = sessionEncounterList(session, 'prop')
    for index = #props, 1, -1 do deleteEncounterRecord(props[index]); table.remove(props, index) end
    return true
  elseif kind == 'make_npc_hostile' or kind == 'set_npc_target' then
    local targets = flowAudiencePlayers(session)
    if #targets == 0 then return true end
    local npcs = sessionEncounterList(session, 'npc')
    local usedTargets = flowActionTargets(session, data.target == 'all' and 'all' or 'random')
    if #usedTargets == 0 then return true end
    for index, npc in ipairs(npcs) do
      if encounterEntityExists(npc.entity) and not encounterEntityDead(npc.entity) then
        local targetId = usedTargets[((index - 1) % #usedTargets) + 1]
        if kind == 'make_npc_hostile' then npc.stance = 'fire_at_will' end
        local applied, reason = taskNpcCombat(npc, targetId, false)
        if not applied then return false, reason end
      end
    end
    return true
  elseif kind == 'patrol_route' then
    local route = {}
    for _, markerId in ipairs(data.markerIds or {}) do
      local marker = encounterMarker(session, markerId, 'patrol')
      if not marker then return false, 'A patrol waypoint is missing from this story.' end
      route[#route + 1] = marker
    end
    if #route < 2 then return false, 'Patrol needs at least two saved waypoints.' end
    local waitSeconds = boundedNumber(data.waitSeconds == nil and 3 or data.waitSeconds, 0, Config.Encounters.maxPatrolWaitSeconds) or 3
    local speed = boundedNumber(data.speed or Config.Encounters.defaultPatrolSpeed, Config.Encounters.minPatrolSpeed, Config.Encounters.maxPatrolSpeed) or Config.Encounters.defaultPatrolSpeed
    for _, npc in ipairs(sessionEncounterList(session, 'npc')) do
      if encounterEntityExists(npc.entity) and not encounterEntityDead(npc.entity) then
        local ok, reason = startNpcOrder(session, npc, route, { loop = true, speed = speed, waitSeconds = waitSeconds })
        if not ok then return false, reason end
      end
    end
    return true
  elseif kind == 'stop_patrol' then
    local selected, reason = selectedEncounterNpcs(session, data.npcIds)
    if not selected then return false, reason end
    for _, npc in ipairs(selected) do stopNpcOrder(npc, false); npc.holdPosition = true end
    return true
  end
  return false, 'Unknown encounter action.'
end

local rtsStances = { fire_at_will = true, return_fire = true, hold_fire = true }

local function applyRtsCommand(session, action, data)
  local selected, selectionError = selectedEncounterNpcs(session, data.npcIds)
  if not selected then return false, selectionError end
  if action == 'rts_move' then
    local marker = encounterMarker(session, data.markerId, 'patrol')
    if not marker then return false, 'Move orders must target a saved patrol waypoint.' end
    local speed = boundedNumber(data.speed or Config.Encounters.defaultPatrolSpeed, Config.Encounters.minPatrolSpeed, Config.Encounters.maxPatrolSpeed)
    if not speed then return false, 'Movement pace is outside the configured limits.' end
    for _, npc in ipairs(selected) do
      local withinLimit, distanceError = npcOrderWithinLimit(npc, { marker })
      if not withinLimit then return false, distanceError end
    end
    for _, npc in ipairs(selected) do
      local ok, reason = startNpcOrder(session, npc, { marker }, { loop = false, speed = speed, waitSeconds = 0 })
      if not ok then return false, reason end
    end
  elseif action == 'rts_move_point' then
    local rawPosition = type(data.position) == 'table' and data.position or {}
    local x = boundedNumber(rawPosition.x, -100000, 100000)
    local y = boundedNumber(rawPosition.y, -100000, 100000)
    local z = boundedNumber(rawPosition.z, -100000, 100000)
    local speed = boundedNumber(data.speed or Config.Encounters.defaultPatrolSpeed, Config.Encounters.minPatrolSpeed, Config.Encounters.maxPatrolSpeed)
    if not x or not y or not z or not speed then return false, 'The RTS map destination or movement pace is invalid.' end
    local marker = { x = x, y = y, z = z, heading = 0 }
    for _, npc in ipairs(selected) do
      local withinLimit, distanceError = npcOrderWithinLimit(npc, { marker })
      if not withinLimit then return false, distanceError end
    end
    for _, npc in ipairs(selected) do
      local ok, reason = startNpcOrder(session, npc, { marker }, { loop = false, speed = speed, waitSeconds = 0 })
      if not ok then return false, reason end
    end
  elseif action == 'rts_patrol' then
    if not isDenseArray(data.markerIds, 20) or #data.markerIds < 2 then return false, 'A patrol needs at least two ordered waypoints.' end
    local route, seenMarkers = {}, {}
    for _, rawMarkerId in ipairs(data.markerIds) do
      local markerId = positiveInteger(rawMarkerId)
      local marker = markerId and encounterMarker(session, markerId, 'patrol') or nil
      if not marker or seenMarkers[markerId] then return false, 'A patrol waypoint is missing or repeated.' end
      seenMarkers[markerId] = true
      route[#route + 1] = marker
    end
    local speed = boundedNumber(data.speed or Config.Encounters.defaultPatrolSpeed, Config.Encounters.minPatrolSpeed, Config.Encounters.maxPatrolSpeed)
    local waitSeconds = boundedNumber(data.waitSeconds == nil and 3 or data.waitSeconds, 0, Config.Encounters.maxPatrolWaitSeconds)
    if not speed or not waitSeconds then return false, 'Patrol pace or waypoint dwell time exceeds the configured limits.' end
    for _, npc in ipairs(selected) do
      local withinLimit, distanceError = npcOrderWithinLimit(npc, route)
      if not withinLimit then return false, distanceError end
    end
    for _, npc in ipairs(selected) do
      local ok, reason = startNpcOrder(session, npc, route, { loop = true, speed = speed, waitSeconds = waitSeconds })
      if not ok then return false, reason end
    end
  elseif action == 'rts_stop' then
    for _, npc in ipairs(selected) do stopNpcOrder(npc, false); npc.holdPosition = true end
  elseif action == 'rts_stance' then
    local stance = type(data.stance) == 'string' and data.stance or ''
    if not rtsStances[stance] then return false, 'Choose Fire at Will, Return Fire, or Hold Fire.' end
    for _, npc in ipairs(selected) do
      local order = npc.order
      npc.stance = stance
      if stance == 'fire_at_will' then npc.holdPosition = false end
      if order and order.kind == 'attack' and stance ~= 'fire_at_will' then
        stopNpcOrder(npc, true)
      elseif stance == 'fire_at_will' and npc.targetId then
        local ok, reason = taskNpcCombat(npc, npc.targetId, false)
        if not ok then return false, reason end
      end
    end
  elseif action == 'rts_target' then
    local targetId = positiveInteger(data.targetPlayerId)
    if not targetId or not GetPlayerName(targetId) or not isAudienceMember(session, targetId) then
      return false, 'Attack orders can target only connected members of the live session audience.'
    end
    for _, npc in ipairs(selected) do
      npc.stance = 'fire_at_will'
      local ok, reason = taskNpcCombat(npc, targetId, false)
      if not ok then return false, reason end
    end
  elseif action == 'rts_weapon' then
    local weapon = allowedEncounterWeapon(data.weapon)
    if not weapon or type(data.enabled) ~= 'boolean' then return false, 'Choose a configured weapon and enabled/disabled state.' end
    local native = data.enabled and GiveWeaponToPed or RemoveWeaponFromPed
    if type(native) ~= 'function' then return false, 'RedM NPC weapon controls are unavailable on this server.' end
    for _, npc in ipairs(selected) do
      if type(npc.weaponStates) ~= 'table' or npc.weaponStates[weapon.name] == nil then
        return false, 'That weapon is not configured for every selected NPC.'
      end
    end
    for _, npc in ipairs(selected) do
      local ok
      if data.enabled then
        ok = pcall(GiveWeaponToPed, npc.entity, GetHashKey(weapon.name), weapon.ammo, false, true)
      else
        ok = pcall(RemoveWeaponFromPed, npc.entity, GetHashKey(weapon.name))
      end
      if not ok then return false, 'RedM could not change the selected NPC weapon.' end
      npc.weaponStates[weapon.name] = data.enabled
      if not data.enabled and not npcHasEnabledWeapon(npc) and npc.order and npc.order.kind == 'attack' then
        stopNpcOrder(npc, true)
      elseif data.enabled and npc.stance == 'fire_at_will' and npc.targetId then
        local applied, reason = taskNpcCombat(npc, npc.targetId, false)
        if not applied then return false, reason end
      end
    end
  end
  return true
end

local function rtsSnapshotPayload(session)
  local units, waypoints, players = {}, {}, {}
  for _, npc in ipairs(sessionEncounterList(session, 'npc')) do
    if encounterEntityExists(npc.entity) then
      local ok, position = false, nil
      if type(GetEntityCoords) == 'function' then ok, position = pcall(GetEntityCoords, npc.entity) end
      if ok and position then
        local weapons = {}
        for name, enabled in pairs(npc.weaponStates or {}) do
          local config = allowedEncounterWeapon(name)
          weapons[#weapons + 1] = { name = name, label = config and config.label or name, enabled = enabled == true }
        end
        table.sort(weapons, function(a, b) return a.label < b.label end)
        local order = npc.order or { kind = 'hold', status = 'holding' }
        local health
        if type(GetEntityHealth) == 'function' then local okHealth, result = pcall(GetEntityHealth, npc.entity); if okHealth then health = result end end
        units[#units + 1] = {
          id = npc.id, model = npc.model, x = position.x, y = position.y, z = position.z,
          alive = not encounterEntityDead(npc.entity), health = health,
          stance = npc.stance or 'fire_at_will', order = {
          kind = order.kind, status = order.status, markerId = order.markerId, targetId = order.targetId,
          targetCoords = order.targetCoords,
            routeMarkerIds = order.route and (function()
              local ids = {}
              for _, marker in ipairs(order.route) do ids[#ids + 1] = tonumber(marker.id) end
              return ids
            end)() or nil,
            routeIndex = order.routeIndex
          },
          weapons = weapons
        }
      end
    end
  end
  for _, marker in pairs(session.spawnPoints or {}) do
    if marker.kind == 'patrol' then
      waypoints[#waypoints + 1] = { id = tonumber(marker.id), label = marker.label, x = tonumber(marker.x), y = tonumber(marker.y), z = tonumber(marker.z) }
    end
  end
  table.sort(waypoints, function(a, b) return tostring(a.label) < tostring(b.label) end)
  for _, id in ipairs(flowAudiencePlayers(session)) do
    local position = currentPosition(id)
    if position then players[#players + 1] = { id = id, name = GetPlayerName(id), x = position.x, y = position.y, z = position.z } end
  end
  return { storyId = session.storyId, units = units, waypoints = waypoints, players = players }
end

local function refreshRtsEngagements(session)
  if not session or Config.Rts.enabled ~= true or Config.Encounters.enabled ~= true or Config.Rts.autoEngage ~= true then return end
  if type(GetEntityCoords) ~= 'function' then return end
  local range = boundedNumber(Config.Rts.autoEngageRange, 1, 1000) or 75
  local now = GetGameTimer()
  if now < (session.rtsEngagementNextAt or 0) then return end
  session.rtsEngagementNextAt = now + math.max(250, tonumber(Config.Rts.autoEngageIntervalMs) or 1200)
  local candidates = {}
  for _, playerId in ipairs(flowAudiencePlayers(session)) do
    local position = currentPosition(playerId)
    if position then candidates[#candidates + 1] = { id = playerId, position = position } end
  end
  for _, npc in ipairs(sessionEncounterList(session, 'npc')) do
    if npc.stance == 'fire_at_will' and not npc.holdPosition and encounterEntityExists(npc.entity) and not encounterEntityDead(npc.entity) then
      local ok, npcPosition = pcall(GetEntityCoords, npc.entity)
      if ok and npcPosition then
        local nearest, nearestDistance
        for _, candidate in ipairs(candidates) do
          local dx = npcPosition.x - candidate.position.x
          local dy = npcPosition.y - candidate.position.y
          local dz = npcPosition.z - candidate.position.z
          local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
          if distance <= range and (not nearestDistance or distance < nearestDistance) then
            nearest, nearestDistance = candidate.id, distance
          end
        end
        local current = tonumber(npc.targetId)
        local currentDistance
        if current then
          for _, candidate in ipairs(candidates) do
            if candidate.id == current then
              local dx = npcPosition.x - candidate.position.x
              local dy = npcPosition.y - candidate.position.y
              local dz = npcPosition.z - candidate.position.z
              currentDistance = math.sqrt(dx * dx + dy * dy + dz * dz)
              break
            end
          end
        end
        if npc.autoTarget and current and (not currentDistance or currentDistance > range) then
          stopNpcOrder(npc, false)
          current = nil
        end
        if not current and nearest and now >= (npc.autoEngageNextAt or 0) then
          npc.autoEngageNextAt = now + 1500
          taskNpcCombat(npc, nearest, false, true)
        end
      end
    end
  end
end

local function encounterDeathSatisfied(session, all)
  local npcs = sessionEncounterList(session, 'npc')
  if #npcs == 0 then return true end
  local deadCount = 0
  for _, npc in ipairs(npcs) do
    if encounterEntityDead(npc.entity) then deadCount = deadCount + 1 end
  end
  return all and deadCount == #npcs or (not all and deadCount > 0)
end

local worldNodeActions = {
  door_open = 'open', door_close = 'close', door_lock = 'lock', door_unlock = 'unlock',
  entity_enable = 'enable', entity_disable = 'disable', trigger_entity = 'trigger'
}

configuredWorldTarget = function(targetId)
  return type(Config.World.targets) == 'table' and Config.World.targets[targetId] or nil
end

local function worldTargetDoorHash(target)
  local value = target and target.doorHash
  if type(value) == 'string' and value ~= '' then return GetHashKey(value) end
  return tonumber(value)
end

local function resolveConfiguredWorldEntity(target)
  if type(target) ~= 'table' or type(target.coords) ~= 'table' then return nil end
  local x, y, z = tonumber(target.coords.x), tonumber(target.coords.y), tonumber(target.coords.z)
  if not x or not y or not z then return nil end
  local radius = boundedNumber(target.radius, 0.5, 100) or 5
  local model = target.model
  if type(model) == 'string' then model = GetHashKey(model) end
  if type(model) ~= 'number' then return nil end
  local entity
  if target.kind == 'ped' and type(GetClosestPed) == 'function' then
    local ok, result = pcall(GetClosestPed, x, y, z, radius, true, true, true, true, -1, model)
    if ok then entity = result end
  elseif type(GetClosestObjectOfType) == 'function' then
    local ok, result = pcall(GetClosestObjectOfType, x, y, z, radius, model, false, false, false)
    if ok then entity = result end
  end
  return entity and encounterEntityExists(entity) and entity or nil
end

local function readWorldTargetState(targetId, target)
  if target.kind == 'door' then
    local hash = worldTargetDoorHash(target)
    if not hash or type(DoorSystemGetDoorState) ~= 'function' or type(DoorSystemGetOpenRatio) ~= 'function' then
      return nil, 'Door-system state inspection is unavailable for this registered target.'
    end
    local okState, state = pcall(DoorSystemGetDoorState, hash)
    local okRatio, ratio = pcall(DoorSystemGetOpenRatio, hash)
    if not okState or not okRatio then return nil, 'The registered door target could not be read.' end
    return { kind = 'door', doorHash = hash, doorState = state, openRatio = ratio }
  end
  local entity = resolveConfiguredWorldEntity(target)
  if not entity then return nil, 'The registered world entity could not be found near its configured position.' end
  if type(IsEntityVisible) ~= 'function' or type(GetEntityCollisionDisabled) ~= 'function' then
    return nil, 'Entity visibility and collision state inspection is unavailable on this RedM server.'
  end
  local okVisible, visible = pcall(IsEntityVisible, entity)
  local okCollision, collisionDisabled = pcall(GetEntityCollisionDisabled, entity)
  if not okVisible or not okCollision then return nil, 'The registered entity state could not be read.' end
  return { kind = 'entity', entity = entity, visible = visible, collisionDisabled = collisionDisabled }
end

local function applyWorldTargetState(state)
  if not state then return false end
  if state.kind == 'door' then
    if type(DoorSystemSetDoorState) ~= 'function' or type(DoorSystemSetOpenRatio) ~= 'function' then return false end
    pcall(DoorSystemSetDoorState, state.doorHash, state.doorState, true, true)
    pcall(DoorSystemSetOpenRatio, state.doorHash, state.openRatio, true, true)
    return true
  end
  if not encounterEntityExists(state.entity) or type(SetEntityVisible) ~= 'function' or type(SetEntityCollision) ~= 'function' then return false end
  pcall(SetEntityVisible, state.entity, state.visible, false)
  pcall(SetEntityCollision, state.entity, not state.collisionDisabled, not state.collisionDisabled)
  return true
end

cleanupSessionWorld = function(session)
  if not session or not session.worldChanges then return end
  for targetId, state in pairs(session.worldChanges) do
    local target = configuredWorldTarget(targetId)
    if target and target.restoreOnSessionEnd == true then applyWorldTargetState(state) end
  end
  session.worldChanges = nil
end

applyWorldAction = function(session, targetId, action)
  local target = configuredWorldTarget(targetId)
  if type(target) ~= 'table' or type(target.actions) ~= 'table' or target.actions[action] ~= true then
    return false, 'The requested action is not enabled for this registered world target.'
  end
  if ({ open = true, close = true, lock = true, unlock = true })[action] and target.kind ~= 'door' then
    return false, 'Door operations require a registered door target.'
  end
  if ({ enable = true, disable = true })[action] and target.kind ~= 'entity' then
    return false, 'Enable/disable operations require a registered entity target.'
  end
  if action == 'trigger' then
    if target.restoreOnSessionEnd == true then return false, 'Trigger targets must use a persistent target policy.' end
    if type(target.triggerEvent) ~= 'string' or not target.triggerEvent:match('^[%w_:%-%.]+$') then return false, 'The configured target has no valid server event.' end
    TriggerEvent(target.triggerEvent, targetId)
    return true
  end
  local state, reason = readWorldTargetState(targetId, target)
  if not state then return false, reason end
  session.worldChanges = session.worldChanges or {}
  if not session.worldChanges[targetId] then session.worldChanges[targetId] = state end
  if state.kind == 'door' then
    local hash = state.doorHash
    if action == 'open' or action == 'close' then
      if type(DoorSystemSetOpenRatio) ~= 'function' then return false, 'Door open control is unavailable.' end
      local ratio = action == 'open' and (tonumber(target.openRatio) or -1.0) or 0.0
      DoorSystemSetOpenRatio(hash, ratio, true, true)
    else
      if type(DoorSystemSetDoorState) ~= 'function' then return false, 'Door lock control is unavailable.' end
      DoorSystemSetDoorState(hash, action == 'lock' and 1 or 0, true, true)
    end
  else
    if not encounterEntityExists(state.entity) then return false, 'The registered entity disappeared before its action ran.' end
    if action == 'enable' or action == 'disable' then
      local enabled = action == 'enable'
      SetEntityVisible(state.entity, enabled, false)
      SetEntityCollision(state.entity, enabled, enabled)
    else
      return false, 'That action is not supported for an entity target.'
    end
  end
  return true
end

cleanupSessionEffects = function(session)
  if not session then return end
  for _, id in ipairs(flowAudiencePlayers(session)) do
    TriggerClientEvent('arachnid_storyteller:storyEffect', id, { kind = 'cleanup' })
  end
  session.effects = nil
end

local function applyStoryEffect(session, kind, data)
  local targets = flowAudiencePlayers(session)
  if #targets == 0 then return true end
  session.effects = session.effects or { sounds = {} }
  session.effects.sounds = session.effects.sounds or {}
  if kind == 'play_sound' then
    local sound = allowedEffectSound(data.soundId)
    if not sound then return false, 'The sound was removed from the server allowlist.' end
    session.effects.sounds[data.soundId] = true
    local payload = { kind = kind, soundId = data.soundId, name = sound.name, set = sound.set, volume = data.volume, pitch = data.pitch }
    for _, id in ipairs(targets) do TriggerClientEvent('arachnid_storyteller:storyEffect', id, payload) end
  elseif kind == 'stop_sound' then
    if session.effects.sounds[data.soundId] then
      for _, id in ipairs(targets) do TriggerClientEvent('arachnid_storyteller:storyEffect', id, { kind = kind, soundId = data.soundId }) end
      session.effects.sounds[data.soundId] = nil
    end
  else
    for _, id in ipairs(targets) do TriggerClientEvent('arachnid_storyteller:storyEffect', id, { kind = kind, data = data }) end
  end
  return true
end

local function flowActionTargets(session, targetMode)
  local targets = flowAudiencePlayers(session)
  if targetMode == 'random' then
    if #targets == 0 then return {} end
    return { targets[math.random(1, #targets)] }
  end
  return targets
end

local function startSessionCutscene(session, sceneId)
  local scene
  for _, candidate in ipairs(session.scenes or {}) do
    if tonumber(candidate.id) == tonumber(sceneId) then scene = candidate break end
  end
  if not scene then return false, 'That scene is not part of the active story.' end
  local payload, reason = cutscenePayload(scene, scene.cutscene_settings)
  if not payload then return false, reason end
  stopSessionCutscene(session)
  payload.runtimeId = session.runtimeId
  session.cutscene = {
    sceneId = tonumber(scene.id),
    loop = payload.settings.loop,
    finishAt = payload.settings.loop and nil or (GetGameTimer() + math.floor(payload.duration * 1000)),
    remaining = payload.duration * 1000,
    paused = false
  }
  for _, id in ipairs(flowAudiencePlayers(session)) do TriggerClientEvent('arachnid_storyteller:cutscenePlay', id, payload) end
  return true, payload
end

local function pauseSessionCutscene(session)
  if not session or not session.cutscene or session.cutscene.paused then return end
  local cutscene = session.cutscene
  if cutscene.finishAt then cutscene.remaining = math.max(0, cutscene.finishAt - GetGameTimer()) end
  cutscene.finishAt, cutscene.paused = nil, true
  for _, id in ipairs(flowAudiencePlayers(session)) do TriggerClientEvent('arachnid_storyteller:cutscenePause', id) end
end

local function resumeSessionCutscene(session)
  if not session or not session.cutscene or not session.cutscene.paused then return end
  local cutscene = session.cutscene
  cutscene.paused = false
  if not cutscene.loop then cutscene.finishAt = GetGameTimer() + (cutscene.remaining or 0) end
  for _, id in ipairs(flowAudiencePlayers(session)) do TriggerClientEvent('arachnid_storyteller:cutsceneResume', id) end
end

vorpCharacterFor = function(sourceId, core)
  if not core or type(core.getUser) ~= 'function' then return nil end
  local ok, user = pcall(core.getUser, sourceId)
  if not ok then return nil end
  if type(user) ~= 'table' then return nil end
  local character = user.getUsedCharacter or user.GetUsedCharacter
  if type(character) == 'function' then
    local ok, result = pcall(character)
    if not ok then return nil end
    character = result
  end
  return type(character) == 'table' and character or nil
end

local function executePlayerAction(session, node)
  local kind, data = node.type, node.data
  local targets = flowActionTargets(session, data.target)
  local successCount, skippedCount, failedCount, firstFailure = 0, 0, 0, nil
  local function audit(outcome, count)
    local description = ('Flow action %s %s for %d participant(s) in story #%s'):format(kind, outcome, count or 0, tostring(session.storyId))
    local actor = tostring(session.startedBy or 'Storyteller')
    local identifier = tostring(session.startedByIdentifier or session.startedBySource or 'unknown')
    MySQL.insert('INSERT INTO arachnid_storyteller_audit (actor_name,actor_identifier,action) VALUES (?,?,?)', {
      actor:sub(1, 100), identifier:sub(1, 160), description:sub(1, 255)
    })
    print(('[arachnid_storyteller] %s (%s): %s'):format(actor, identifier, description))
  end
  local function failure(reason)
    audit(successCount > 0 and 'partially failed' or 'failed', successCount)
    return false, reason
  end
  if #targets == 0 then
    audit('skipped (no connected targets)', 0)
    return true
  end
  local function runNative(fn)
    if type(fn) ~= 'function' then return false, 'Required RedM native is unavailable.' end
    local ok, err = pcall(fn)
    if not ok then return false, tostring(err) end
    successCount = successCount + 1
    return true
  end

  local core
  if flowVorpActions[kind] then
    local reason
    core, reason = getVorpCore()
    if not core then return failure(reason) end
  end
  local weaponHash, weaponConfig
  if kind == 'give_weapon' or kind == 'strip_weapon' then
    weaponConfig = allowedWeapon(data.weapon)
    if not weaponConfig then return failure('Configured weapon allowlist changed while the flow was running.') end
    weaponHash = GetHashKey(data.weapon)
  end
  local marker
  if kind == 'teleport_players' then
    marker = session.flowRuntime.teleports[tostring(data.markerId)]
    if not marker then return failure('A teleport marker in the active flow is unavailable.') end
  end

  for _, id in ipairs(targets) do
    if GetPlayerName(id) then
      local ped = GetPlayerPed(id)
      if ped and ped ~= 0 then
        local ok, reason = true, nil
        if kind == 'send_message' then
          TriggerClientEvent('arachnid_storyteller:actionMessage', id, {
            title = session.storyTitle, text = data.message, duration = 7000
          })
          successCount = successCount + 1
        elseif kind == 'freeze_players' then
          local alreadyFrozen = type(IsEntityPositionFrozen) == 'function' and IsEntityPositionFrozen(ped) or false
          ok, reason = runNative(function() FreezeEntityPosition(ped, true) end)
          if ok and not alreadyFrozen then frozenByArachnid[tostring(id)] = session.runtimeId end
        elseif kind == 'unfreeze_players' then
          ok, reason = runNative(function() FreezeEntityPosition(ped, false) end)
          if ok then frozenByArachnid[tostring(id)] = nil end
        elseif kind == 'set_health' then
          ok, reason = runNative(function() SetEntityHealth(ped, data.health) end)
        elseif kind == 'set_armor' then
          ok, reason = runNative(function() SetPedArmour(ped, data.armor) end)
        elseif kind == 'give_weapon' then
          ok, reason = runNative(function() GiveWeaponToPed(ped, weaponHash, data.ammo, false, true) end)
        elseif kind == 'strip_weapon' then
          ok, reason = runNative(function() RemoveWeaponFromPed(ped, weaponHash) end)
        elseif kind == 'strip_all_weapons' then
          ok, reason = runNative(function() RemoveAllPedWeapons(ped, true, false) end)
        elseif kind == 'teleport_players' then
          ok, reason = runNative(function()
            SetEntityCoords(ped, tonumber(marker.x), tonumber(marker.y), tonumber(marker.z) + Config.PlayerActions.teleportZOffset, false, false, false, false)
            SetEntityHeading(ped, tonumber(marker.heading) or 0.0)
          end)
        elseif kind == 'kill_players' then
          ok, reason = runNative(function() SetEntityHealth(ped, 0) end)
        elseif kind == 'respawn_players' then
          ok, reason = runNative(function() core.Player.Respawn(id) end)
        elseif kind == 'change_job' then
          local character = vorpCharacterFor(id, core)
          if not character or type(character.setJob) ~= 'function' or type(character.setJobGrade) ~= 'function' then
            skippedCount = skippedCount + 1
          else
            ok, reason = runNative(function()
              local job = Config.PlayerActions.jobs[data.jobName]
              character.setJob(data.jobName)
              character.setJobGrade(data.grade)
              if job and job.label and type(character.setJobLabel) == 'function' then character.setJobLabel(job.label) end
            end)
          end
        end
        if not ok then
          failedCount = failedCount + 1
          firstFailure = firstFailure or ('player %s: %s'):format(tostring(id), tostring(reason))
        end
      end
    end
  end
  if failedCount > 0 then
    return failure(('%d target action(s) failed for %s; first error: %s'):format(failedCount, kind, tostring(firstFailure)))
  end
  if successCount == 0 then
    audit(('skipped (%d target(s) had no usable player state)'):format(skippedCount), 0)
  else
    audit('ran', successCount)
  end
  return true
end

local function flowCompare(runtime, data)
  local value = runtime.variables[data.variable]
  if value == nil or value.type ~= data.valueType then return false end
  local left, right = value.value, data.value
  if data.operator == '==' then return left == right end
  if data.operator == '!=' then return left ~= right end
  if type(left) ~= 'number' or type(right) ~= 'number' then return false end
  if data.operator == '>' then return left > right end
  if data.operator == '<' then return left < right end
  if data.operator == '>=' then return left >= right end
  if data.operator == '<=' then return left <= right end
  return false
end

local function flowFault(message)
  local runtime = activeSession and activeSession.flowRuntime
  if not runtime then return end
  runtime.paused = true
  runtime.error = tostring(message):sub(1, 240)
  print('[arachnid_storyteller] Flow paused: ' .. runtime.error)
  broadcastSession('flow_error')
  local actor = activeSession.startedBySource
  if actor and GetPlayerName(actor) and canManage(actor) then
    TriggerClientEvent('arachnid_storyteller:feedback', actor, 'Flow paused: ' .. runtime.error)
  end
end

local function flowTick()
  local session = activeSession
  if session and session.cutscene and not session.cutscene.paused and not session.cutscene.loop and
    session.cutscene.finishAt and GetGameTimer() >= session.cutscene.finishAt then
    stopSessionCutscene(session)
    broadcastSession('cutscene_completed', session)
  end
  if not session or not session.flowRuntime then return end
  local runtime = session.flowRuntime
  if runtime.paused then return end

  for index = #runtime.waiters, 1, -1 do
    local waiting = runtime.waiters[index]
    local ready, port = false, waiting.port or 'next'
    if waiting.kind == 'delay' then
      ready = waiting.untilTime and GetGameTimer() >= waiting.untilTime or false
    elseif waiting.kind == 'objective' then
      local status = session.objective and session.objective.status
      if status == 'completed' or status == 'failed' then ready, port = true, status end
    elseif waiting.kind == 'area' then
      ready = flowAreaCondition(session, waiting.area, waiting.condition)
    elseif waiting.kind == 'cutscene' then
      local cutscene = session.cutscene
      ready = not cutscene or (not cutscene.paused and not cutscene.loop and cutscene.finishAt and GetGameTimer() >= cutscene.finishAt)
      if ready and cutscene then stopSessionCutscene(session) end
    elseif waiting.kind == 'npc_death' then
      ready = encounterDeathSatisfied(session, false)
    elseif waiting.kind == 'npcs_dead' then
      ready = encounterDeathSatisfied(session, true)
    end
    if ready then
      table.remove(runtime.waiters, index)
      flowEnqueueRoute(runtime, waiting.nodeId, port)
    end
  end

  local steps = 0
  while activeSession == session and not runtime.paused and #runtime.queue > 0 and steps < Config.Flow.maxStepsPerTick do
    local token = table.remove(runtime.queue, 1)
    local node = runtime.nodes[token.nodeId]
    if not node then return flowFault('Flow reached a missing node.') end
    steps = steps + 1
    local nextPort = 'next'

    if node.type == 'and_node' then
      local arrivals = runtime.joinArrivals[node.id] or {}
      arrivals[token.inputPort] = true
      runtime.joinArrivals[node.id] = arrivals
      if arrivals.a and arrivals.b and not runtime.joinFired[node.id] then
        runtime.joinFired[node.id] = true
        flowEnqueueRoute(runtime, node.id, nextPort)
      end
    elseif node.type == 'or_node' then
      if not runtime.joinFired[node.id] then
        runtime.joinFired[node.id] = true
        flowEnqueueRoute(runtime, node.id, nextPort)
      end
    elseif node.type == 'start' then
      flowEnqueueRoute(runtime, node.id, nextPort)
    elseif node.type == 'scene' then
      local targetIndex
      for sceneIndex, scene in ipairs(session.scenes) do
        if tonumber(scene.id) == tonumber(node.data.sceneId) then targetIndex = sceneIndex break end
      end
      if not targetIndex then return flowFault('A scene referenced by the active flow was removed.') end
      activateSessionScene(targetIndex, session.startedBy)
      broadcastSession('flow_scene')
      flowEnqueueRoute(runtime, node.id, nextPort)
    elseif node.type == 'delay' then
      if node.data.seconds <= 0 then
        flowEnqueueRoute(runtime, node.id, nextPort)
      else
        runtime.waiters[#runtime.waiters + 1] = {
          kind = 'delay', nodeId = node.id, port = nextPort,
          untilTime = GetGameTimer() + math.floor(node.data.seconds * 1000)
        }
      end
    elseif node.type == 'branch' then
      flowEnqueueRoute(runtime, node.id, flowCompare(runtime, node.data) and 'true' or 'false')
    elseif node.type == 'random_branch' then
      local succeeds = math.random(1, 10000) <= math.floor(node.data.chance * 100)
      flowEnqueueRoute(runtime, node.id, succeeds and 'success' or 'failure')
    elseif node.type == 'set_variable' then
      runtime.variables[node.data.variable] = { type = node.data.valueType, value = node.data.value }
      flowEnqueueRoute(runtime, node.id, nextPort)
    elseif node.type == 'add_variable' or node.type == 'subtract_variable' then
      local current = runtime.variables[node.data.variable]
      if current and current.type ~= 'number' then return flowFault('Add/subtract requires a numeric variable: ' .. node.data.variable) end
      local value = current and current.value or 0
      local amount = node.data.amount * (node.type == 'add_variable' and 1 or -1)
      local result = value + amount
      if result ~= result or math.abs(result) > Config.Flow.maxVariableNumber then return flowFault('Variable result exceeds the configured limit.') end
      runtime.variables[node.data.variable] = { type = 'number', value = result }
      flowEnqueueRoute(runtime, node.id, nextPort)
    elseif node.type == 'objective' then
      session.objective = { text = node.data.text, status = 'active', updatedAt = os.time(), updatedBy = session.startedBy }
      broadcastSession('objective_updated')
      flowEnqueueRoute(runtime, node.id, nextPort)
    elseif node.type == 'complete_objective' or node.type == 'fail_objective' then
      local status = node.type == 'complete_objective' and 'completed' or 'failed'
      session.objective = session.objective or { text = '', updatedBy = session.startedBy }
      session.objective.status, session.objective.updatedAt, session.objective.updatedBy = status, os.time(), session.startedBy
      broadcastSession('objective_' .. status)
      flowEnqueueRoute(runtime, node.id, nextPort)
    elseif node.type == 'wait_objective' then
      local status = session.objective and session.objective.status
      if status == 'completed' or status == 'failed' then
        flowEnqueueRoute(runtime, node.id, status)
      else
        runtime.waiters[#runtime.waiters + 1] = { kind = 'objective', nodeId = node.id, port = 'completed' }
      end
    elseif node.type == 'wait_area' or node.type == 'wait_all_in_area' or node.type == 'wait_area_empty' then
      local area = runtime.areas[tostring(node.data.areaId)]
      if not area then return flowFault('An area referenced by the active flow is unavailable.') end
      local condition = node.type == 'wait_area' and 'any' or node.type == 'wait_all_in_area' and 'all' or 'empty'
      if flowAreaCondition(session, area, condition) then
        flowEnqueueRoute(runtime, node.id, nextPort)
      else
        runtime.waiters[#runtime.waiters + 1] = {
          kind = 'area', nodeId = node.id, port = nextPort, area = area, condition = condition
        }
      end
    elseif node.type == 'check_player_count' then
      local count = #flowAudiencePlayers(session)
      local passed = flowCountMatches(count, node.data.operator, node.data.count)
      flowEnqueueRoute(runtime, node.id, passed and 'true' or 'false')
    elseif node.type == 'check_job' then
      flowEnqueueRoute(runtime, node.id, flowAudienceHasJob(session, node.data.jobName) and 'true' or 'false')
    elseif node.type == 'check_entity_alive' then
      flowEnqueueRoute(runtime, node.id, flowConfiguredEntityAlive(node.data.targetId) and 'true' or 'false')
    elseif flowWorldActions[node.type] then
      flowEnqueueRoute(runtime, node.id, nextPort)
      local callOk, actionOk, actionError = pcall(applyWorldAction, session, node.data.targetId, flowWorldActions[node.type])
      if not callOk then return flowFault(tostring(actionOk)) end
      if not actionOk then return flowFault(actionError) end
    elseif flowFeatureNodes.effects[node.type] then
      flowEnqueueRoute(runtime, node.id, nextPort)
      local callOk, actionOk, actionError = pcall(applyStoryEffect, session, node.type, node.data)
      if not callOk then return flowFault(tostring(actionOk)) end
      if not actionOk then return flowFault(actionError) end
    elseif node.type == 'not_node' then
      flowEnqueueRoute(runtime, node.id, nextPort)
    elseif node.type == 'play_cutscene' then
      local ok, reason = startSessionCutscene(session, node.data.sceneId)
      if not ok then return flowFault(reason) end
      flowEnqueueRoute(runtime, node.id, nextPort)
    elseif node.type == 'wait_cutscene' then
      local cutscene = session.cutscene
      if not cutscene or (not cutscene.loop and not cutscene.paused and cutscene.finishAt and GetGameTimer() >= cutscene.finishAt) then
        if cutscene then stopSessionCutscene(session) end
        flowEnqueueRoute(runtime, node.id, nextPort)
      else
        runtime.waiters[#runtime.waiters + 1] = { kind = 'cutscene', nodeId = node.id, port = nextPort }
      end
    elseif node.type == 'stop_cutscene' then
      stopSessionCutscene(session)
      flowEnqueueRoute(runtime, node.id, nextPort)
    elseif node.type == 'wait_npc_death' or node.type == 'wait_npcs_dead' then
      local all = node.type == 'wait_npcs_dead'
      if encounterDeathSatisfied(session, all) then
        flowEnqueueRoute(runtime, node.id, nextPort)
      else
        runtime.waiters[#runtime.waiters + 1] = { kind = all and 'npcs_dead' or 'npc_death', nodeId = node.id, port = nextPort }
      end
    elseif flowFeatureNodes.encounters[node.type] then
      flowEnqueueRoute(runtime, node.id, nextPort)
      local callOk, actionOk, actionError = pcall(applyEncounterAction, session, node.type, node.data)
      if not callOk then return flowFault(tostring(actionOk)) end
      if not actionOk then return flowFault(actionError) end
    elseif flowActionSettings[node.type] then
      -- Queue the next node before applying the action so Resume cannot repeat it.
      flowEnqueueRoute(runtime, node.id, nextPort)
      local callOk, actionOk, actionError = pcall(executePlayerAction, session, node)
      if not callOk then return flowFault(tostring(actionOk)) end
      if not actionOk then return flowFault(actionError) end
    elseif node.type == 'end' then
      if activeSession == session then endActiveSession('ended', session.startedBySource) end
      return
    else
      return flowFault('Flow contains an unsupported node type.')
    end
  end

  if activeSession == session then
    if #runtime.queue == 0 and #runtime.waiters > 0 then broadcastSession('flow_waiting') end
    if steps >= Config.Flow.maxStepsPerTick and #runtime.queue > 0 then broadcastSession('flow_running') end
  end
end
local function storyForSession(id)
  local rows = MySQL.query.await('SELECT id,title,status FROM arachnid_storyteller_stories WHERE id=? LIMIT 1', { id })
  if type(rows) ~= 'table' or not rows[1] then return nil, 'That story no longer exists.' end
  local story = rows[1]
  if Config.Session.requirePublishedStory and story.status ~= 'published' then
    return nil, 'Publish the story before starting a live session.'
  end
  local scenes = MySQL.query.await([[SELECT id,title,objective,sort_order,x,y,z
    FROM arachnid_storyteller_scenes WHERE story_id=? ORDER BY sort_order ASC,id ASC]], { id }) or {}
  if #scenes == 0 then return nil, 'Add at least one scene beat before starting a session.' end
  local points = MySQL.query.await([[SELECT points.id,points.scene_id,points.label,points.message,points.sort_order,points.x,points.y,points.z,
      points.heading,points.fov,points.hold_duration,points.transition_duration
    FROM arachnid_storyteller_camera_points AS points
    INNER JOIN arachnid_storyteller_scenes AS scenes ON scenes.id=points.scene_id
    WHERE scenes.story_id=? ORDER BY points.scene_id,points.sort_order,points.id]], { id }) or {}
  local pointsByScene = {}
  for _, point in ipairs(points) do
    pointsByScene[tostring(point.scene_id)] = pointsByScene[tostring(point.scene_id)] or {}
    pointsByScene[tostring(point.scene_id)][#pointsByScene[tostring(point.scene_id)] + 1] = point
  end
  for _, scene in ipairs(scenes) do
    scene.cutscene_settings = sceneCutsceneSettings(scene.id)
    scene.camera_points = pointsByScene[tostring(scene.id)] or {}
  end
  local spawnPoints = MySQL.query.await([[SELECT id,story_id,label,kind,x,y,z,heading
    FROM arachnid_storyteller_spawn_points WHERE story_id=? ORDER BY kind,label,id]], { id }) or {}
  local spawnById = {}
  for _, marker in ipairs(spawnPoints) do spawnById[tostring(marker.id)] = marker end
  local flowRows = MySQL.query.await('SELECT graph_json FROM arachnid_storyteller_flows WHERE story_id=? LIMIT 1', { id }) or {}
  local flow = nil
  if flowRows[1] then
    local decoded, value = pcall(json.decode, flowRows[1].graph_json)
    if not decoded or type(value) ~= 'table' then return nil, 'Saved flow data is invalid; open and resave the graph.' end
    flow = value
  end
  return { id = story.id, title = story.title, scenes = scenes, flow = flow, spawnPoints = spawnById }
end

local function snapshot()
  local stories = MySQL.query.await([[SELECT id,title,summary,status,created_by,updated_by,created_at,updated_at
    FROM arachnid_storyteller_stories
    ORDER BY FIELD(status,'published','draft','archived'),updated_at DESC,id DESC]]) or {}
  local scenes = MySQL.query.await([[SELECT id,story_id,title,objective,sort_order,x,y,z,created_by,created_at,updated_at
    FROM arachnid_storyteller_scenes ORDER BY story_id ASC,sort_order ASC,id ASC]]) or {}
  local cutsceneRows = MySQL.query.await('SELECT scene_id,settings_json FROM arachnid_storyteller_cutscene_settings') or {}
  local cutsceneSettingsByScene = {}
  for _, row in ipairs(cutsceneRows) do
    local ok, value = pcall(json.decode, row.settings_json)
    local settings = ok and normalizedCutsceneSettings(value) or nil
    if settings then cutsceneSettingsByScene[tostring(row.scene_id)] = settings end
  end
  local cameraPoints = MySQL.query.await([[SELECT id,scene_id,label,message,sort_order,x,y,z,heading,fov,hold_duration,
    transition_duration,created_by,created_at,updated_at FROM arachnid_storyteller_camera_points
    ORDER BY scene_id ASC,sort_order ASC,id ASC]]) or {}
  local areas = MySQL.query.await([[SELECT id,label,shape,x,y,z,radius,width,depth,height,created_by,created_at,updated_at
    FROM arachnid_storyteller_areas ORDER BY label ASC,id ASC]]) or {}
  local teleports = MySQL.query.await([[SELECT id,story_id,label,x,y,z,heading,created_by,created_at,updated_at
    FROM arachnid_storyteller_teleports ORDER BY story_id ASC,label ASC,id ASC]]) or {}
  local spawnPoints = MySQL.query.await([[SELECT id,story_id,label,kind,x,y,z,heading,created_by,created_at,updated_at
    FROM arachnid_storyteller_spawn_points ORDER BY story_id ASC,kind ASC,label ASC,id ASC]]) or {}
  local flowRows = MySQL.query.await('SELECT story_id,graph_json,updated_by,updated_at FROM arachnid_storyteller_flows') or {}
  local flowsByStory = {}
  for _, row in ipairs(flowRows) do
    local ok, graph = pcall(json.decode, row.graph_json)
    flowsByStory[tostring(row.story_id)] = ok and type(graph) == 'table' and graph or nil
  end
  local camerasByScene = {}
  for _, point in ipairs(cameraPoints) do
    camerasByScene[point.scene_id] = camerasByScene[point.scene_id] or {}
    camerasByScene[point.scene_id][#camerasByScene[point.scene_id] + 1] = point
  end
  local scenesByStory = {}
  local teleportsByStory = {}
  local spawnPointsByStory = {}
  for _, marker in ipairs(teleports) do
    teleportsByStory[marker.story_id] = teleportsByStory[marker.story_id] or {}
    teleportsByStory[marker.story_id][#teleportsByStory[marker.story_id] + 1] = marker
  end
  for _, marker in ipairs(spawnPoints) do
    spawnPointsByStory[marker.story_id] = spawnPointsByStory[marker.story_id] or {}
    spawnPointsByStory[marker.story_id][#spawnPointsByStory[marker.story_id] + 1] = marker
  end
  for _, scene in ipairs(scenes) do
    scene.camera_points = camerasByScene[scene.id] or {}
    scene.camera_point_count = #scene.camera_points
    scene.cutscene_settings = cutsceneSettingsByScene[tostring(scene.id)] or defaultCutsceneSettings()
    scenesByStory[scene.story_id] = scenesByStory[scene.story_id] or {}
    scenesByStory[scene.story_id][#scenesByStory[scene.story_id] + 1] = scene
  end
  for _, story in ipairs(stories) do
    story.scenes = scenesByStory[story.id] or {}
    story.scene_count = #story.scenes
    story.flow = flowsByStory[tostring(story.id)]
    story.teleports = teleportsByStory[story.id] or {}
    story.spawnPoints = spawnPointsByStory[story.id] or {}
  end
  local actionConfig = Config.PlayerActions
  local playerActions = {
    enabled = actionConfig.enabled or {},
    maxMessageLength = actionConfig.maxMessageLength,
    maxHealth = actionConfig.maxHealth,
    maxArmor = actionConfig.maxArmor,
    maxAmmo = actionConfig.maxAmmo,
    weapons = {},
    jobs = {}
  }
  for name, weapon in pairs(type(actionConfig.weapons) == 'table' and actionConfig.weapons or {}) do
    local _, maxAmmo, defaultAmmo = allowedWeapon(name)
    if type(name) == 'string' and type(weapon) == 'table' and maxAmmo then
      playerActions.weapons[#playerActions.weapons + 1] = {
        name = name, label = cleanText(weapon.label or name, 100, true) or name,
        maxAmmo = maxAmmo, defaultAmmo = defaultAmmo
      }
    end
  end
  table.sort(playerActions.weapons, function(left, right) return left.label < right.label end)
  for name, job in pairs(type(actionConfig.jobs) == 'table' and actionConfig.jobs or {}) do
    if type(name) == 'string' and type(job) == 'table' and type(job.grades) == 'table' then
      local grades = {}
      for key, value in pairs(job.grades) do
        local grade = value == true and tonumber(key) or type(key) == 'number' and tonumber(value) or tonumber(value)
        if grade and grade >= 0 and grade % 1 == 0 then grades[#grades + 1] = grade end
      end
      table.sort(grades)
      playerActions.jobs[#playerActions.jobs + 1] = {
        name = name, label = cleanText(job.label or name, 100, true) or name, grades = grades
      }
    end
  end
  table.sort(playerActions.jobs, function(left, right) return left.label < right.label end)
  local worldTargets = {}
  for targetId, target in pairs(type(Config.World.targets) == 'table' and Config.World.targets or {}) do
    if type(targetId) == 'string' and type(target) == 'table' then
      worldTargets[#worldTargets + 1] = {
        id = targetId, label = cleanText(target.label or targetId, 100, true) or targetId,
        kind = target.kind, actions = type(target.actions) == 'table' and target.actions or {},
        restoreOnSessionEnd = target.restoreOnSessionEnd == true
      }
    end
  end
  table.sort(worldTargets, function(left, right) return left.label < right.label end)
  local encounterConfig = Config.Encounters or {}
  local encounterModels = { ped = {}, prop = {} }
  for _, pair in ipairs({ { 'ped', encounterConfig.pedModels }, { 'prop', encounterConfig.propModels } }) do
    local kind, models = pair[1], type(pair[2]) == 'table' and pair[2] or {}
    for model, entry in pairs(models) do
      local allow = allowedEncounterModel(kind, model)
      if allow and type(model) == 'string' then
        encounterModels[kind][#encounterModels[kind] + 1] = {
          name = model,
          label = cleanText(type(entry) == 'table' and entry.label or model, 100, true) or model,
          maxHealth = kind == 'ped' and maxPedHealth(allow) or encounterConfig.maxNpcHealth
        }
      end
    end
    table.sort(encounterModels[kind], function(left, right) return left.label < right.label end)
  end
  local effectsConfig = Config.Effects or {}
  local sounds = {}
  for soundId, sound in pairs(type(effectsConfig.sounds) == 'table' and effectsConfig.sounds or {}) do
    if type(soundId) == 'string' and allowedEffectSound(soundId) then
      sounds[#sounds + 1] = { id = soundId, label = cleanText(sound.label or soundId, 100, true) or soundId }
    end
  end
  table.sort(sounds, function(left, right) return left.label < right.label end)
  return {
    stories = stories,
    session = activeSession and sessionPayload('snapshot') or nil,
    players = onlinePlayers(),
    areas = areas,
    areaLimits = {
      minRadius = Config.Areas.minRadius,
      maxRadius = Config.Areas.maxRadius,
      minDimension = Config.Areas.minDimension,
      maxDimension = Config.Areas.maxDimension
    },
    flowLimits = {
      maxNodes = Config.Flow.maxNodes,
      maxLinks = Config.Flow.maxLinks,
      maxDelaySeconds = Config.Flow.maxDelaySeconds,
      maxParticipants = Config.Session.maxParticipants
    },
    camera = {
      defaultPlacementDistance = Config.Camera.Tool.defaultPlacementDistance,
      maxPlacementDistance = Config.Camera.Tool.maxPlacementDistance,
      toolConfigured = Config.Camera.Tool.weapon ~= ''
    },
    cutscenes = {
      enabled = Config.Cutscenes.enabled == true,
      maxFadeSeconds = Config.Cutscenes.maxFadeSeconds,
      minFov = Config.Cutscenes.minFov,
      maxFov = Config.Cutscenes.maxFov,
      defaults = defaultCutsceneSettings()
    },
    world = { enabled = Config.World.enabled == true, targets = worldTargets },
    encounters = {
      enabled = encounterConfig.enabled == true,
      maxNpcsPerSession = encounterConfig.maxNpcsPerSession,
      maxPropsPerSession = encounterConfig.maxPropsPerSession,
      maxGroupCount = encounterConfig.maxGroupCount,
      maxNpcHealth = encounterConfig.maxNpcHealth,
      maxPatrolWaitSeconds = encounterConfig.maxPatrolWaitSeconds,
      minPatrolSpeed = encounterConfig.minPatrolSpeed,
      maxPatrolSpeed = encounterConfig.maxPatrolSpeed,
      defaultPatrolSpeed = encounterConfig.defaultPatrolSpeed,
      models = encounterModels
    },
    rts = {
      enabled = Config.Rts.enabled == true,
      snapshotIntervalMs = Config.Rts.snapshotIntervalMs
    },
    effects = {
      enabled = effectsConfig.enabled == true,
      sounds = sounds,
      maxDurationSeconds = effectsConfig.maxDurationSeconds,
      maxVolume = effectsConfig.maxVolume,
      minPitch = effectsConfig.minPitch,
      maxPitch = effectsConfig.maxPitch,
      maxShakeAmplitude = effectsConfig.maxShakeAmplitude,
      maxShakeFrequency = effectsConfig.maxShakeFrequency,
      maxMessageLength = effectsConfig.maxMessageLength
    },
    playerActions = playerActions,
    serverTime = os.date('!%Y-%m-%d %H:%M:%S UTC')
  }
end

local function sendData(src, open)
  local ok, data = pcall(snapshot)
  if not ok then
    print('[arachnid_storyteller] Snapshot failed: ' .. tostring(data))
    TriggerClientEvent('arachnid_storyteller:feedback', src, 'Story data is unavailable. Check the server console.')
    return
  end
  TriggerClientEvent(open and 'arachnid_storyteller:open' or 'arachnid_storyteller:data', src, data)
end

local function feedback(src, message)
  TriggerClientEvent('arachnid_storyteller:feedback', src, message)
  sendData(src, false)
end

RegisterNetEvent('arachnid_storyteller:requestOpen', function()
  local src = source
  if not canManage(src) then
    TriggerClientEvent('arachnid_storyteller:denied', src, 'You need the Arachnid Storyteller ACE permissions to use /STTool.')
    return
  end
  if not databaseReady then
    TriggerClientEvent('arachnid_storyteller:denied', src, 'Storyteller is still starting. Check oxmysql if this persists.')
    return
  end
  logAction(src, 'Opened the gamemaster console')
  sendData(src, true)
end)

RegisterNetEvent('arachnid_storyteller:requestData', function()
  local src = source
  if canManage(src) and databaseReady then sendData(src, false) end
end)

RegisterNetEvent('arachnid_storyteller:requestSession', function()
  if Config.Session.broadcastToPlayers and activeSession and isAudienceMember(activeSession, source) then
    TriggerClientEvent('arachnid_storyteller:session', source, sessionPayload('sync'))
  end
end)

RegisterNetEvent('arachnid_storyteller:requestRtsSnapshot', function()
  local src = source
  if not canManage(src) or not activeSession then return end
  if Config.Rts.enabled ~= true or Config.Encounters.enabled ~= true or not IsPlayerAceAllowed(src, Config.Ace.encounters) then return end
  activeSession.rtsRequestAt = activeSession.rtsRequestAt or {}
  local now = GetGameTimer()
  if now - (activeSession.rtsRequestAt[src] or 0) < 500 then return end
  activeSession.rtsRequestAt[src] = now
  TriggerClientEvent('arachnid_storyteller:rtsSnapshot', src, rtsSnapshotPayload(activeSession))
end)

RegisterNetEvent('arachnid_storyteller:cameraPointCapture', function(rawSceneId, rawHeading, rawDistance)
  local src = source
  if not canManage(src) or not databaseReady then return end
  local sceneId = positiveInteger(rawSceneId)
  if not sceneId then return feedback(src, 'Invalid scene identifier.') end
  local heading = boundedNumber(rawHeading, -720, 720) or 0
  local distance = boundedNumber(rawDistance, 0, Config.Camera.Tool.maxPlacementDistance)
  if distance == nil then distance = Config.Camera.Tool.defaultPlacementDistance end
  local ok, point, reason = pcall(function()
    local scene = sceneRecord(sceneId)
    if not scene then return nil, 'That scene no longer exists.' end
    local position = currentPosition(src)
    if not position then return nil, 'Current position is unavailable. Ensure OneSync is enabled and try again.' end
    heading = heading % 360
    local radians = math.rad(heading)
    position.x = position.x + math.sin(radians) * distance
    position.y = position.y + math.cos(radians) * distance
    position.z = position.z + Config.Camera.captureHeight
    local rows = MySQL.query.await('SELECT COALESCE(MAX(sort_order),0) AS max_order FROM arachnid_storyteller_camera_points WHERE scene_id=?', { sceneId })
    local sortOrder = ((rows and rows[1] and tonumber(rows[1].max_order)) or 0) + 1
    local id = MySQL.insert.await([[INSERT INTO arachnid_storyteller_camera_points
      (scene_id,label,message,sort_order,x,y,z,heading,fov,hold_duration,transition_duration,created_by)
      VALUES (?,?,?,?,?,?,?,?,?,?,?,?)]], {
      sceneId, 'Shot ' .. sortOrder, '', sortOrder, position.x, position.y, position.z, heading,
      Config.Camera.defaultFov, Config.Camera.defaultHoldDuration, Config.Camera.defaultTransitionDuration, actorName(src)
    })
    MySQL.update.await('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actorName(src), scene.story_id })
    return { id = id, sceneId = sceneId, storyId = scene.story_id, distance = distance }
  end)
  if not ok or not point then return feedback(src, 'Camera point capture failed: ' .. tostring(ok and reason or point)) end
  logAction(src, ('Captured camera point #%s for scene #%s at %.1fm'):format(tostring(point.id), tostring(sceneId), point.distance))
  TriggerClientEvent('arachnid_storyteller:select', src, { storyId = point.storyId, sceneId = point.sceneId, cameraPointId = point.id })
  feedback(src, ('Camera point %s captured %.1fm ahead.'):format(tostring(point.id), point.distance))
end)

RegisterNetEvent('arachnid_storyteller:cameraPointSave', function(raw)
  local src = source
  if not canManage(src) or not databaseReady or type(raw) ~= 'table' then return end
  local id = positiveInteger(raw.id)
  local label = cleanText(raw.label, Config.Limits.cameraLabel, true)
  local message = cleanText(raw.message or '', Config.Limits.cameraMessage, false)
  local sortOrder = positiveInteger(raw.sortOrder)
  local fov = boundedNumber(raw.fov, 15, Config.Camera.maxFov)
  local holdDuration = boundedNumber(raw.holdDuration, 0, Config.Camera.maxHoldDuration)
  local transitionDuration = boundedNumber(raw.transitionDuration, 0, Config.Camera.maxTransitionDuration)
  if not id or not label or message == nil or not sortOrder or not fov or holdDuration == nil or transitionDuration == nil then
    return feedback(src, 'Camera point label, order, FOV, hold, or transition settings are invalid.')
  end
  local ok, point, reason = pcall(function()
    local rows = MySQL.query.await([[SELECT points.id,points.scene_id,scenes.story_id
      FROM arachnid_storyteller_camera_points AS points
      INNER JOIN arachnid_storyteller_scenes AS scenes ON scenes.id=points.scene_id
      WHERE points.id=? LIMIT 1]], { id })
    if type(rows) ~= 'table' or not rows[1] then return nil, 'That camera point no longer exists.' end
    local record = rows[1]
    MySQL.update.await([[UPDATE arachnid_storyteller_camera_points
      SET label=?,message=?,sort_order=?,fov=?,hold_duration=?,transition_duration=? WHERE id=?]],
      { label, message, sortOrder, fov, holdDuration, transitionDuration, id })
    MySQL.update.await('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actorName(src), record.story_id })
    return { id = id, sceneId = record.scene_id, storyId = record.story_id }
  end)
  if not ok or not point then return feedback(src, 'Camera point save failed: ' .. tostring(ok and reason or point)) end
  logAction(src, ('Updated camera point #%s: %s'):format(tostring(id), label:sub(1, 80)))
  TriggerClientEvent('arachnid_storyteller:select', src, { storyId = point.storyId, sceneId = point.sceneId, cameraPointId = point.id })
  feedback(src, 'Camera point saved.')
end)

RegisterNetEvent('arachnid_storyteller:cameraPointDelete', function(rawId)
  local src = source
  if not canManage(src) or not databaseReady then return end
  local id = positiveInteger(rawId)
  if not id then return feedback(src, 'Invalid camera point identifier.') end
  local ok, point, reason = pcall(function()
    local rows = MySQL.query.await([[SELECT points.scene_id,points.label,scenes.story_id
      FROM arachnid_storyteller_camera_points AS points
      INNER JOIN arachnid_storyteller_scenes AS scenes ON scenes.id=points.scene_id
      WHERE points.id=? LIMIT 1]], { id })
    if type(rows) ~= 'table' or not rows[1] then return nil, 'That camera point no longer exists.' end
    local record = rows[1]
    MySQL.update.await('DELETE FROM arachnid_storyteller_camera_points WHERE id=?', { id })
    MySQL.update.await('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actorName(src), record.story_id })
    return record
  end)
  if not ok or not point then return feedback(src, 'Camera point deletion failed: ' .. tostring(ok and reason or point)) end
  logAction(src, ('Deleted camera point #%s: %s'):format(tostring(id), tostring(point.label):sub(1, 80)))
  feedback(src, 'Camera point deleted.')
end)

RegisterNetEvent('arachnid_storyteller:sceneCutsceneSettingsSave', function(raw)
  local src = source
  if not canManage(src) or not databaseReady or type(raw) ~= 'table' then return end
  local sceneId = positiveInteger(raw.sceneId)
  local settings, reason = normalizedCutsceneSettings(raw.settings)
  if not sceneId or not settings then return feedback(src, reason or 'Invalid scene identifier.') end
  local scene = sceneRecord(sceneId)
  if not scene then return feedback(src, 'That scene no longer exists.') end
  local actor = actorName(src)
  local ok, err = pcall(function()
    MySQL.insert.await([[INSERT INTO arachnid_storyteller_cutscene_settings (scene_id,settings_json,updated_by)
      VALUES (?,?,?) ON DUPLICATE KEY UPDATE settings_json=VALUES(settings_json),updated_by=VALUES(updated_by)]],
      { sceneId, json.encode(settings), actor })
    MySQL.update.await('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actor, scene.story_id })
  end)
  if not ok then return feedback(src, 'Cutscene settings could not be saved: ' .. tostring(err)) end
  logAction(src, ('Saved cutscene settings for scene #%s'):format(tostring(sceneId)))
  TriggerClientEvent('arachnid_storyteller:select', src, { storyId = scene.story_id, sceneId = sceneId })
  feedback(src, 'Cutscene settings saved.')
  sendData(src, false)
end)

RegisterNetEvent('arachnid_storyteller:areaSave', function(raw)
  local src = source
  if not canManage(src) or not databaseReady or type(raw) ~= 'table' then return end
  local id = nil
  if raw.id ~= nil and raw.id ~= '' then id = positiveInteger(raw.id) end
  local label = cleanText(raw.label, Config.Limits.areaLabel, true)
  local shape = type(raw.shape) == 'string' and raw.shape:lower() or nil
  local radius, width, depth, height
  if shape == 'sphere' then
    radius = boundedNumber(raw.radius, Config.Areas.minRadius, Config.Areas.maxRadius)
    if radius then width, depth, height = radius * 2, radius * 2, radius * 2 end
  elseif shape == 'box' then
    width = boundedNumber(raw.width, Config.Areas.minDimension, Config.Areas.maxDimension)
    depth = boundedNumber(raw.depth, Config.Areas.minDimension, Config.Areas.maxDimension)
    height = boundedNumber(raw.height, Config.Areas.minDimension, Config.Areas.maxDimension)
    radius = 0
  end
  if not label or not areaShapes[shape] or not radius or not width or not depth or not height or
    (raw.id ~= nil and raw.id ~= '' and not id) then
    return feedback(src, 'Area label, shape, dimensions, or identifier are invalid.')
  end
  local position = currentPosition(src)
  if not position then
    return feedback(src, 'Current position is unavailable. Ensure OneSync is enabled and try again.')
  end
  local actor = actorName(src)
  local ok, result, action = pcall(function()
    if id then
      if not areaRecord(id) then return nil, 'That area no longer exists.' end
      MySQL.update.await([[UPDATE arachnid_storyteller_areas
        SET label=?,shape=?,x=?,y=?,z=?,radius=?,width=?,depth=?,height=? WHERE id=?]], {
        label, shape, position.x, position.y, position.z, radius, width, depth, height, id
      })
      return id, 'updated'
    end
    local newId = MySQL.insert.await([[INSERT INTO arachnid_storyteller_areas
      (label,shape,x,y,z,radius,width,depth,height,created_by) VALUES (?,?,?,?,?,?,?,?,?,?)]], {
      label, shape, position.x, position.y, position.z, radius, width, depth, height, actor
    })
    return newId, 'created'
  end)
  if not ok or not result then return feedback(src, 'Area save failed: ' .. tostring(ok and action or result)) end
  logAction(src, ('%s %s area #%s at %.2f, %.2f, %.2f: %s'):format(
    action, shape, tostring(result), position.x, position.y, position.z, label:sub(1, 80)))
  TriggerClientEvent('arachnid_storyteller:select', src, { areaId = result })
  feedback(src, 'Area ' .. action .. '.')
end)

RegisterNetEvent('arachnid_storyteller:areaDelete', function(rawId)
  local src = source
  if not canManage(src) or not databaseReady then return end
  local id = positiveInteger(rawId)
  if not id then return feedback(src, 'Invalid area identifier.') end
  local ok, area, reason = pcall(function()
    local record = areaRecord(id)
    if not record then return nil, 'That area no longer exists.' end
    MySQL.update.await('DELETE FROM arachnid_storyteller_areas WHERE id=?', { id })
    return record
  end)
  if not ok or not area then return feedback(src, 'Area deletion failed: ' .. tostring(ok and reason or area)) end
  logAction(src, ('Deleted %s area #%s: %s'):format(tostring(area.shape), tostring(id), tostring(area.label):sub(1, 80)))
  feedback(src, 'Area deleted.')
end)

RegisterNetEvent('arachnid_storyteller:flowSave', function(raw)
  local src = source
  if not canManage(src) or not databaseReady or type(raw) ~= 'table' then return end
  local storyId = positiveInteger(raw.storyId)
  if not storyId or not storyExists(storyId) then return feedback(src, 'Choose an existing story before saving its flow.') end
  local graph, reason = validateFlowGraph(raw.graph, storyId, false)
  if not graph then return feedback(src, 'Flow could not be saved: ' .. tostring(reason)) end
  local actor = actorName(src)
  local ok, err = pcall(function()
    if #graph.nodes == 0 then
      MySQL.update.await('DELETE FROM arachnid_storyteller_flows WHERE story_id=?', { storyId })
    else
      MySQL.insert.await([[INSERT INTO arachnid_storyteller_flows (story_id,graph_json,updated_by)
        VALUES (?,?,?) ON DUPLICATE KEY UPDATE graph_json=VALUES(graph_json),updated_by=VALUES(updated_by)]], {
        storyId, json.encode(graph), actor
      })
    end
    MySQL.update.await('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actor, storyId })
  end)
  if not ok then return feedback(src, 'Flow save failed: ' .. tostring(err)) end
  logAction(src, ('Saved flow graph for story #%s (%d nodes, %d links)'):format(tostring(storyId), #graph.nodes, #graph.links))
  TriggerClientEvent('arachnid_storyteller:select', src, { storyId = storyId })
  feedback(src, #graph.nodes == 0 and 'Flow graph cleared; this story uses manual scene control.' or 'Flow graph saved.')
end)

RegisterNetEvent('arachnid_storyteller:teleportSave', function(raw)
  local src = source
  if not canManage(src) or not databaseReady or type(raw) ~= 'table' then return end
  local storyId = positiveInteger(raw.storyId)
  local id = raw.id ~= nil and raw.id ~= '' and positiveInteger(raw.id) or nil
  local label = cleanText(raw.label, Config.Limits.teleportLabel, true)
  if not storyId or not storyExists(storyId) or not label or (raw.id ~= nil and raw.id ~= '' and not id) then
    return feedback(src, 'Teleport marker story, label, or identifier is invalid.')
  end
  local existing = id and teleportRecord(id, storyId) or nil
  if id and not existing then return feedback(src, 'That teleport marker no longer exists in this story.') end
  local capturePosition = raw.capturePosition == true or not existing
  local position, heading
  if capturePosition then
    position = currentPosition(src)
    local ped = GetPlayerPed(src)
    if not position or not ped or ped == 0 then return feedback(src, 'Current position is unavailable. Ensure OneSync is enabled and try again.') end
    heading = math.floor(GetEntityHeading(ped) * 100) / 100
  end
  local actor = actorName(src)
  local ok, result = pcall(function()
    if existing then
      if capturePosition then
        MySQL.update.await([[UPDATE arachnid_storyteller_teleports SET label=?,x=?,y=?,z=?,heading=? WHERE id=? AND story_id=?]], {
          label, position.x, position.y, position.z, heading, id, storyId
        })
      else
        MySQL.update.await('UPDATE arachnid_storyteller_teleports SET label=? WHERE id=? AND story_id=?', { label, id, storyId })
      end
      return id
    end
    return MySQL.insert.await([[INSERT INTO arachnid_storyteller_teleports
      (story_id,label,x,y,z,heading,created_by) VALUES (?,?,?,?,?,?,?)]], {
      storyId, label, position.x, position.y, position.z, heading, actor
    })
  end)
  if not ok or not result then return feedback(src, 'Teleport marker save failed: ' .. tostring(result)) end
  MySQL.update('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actor, storyId })
  logAction(src, ('Saved teleport marker #%s for story #%s: %s'):format(tostring(result), tostring(storyId), label:sub(1, 80)))
  TriggerClientEvent('arachnid_storyteller:select', src, { storyId = storyId, teleportMarkerId = result })
  feedback(src, existing and 'Teleport marker updated.' or 'Teleport marker created.')
end)

RegisterNetEvent('arachnid_storyteller:teleportDelete', function(rawId, rawStoryId)
  local src = source
  if not canManage(src) or not databaseReady then return end
  local id, storyId = positiveInteger(rawId), positiveInteger(rawStoryId)
  if not id or not storyId then return feedback(src, 'Invalid teleport marker or story identifier.') end
  local marker = teleportRecord(id, storyId)
  if not marker then return feedback(src, 'That teleport marker no longer exists in this story.') end
  MySQL.update.await('DELETE FROM arachnid_storyteller_teleports WHERE id=? AND story_id=?', { id, storyId })
  MySQL.update('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actorName(src), storyId })
  logAction(src, ('Deleted teleport marker #%s from story #%s: %s'):format(tostring(id), tostring(storyId), tostring(marker.label):sub(1, 80)))
  feedback(src, 'Teleport marker deleted.')
end)

RegisterNetEvent('arachnid_storyteller:spawnPointSave', function(raw)
  local src = source
  if not canManage(src) or not databaseReady or type(raw) ~= 'table' then return end
  local storyId = positiveInteger(raw.storyId)
  local id = raw.id ~= nil and raw.id ~= '' and positiveInteger(raw.id) or nil
  local label = cleanText(raw.label, Config.Limits.spawnPointLabel, true)
  local kind = type(raw.kind) == 'string' and raw.kind:lower() or nil
  if not storyId or not storyExists(storyId) or not label or not ({ npc = true, prop = true, patrol = true })[kind] or
    (raw.id ~= nil and raw.id ~= '' and not id) then
    return feedback(src, 'Spawn marker story, label, kind, or identifier is invalid.')
  end
  local existing
  if id then
    local rows = MySQL.query.await('SELECT id FROM arachnid_storyteller_spawn_points WHERE id=? AND story_id=? LIMIT 1', { id, storyId }) or {}
    existing = rows[1]
    if not existing then return feedback(src, 'That spawn marker no longer exists in this story.') end
  end
  local capture = raw.capturePosition == true or not existing
  local position, heading
  if capture then
    position = currentPosition(src)
    local ped = GetPlayerPed(src)
    if not position or not ped or ped == 0 then return feedback(src, 'Current position is unavailable. Ensure OneSync is enabled and try again.') end
    heading = math.floor(GetEntityHeading(ped) * 100) / 100
  end
  local actor = actorName(src)
  local ok, result = pcall(function()
    if existing then
      if capture then
        MySQL.update.await([[UPDATE arachnid_storyteller_spawn_points
          SET label=?,kind=?,x=?,y=?,z=?,heading=? WHERE id=? AND story_id=?]],
          { label, kind, position.x, position.y, position.z, heading, id, storyId })
      else
        MySQL.update.await('UPDATE arachnid_storyteller_spawn_points SET label=?,kind=? WHERE id=? AND story_id=?', { label, kind, id, storyId })
      end
      return id
    end
    return MySQL.insert.await([[INSERT INTO arachnid_storyteller_spawn_points
      (story_id,label,kind,x,y,z,heading,created_by) VALUES (?,?,?,?,?,?,?,?)]],
      { storyId, label, kind, position.x, position.y, position.z, heading, actor })
  end)
  if not ok or not result then return feedback(src, 'Spawn marker save failed: ' .. tostring(result)) end
  MySQL.update('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actor, storyId })
  logAction(src, ('Saved %s spawn marker #%s for story #%s: %s'):format(kind, tostring(result), tostring(storyId), label:sub(1, 80)))
  TriggerClientEvent('arachnid_storyteller:select', src, { storyId = storyId, spawnPointId = result })
  feedback(src, 'Spawn marker saved.')
end)

RegisterNetEvent('arachnid_storyteller:spawnPointDelete', function(rawId, rawStoryId)
  local src = source
  if not canManage(src) or not databaseReady then return end
  local id, storyId = positiveInteger(rawId), positiveInteger(rawStoryId)
  if not id or not storyId then return feedback(src, 'Invalid spawn marker or story identifier.') end
  local rows = MySQL.query.await('SELECT label,kind FROM arachnid_storyteller_spawn_points WHERE id=? AND story_id=? LIMIT 1', { id, storyId }) or {}
  if not rows[1] then return feedback(src, 'That spawn marker no longer exists in this story.') end
  MySQL.update.await('DELETE FROM arachnid_storyteller_spawn_points WHERE id=? AND story_id=?', { id, storyId })
  MySQL.update('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actorName(src), storyId })
  logAction(src, ('Deleted %s spawn marker #%s from story #%s: %s'):format(tostring(rows[1].kind), tostring(id), tostring(storyId), tostring(rows[1].label):sub(1, 80)))
  feedback(src, 'Spawn marker deleted.')
end)

RegisterNetEvent('arachnid_storyteller:sessionStart', function(raw)
  local src = source
  if not canManage(src) or not databaseReady then return end
  local storyId = positiveInteger(type(raw) == 'table' and raw.storyId or raw)
  if not storyId then return feedback(src, 'Invalid story identifier.') end
  if activeSession then return feedback(src, 'A live session is already running. End it before starting another.') end
  local audienceOk, audience, audienceError = pcall(validatedAudience,
    type(raw) == 'table' and raw.audienceMode or 'all',
    type(raw) == 'table' and raw.participantIds or nil,
    type(raw) == 'table' and raw.areaId or nil
  )
  if not audienceOk then return feedback(src, 'Audience validation failed: ' .. tostring(audience)) end
  if not audience then return feedback(src, audienceError) end
  local ok, story, reason = pcall(storyForSession, storyId)
  if not ok or not story then return feedback(src, 'Session start failed: ' .. tostring(ok and reason or story)) end
  local flowGraph, flowMeta
  if story.flow and type(story.flow.nodes) == 'table' and #story.flow.nodes > 0 then
    local validCall, normalized, validationError, metadata = pcall(validateFlowGraph, story.flow, storyId, true)
    if not validCall then return feedback(src, 'Flow validation failed: ' .. tostring(normalized)) end
    if not normalized then return feedback(src, 'Flow cannot start: ' .. tostring(validationError)) end
    flowGraph, flowMeta = normalized, metadata
    if flowMeta.hasPlayerActions and not IsPlayerAceAllowed(src, Config.Ace.playerActions) then
      return feedback(src, 'You need the Arachnid Storyteller player-action ACE permission to start this flow.')
    end
    for family, required in pairs(flowMeta.featureFamilies or {}) do
      if required and not IsPlayerAceAllowed(src, Config.Ace[family]) then
        return feedback(src, ('You need the Arachnid Storyteller %s ACE permission to start this flow.'):format(family))
      end
    end
  end
  local actor = actorName(src)
  local actorIdentifier = GetPlayerIdentifierByType(src, 'license') or GetPlayerIdentifier(src, 0) or tostring(src)
  activeSession = {
    storyId = story.id,
    storyTitle = story.title,
    scenes = story.scenes,
    sceneIndex = 1,
    audience = audience,
    spawnPoints = story.spawnPoints or {},
    entities = { npcs = {}, props = {} },
    startedAt = os.time(),
    startedBy = actor,
    startedBySource = src,
    startedByIdentifier = actorIdentifier,
    runtimeId = ('%s:%s:%s'):format(tostring(os.time()), tostring(GetGameTimer()), tostring(src))
  }
  if flowGraph then
    local startId
    for id, node in pairs(flowMeta.nodes) do if node.type == 'start' then startId = id break end end
    activeSession.flowRuntime = {
      graph = flowGraph,
      nodes = flowMeta.nodes,
      outgoing = flowMeta.outgoing,
      areas = flowMeta.areas,
      teleports = flowMeta.teleports,
      featureFamilies = flowMeta.featureFamilies,
      spawnPoints = flowMeta.spawnPoints,
      queue = { { nodeId = startId, inputPort = 'in' } },
      waiters = {},
      joinArrivals = {},
      joinFired = {},
      variables = {},
      paused = false
    }
    activeSession.objective = { text = '', status = 'none', updatedAt = os.time(), updatedBy = actorName(src) }
  else
    activateSessionScene(1, actorName(src))
  end
  logAction(src, ('Started live session for story #%s (%s audience): %s'):format(tostring(story.id), audience.mode, story.title:sub(1, 80)))
  broadcastSession('started')
  if flowGraph then
    flowTick()
    feedback(src, 'Live flow started.')
  else
    feedback(src, 'Live session started at scene 1 of ' .. #story.scenes .. '.')
  end
end)

RegisterNetEvent('arachnid_storyteller:cutscenePreview', function(rawSceneId)
  local src = source
  if not canManage(src) then return end
  if activeSession then return feedback(src, 'Local cutscene preview is available when no live session is active.') end
  if Config.Cutscenes.enabled ~= true or not IsPlayerAceAllowed(src, Config.Ace.cutscenes) then
    return feedback(src, 'Cutscene playback is disabled or you lack the cutscenes ACE permission.')
  end
  local sceneId = positiveInteger(rawSceneId)
  local scene = sceneId and MySQL.query.await('SELECT id,title FROM arachnid_storyteller_scenes WHERE id=? LIMIT 1', { sceneId }) or {}
  scene = type(scene) == 'table' and scene[1] or nil
  if not scene then return feedback(src, 'Choose an existing scene beat.') end
  scene.cutscene_settings = sceneCutsceneSettings(sceneId)
  local payload, reason = cutscenePayload(scene, scene.cutscene_settings)
  if not payload then return feedback(src, reason) end
  payload.localPreview = true
  TriggerClientEvent('arachnid_storyteller:cutscenePlay', src, payload)
  feedback(src, 'Local cutscene preview started.')
end)

RegisterNetEvent('arachnid_storyteller:cutscenePreviewStop', function()
  local src = source
  if not canManage(src) or activeSession then return end
  if Config.Cutscenes.enabled ~= true or not IsPlayerAceAllowed(src, Config.Ace.cutscenes) then
    return feedback(src, 'Cutscene playback is disabled or you lack the cutscenes ACE permission.')
  end
  TriggerClientEvent('arachnid_storyteller:cutsceneStop', src)
  feedback(src, 'Local cutscene preview stopped.')
end)

RegisterNetEvent('arachnid_storyteller:sessionEncounterAction', function(raw)
  local src = source
  if not canManage(src) or not activeSession or type(raw) ~= 'table' then return end
  if Config.Encounters.enabled ~= true or not IsPlayerAceAllowed(src, Config.Ace.encounters) then
    return feedback(src, 'Encounters are disabled or you lack the encounters ACE permission.')
  end
  local action = type(raw.action) == 'string' and raw.action or ''
  local rtsActions = { rts_move = true, rts_move_point = true, rts_patrol = true, rts_stop = true, rts_stance = true, rts_target = true, rts_weapon = true }
  if rtsActions[action] then
    if Config.Rts.enabled ~= true then return feedback(src, 'The NPC RTS tool is disabled by the server owner.') end
    local ok, actionOk, reason = pcall(applyRtsCommand, activeSession, action, raw)
    if not ok or not actionOk then return feedback(src, 'RTS command failed: ' .. tostring(ok and reason or actionOk)) end
    logAction(src, ('Issued NPC RTS order %s for story #%s'):format(action, tostring(activeSession.storyId)))
    TriggerClientEvent('arachnid_storyteller:rtsSnapshot', src, rtsSnapshotPayload(activeSession))
    feedback(src, 'NPC order issued.')
    return
  end
  local allowed = {
    spawn_npc = true, spawn_npc_group = true, remove_npc = true, make_npc_hostile = true,
    set_npc_target = true, patrol_route = true, stop_patrol = true, spawn_prop = true, delete_prop = true
  }
  if not allowed[action] then return feedback(src, 'Choose a supported encounter action.') end
  local data = {}
  if action == 'spawn_npc' or action == 'spawn_npc_group' then
    data.model = type(raw.model) == 'string' and raw.model or ''
    data.spawnPointId = positiveInteger(raw.spawnPointId)
    local modelEntry = allowedEncounterModel('ped', data.model)
    data.health = boundedNumber(raw.health or 150, 1, maxPedHealth(modelEntry))
    data.count = action == 'spawn_npc_group' and boundedNumber(raw.count, 1, Config.Encounters.maxGroupCount) or 1
    if not modelEntry or not encounterMarker(activeSession, data.spawnPointId, 'npc') or
      data.health == nil or data.health % 1 ~= 0 or data.count == nil or data.count % 1 ~= 0 then
      return feedback(src, 'NPC model, spawn marker, count, or health is outside the configured limits.')
    end
  elseif action == 'spawn_prop' then
    data.model = type(raw.model) == 'string' and raw.model or ''
    data.spawnPointId = positiveInteger(raw.spawnPointId)
    if not allowedEncounterModel('prop', data.model) or not encounterMarker(activeSession, data.spawnPointId, 'prop') then
      return feedback(src, 'Prop model or spawn marker is not configured for this story.')
    end
  elseif action == 'set_npc_target' then
    data.target = raw.target == 'all' and 'all' or raw.target == 'random' and 'random' or nil
    if not data.target then return feedback(src, 'Choose all participants or one random participant as the NPC target.') end
  elseif action == 'patrol_route' then
    if not isDenseArray(raw.markerIds, 20) or #raw.markerIds < 2 then return feedback(src, 'Select at least two patrol waypoints.') end
    data.markerIds = {}
    for _, rawMarker in ipairs(raw.markerIds) do
      local markerId = positiveInteger(rawMarker)
      if not markerId or not encounterMarker(activeSession, markerId, 'patrol') then return feedback(src, 'A patrol waypoint does not belong to this story.') end
      data.markerIds[#data.markerIds + 1] = markerId
    end
    data.waitSeconds = boundedNumber(raw.waitSeconds == nil and 3 or raw.waitSeconds, 0, Config.Encounters.maxPatrolWaitSeconds)
    data.speed = boundedNumber(raw.speed or Config.Encounters.defaultPatrolSpeed, Config.Encounters.minPatrolSpeed, Config.Encounters.maxPatrolSpeed)
    if data.waitSeconds == nil or data.speed == nil then return feedback(src, 'Patrol pace or waypoint time exceeds the configured limits.') end
  end
  local ok, actionOk, reason = pcall(applyEncounterAction, activeSession, action, data)
  if not ok or not actionOk then return feedback(src, 'Encounter action failed: ' .. tostring(ok and reason or actionOk)) end
  logAction(src, ('Ran encounter action %s in story #%s'):format(action, tostring(activeSession.storyId)))
  flowTick()
  feedback(src, 'Encounter action completed.')
end)

AddEventHandler('weaponDamageEvent', function(sender, data)
  local session = activeSession
  local attacker = positiveInteger(sender)
  if not session or not attacker or not isAudienceMember(session, attacker) or type(data) ~= 'table' or type(NetworkGetEntityFromNetworkId) ~= 'function' then return end
  local netIds = type(data.hitGlobalIds) == 'table' and data.hitGlobalIds or { data.hitGlobalId }
  for _, rawNetId in ipairs(netIds) do
    local netId = positiveInteger(rawNetId)
    if netId then
      local okEntity, damagedEntity = pcall(NetworkGetEntityFromNetworkId, netId)
      if okEntity and damagedEntity and damagedEntity ~= 0 then
        for _, npc in ipairs(sessionEncounterList(session, 'npc')) do
          if npc.entity == damagedEntity and npc.stance == 'return_fire' and not encounterEntityDead(npc.entity) then
            taskNpcCombat(npc, attacker, true)
          end
        end
      end
    end
  end
end)

RegisterNetEvent('arachnid_storyteller:sessionWorldAction', function(raw)
  local src = source
  if not canManage(src) or not activeSession or type(raw) ~= 'table' then return end
  if Config.World.enabled ~= true or not IsPlayerAceAllowed(src, Config.Ace.world) then
    return feedback(src, 'World controls are disabled or you lack the world ACE permission.')
  end
  local targetId = type(raw.targetId) == 'string' and raw.targetId or ''
  local action = type(raw.action) == 'string' and raw.action or ''
  local supported = { open = true, close = true, lock = true, unlock = true, enable = true, disable = true, trigger = true }
  if not supported[action] then return feedback(src, 'Choose a supported registered world operation.') end
  local ok, actionOk, reason = pcall(applyWorldAction, activeSession, targetId, action)
  if not ok or not actionOk then return feedback(src, 'World action failed: ' .. tostring(ok and reason or actionOk)) end
  logAction(src, ('Ran registered world action %s on target %s in story #%s'):format(action, targetId, tostring(activeSession.storyId)))
  feedback(src, 'World action completed.')
end)

RegisterNetEvent('arachnid_storyteller:sessionEffectAction', function(raw)
  local src = source
  if not canManage(src) or not activeSession or type(raw) ~= 'table' then return end
  if Config.Effects.enabled ~= true or not IsPlayerAceAllowed(src, Config.Ace.effects) then
    return feedback(src, 'Audio and visual effects are disabled or you lack the effects ACE permission.')
  end
  local kind = type(raw.kind) == 'string' and raw.kind or ''
  if not flowFeatureNodes.effects[kind] then return feedback(src, 'Choose a supported story effect.') end
  local data, reason = normalizeEffectData(kind, raw.data)
  if not data then return feedback(src, reason) end
  local ok, actionOk, actionError = pcall(applyStoryEffect, activeSession, kind, data)
  if not ok or not actionOk then return feedback(src, 'Story effect failed: ' .. tostring(ok and actionError or actionOk)) end
  logAction(src, ('Ran session effect %s in story #%s'):format(kind, tostring(activeSession.storyId)))
  feedback(src, 'Story effect sent to the connected session audience.')
end)

RegisterNetEvent('arachnid_storyteller:sessionCutscenePlay', function(rawSceneId)
  local src = source
  if not canManage(src) or not activeSession then return end
  if Config.Cutscenes.enabled ~= true or not IsPlayerAceAllowed(src, Config.Ace.cutscenes) then
    return feedback(src, 'Cutscene playback is disabled or you lack the cutscenes ACE permission.')
  end
  local sceneId = positiveInteger(rawSceneId)
  if not sceneId then return feedback(src, 'Choose a valid scene beat.') end
  local ok, reason = startSessionCutscene(activeSession, sceneId)
  if not ok then return feedback(src, reason) end
  logAction(src, ('Played cutscene for scene #%s in story #%s'):format(tostring(sceneId), tostring(activeSession.storyId)))
  broadcastSession('cutscene_started')
  feedback(src, 'Cutscene playback started for the live audience.')
end)

RegisterNetEvent('arachnid_storyteller:sessionCutscenePause', function()
  local src = source
  if not canManage(src) or not activeSession then return end
  if Config.Cutscenes.enabled ~= true or not IsPlayerAceAllowed(src, Config.Ace.cutscenes) then
    return feedback(src, 'Cutscene playback is disabled or you lack the cutscenes ACE permission.')
  end
  if activeSession.flowRuntime then return feedback(src, 'Pause the flow to pause its active cutscene.') end
  if not activeSession.cutscene then return feedback(src, 'There is no active cutscene.') end
  if activeSession.cutscene.paused then return feedback(src, 'The audience cutscene is already paused.') end
  pauseSessionCutscene(activeSession)
  logAction(src, ('Paused cutscene in story #%s'):format(tostring(activeSession.storyId)))
  broadcastSession('cutscene_paused')
  feedback(src, 'Cutscene paused for the live audience.')
end)

RegisterNetEvent('arachnid_storyteller:sessionCutsceneResume', function()
  local src = source
  if not canManage(src) or not activeSession then return end
  if Config.Cutscenes.enabled ~= true or not IsPlayerAceAllowed(src, Config.Ace.cutscenes) then
    return feedback(src, 'Cutscene playback is disabled or you lack the cutscenes ACE permission.')
  end
  if activeSession.flowRuntime then return feedback(src, 'Resume the flow to resume its active cutscene.') end
  if not activeSession.cutscene then return feedback(src, 'There is no active cutscene.') end
  if not activeSession.cutscene.paused then return feedback(src, 'The audience cutscene is already running.') end
  resumeSessionCutscene(activeSession)
  logAction(src, ('Resumed cutscene in story #%s'):format(tostring(activeSession.storyId)))
  broadcastSession('cutscene_resumed')
  feedback(src, 'Cutscene resumed for the live audience.')
end)

RegisterNetEvent('arachnid_storyteller:sessionCutsceneStop', function()
  local src = source
  if not canManage(src) or not activeSession then return end
  if Config.Cutscenes.enabled ~= true or not IsPlayerAceAllowed(src, Config.Ace.cutscenes) then
    return feedback(src, 'Cutscene playback is disabled or you lack the cutscenes ACE permission.')
  end
  if not activeSession.cutscene then return feedback(src, 'There is no active cutscene.') end
  stopSessionCutscene(activeSession)
  logAction(src, ('Stopped cutscene in story #%s'):format(tostring(activeSession.storyId)))
  broadcastSession('cutscene_stopped')
  flowTick()
  feedback(src, 'Cutscene stopped.')
end)

RegisterNetEvent('arachnid_storyteller:sessionNext', function()
  local src = source
  if not canManage(src) or not activeSession then return end
  if activeSession.flowRuntime then return feedback(src, 'This session is following its saved flow. Pause it before changing controls.') end
  if activeSession.sceneIndex >= #activeSession.scenes then
    return feedback(src, 'The final scene beat is active. End the session when the story is complete.')
  end
  local scene = activateSessionScene(activeSession.sceneIndex + 1, actorName(src))
  logAction(src, ('Advanced live session #%s to scene #%s: %s'):format(
    tostring(activeSession.storyId), tostring(scene.id), scene.title:sub(1, 80)))
  broadcastSession('advanced')
  feedback(src, 'Advanced to scene ' .. activeSession.sceneIndex .. ' of ' .. #activeSession.scenes .. '.')
end)

RegisterNetEvent('arachnid_storyteller:sessionSelectScene', function(rawSceneId)
  local src = source
  if not canManage(src) or not activeSession then return end
  if activeSession.flowRuntime then return feedback(src, 'Scene jumps are unavailable while a saved flow is running.') end
  local sceneId = positiveInteger(rawSceneId)
  if not sceneId then return feedback(src, 'Invalid scene identifier.') end
  local targetIndex = nil
  for index, scene in ipairs(activeSession.scenes) do
    if tonumber(scene.id) == sceneId then targetIndex = index break end
  end
  if not targetIndex then return feedback(src, 'That scene is not part of the active session.') end
  local scene = activateSessionScene(targetIndex, actorName(src))
  logAction(src, ('Jumped live session #%s to scene #%s: %s'):format(
    tostring(activeSession.storyId), tostring(scene.id), scene.title:sub(1, 80)))
  broadcastSession('jumped')
  feedback(src, 'Running scene ' .. targetIndex .. ' of ' .. #activeSession.scenes .. '.')
end)

RegisterNetEvent('arachnid_storyteller:sessionStop', function()
  local src = source
  if not canManage(src) or not activeSession then return end
  endActiveSession('ended', src)
  feedback(src, 'Live session ended.')
end)

RegisterNetEvent('arachnid_storyteller:sessionPause', function()
  local src = source
  if not canManage(src) or not activeSession or not activeSession.flowRuntime then return end
  local runtime = activeSession.flowRuntime
  if runtime.paused then return feedback(src, 'The flow is already paused.') end
  for _, waiting in ipairs(runtime.waiters) do
    if waiting.kind == 'delay' and waiting.untilTime then
      waiting.remaining = math.max(0, waiting.untilTime - GetGameTimer())
      waiting.untilTime = nil
    end
  end
  pauseSessionCutscene(activeSession)
  runtime.paused = true
  logAction(src, ('Paused flow for live session #%s'):format(tostring(activeSession.storyId)))
  broadcastSession('flow_paused')
  feedback(src, 'Flow paused.')
end)

RegisterNetEvent('arachnid_storyteller:sessionResume', function()
  local src = source
  if not canManage(src) or not activeSession or not activeSession.flowRuntime then return end
  local runtime = activeSession.flowRuntime
  if not runtime.paused then return feedback(src, 'The flow is already running.') end
  for _, waiting in ipairs(runtime.waiters) do
    if waiting.kind == 'delay' and not waiting.untilTime then
      waiting.untilTime = GetGameTimer() + (waiting.remaining or 0)
      waiting.remaining = nil
    end
  end
  resumeSessionCutscene(activeSession)
  runtime.paused = false
  runtime.error = nil
  logAction(src, ('Resumed flow for live session #%s'):format(tostring(activeSession.storyId)))
  broadcastSession('flow_resumed')
  flowTick()
  feedback(src, 'Flow resumed.')
end)

RegisterNetEvent('arachnid_storyteller:sessionObjectiveSave', function(rawText)
  local src = source
  if not canManage(src) or not activeSession then return end
  local text = cleanText(rawText or '', Config.Limits.activeObjective, false)
  if text == nil then return feedback(src, 'Objective text is invalid.') end
  activeSession.objective = {
    text = text,
    status = text ~= '' and 'active' or 'none',
    updatedAt = os.time(),
    updatedBy = actorName(src)
  }
  logAction(src, ('Updated live objective for story #%s'):format(tostring(activeSession.storyId)))
  broadcastSession('objective_updated')
  feedback(src, text == '' and 'Live objective cleared.' or 'Live objective updated.')
end)

RegisterNetEvent('arachnid_storyteller:sessionObjectiveStatus', function(rawStatus)
  local src = source
  if not canManage(src) or not activeSession then return end
  local status = type(rawStatus) == 'string' and rawStatus:lower() or nil
  if not objectiveStatuses[status] then return feedback(src, 'Invalid objective status.') end
  local objective = activeSession.objective
  if not objective or tostring(objective.text or '') == '' then
    return feedback(src, 'Set a live objective before changing its status.')
  end
  objective.status = status
  objective.updatedAt = os.time()
  objective.updatedBy = actorName(src)
  logAction(src, ('Marked live objective %s for story #%s'):format(status, tostring(activeSession.storyId)))
  broadcastSession('objective_' .. status)
  flowTick()
  feedback(src, 'Live objective marked ' .. status .. '.')
end)

AddEventHandler('playerDropped', function()
  local leaving = tonumber(source)
  if leaving then frozenByArachnid[tostring(leaving)] = nil end
  if leaving and activeSession then
    for _, npc in ipairs(sessionEncounterList(activeSession, 'npc')) do
      if tonumber(npc.targetId) == leaving then stopNpcOrder(npc, false) end
    end
  end
  if not activeSession or not activeSession.audience or activeSession.audience.mode == 'all' then return end
  for index = #activeSession.audience.participants, 1, -1 do
    if tonumber(activeSession.audience.participants[index]) == leaving then
      table.remove(activeSession.audience.participants, index)
    end
  end
end)

RegisterNetEvent('arachnid_storyteller:storySave', function(raw)
  local src = source
  if not canManage(src) or not databaseReady or type(raw) ~= 'table' then return end
  local title = cleanText(raw.title, Config.Limits.storyTitle, true)
  local summary = cleanText(raw.summary or '', Config.Limits.storySummary, false)
  local status = type(raw.status) == 'string' and raw.status:lower() or nil
  local id = nil
  if raw.id ~= nil and raw.id ~= '' then id = positiveInteger(raw.id) end
  if not title or summary == nil or not statuses[status] or (raw.id ~= nil and raw.id ~= '' and not id) then
    return feedback(src, 'Story title, summary, status, or identifier is invalid.')
  end
  local actor = actorName(src)
  local ok, result, action = pcall(function()
    if id then
      if not storyExists(id) then return nil, 'That story no longer exists.' end
      MySQL.update.await([[UPDATE arachnid_storyteller_stories
        SET title=?,summary=?,status=?,updated_by=? WHERE id=?]], { title, summary, status, actor, id })
      return id, 'updated'
    end
    local newId = MySQL.insert.await([[INSERT INTO arachnid_storyteller_stories
      (title,summary,status,created_by,updated_by) VALUES (?,?,?,?,?)]], { title, summary, status, actor, actor })
    return newId, 'created'
  end)
  if not ok or not result then return feedback(src, 'Story save failed: ' .. tostring(ok and action or result)) end
  logAction(src, ('%s story #%s: %s'):format(action, tostring(result), title:sub(1, 80)))
  TriggerClientEvent('arachnid_storyteller:select', src, { storyId = result })
  feedback(src, 'Story ' .. action .. '.')
end)

RegisterNetEvent('arachnid_storyteller:storyDelete', function(rawId)
  local src = source
  if not canManage(src) or not databaseReady then return end
  local id = positiveInteger(rawId)
  if not id then return feedback(src, 'Invalid story identifier.') end
  local ok, title, reason = pcall(function()
    local rows = MySQL.query.await('SELECT title FROM arachnid_storyteller_stories WHERE id=? LIMIT 1', { id })
    if type(rows) ~= 'table' or not rows[1] then return nil, 'That story no longer exists.' end
    MySQL.update.await([[DELETE points FROM arachnid_storyteller_camera_points AS points
      INNER JOIN arachnid_storyteller_scenes AS scenes ON scenes.id=points.scene_id WHERE scenes.story_id=?]], { id })
    MySQL.update.await([[DELETE settings FROM arachnid_storyteller_cutscene_settings AS settings
      INNER JOIN arachnid_storyteller_scenes AS scenes ON scenes.id=settings.scene_id WHERE scenes.story_id=?]], { id })
    MySQL.update.await('DELETE FROM arachnid_storyteller_flows WHERE story_id=?', { id })
    MySQL.update.await('DELETE FROM arachnid_storyteller_teleports WHERE story_id=?', { id })
    MySQL.update.await('DELETE FROM arachnid_storyteller_spawn_points WHERE story_id=?', { id })
    MySQL.update.await('DELETE FROM arachnid_storyteller_scenes WHERE story_id=?', { id })
    MySQL.update.await('DELETE FROM arachnid_storyteller_stories WHERE id=?', { id })
    return rows[1].title
  end)
  if not ok or not title then return feedback(src, 'Story deletion failed: ' .. tostring(ok and reason or title)) end
  if activeSession and tonumber(activeSession.storyId) == id then
    endActiveSession('ended', src)
  end
  logAction(src, ('Deleted story #%d and its scene beats: %s'):format(id, tostring(title):sub(1, 80)))
  feedback(src, 'Story and its scene beats deleted.')
end)

RegisterNetEvent('arachnid_storyteller:sceneSave', function(raw)
  local src = source
  if not canManage(src) or not databaseReady or type(raw) ~= 'table' then return end
  local storyId = positiveInteger(raw.storyId)
  local title = cleanText(raw.title, Config.Limits.sceneTitle, true)
  local objective = cleanText(raw.objective or '', Config.Limits.sceneObjective, false)
  local sceneId = nil
  if raw.id ~= nil and raw.id ~= '' then sceneId = positiveInteger(raw.id) end
  local sortOrder = nil
  if raw.sortOrder ~= nil and raw.sortOrder ~= '' then sortOrder = positiveInteger(raw.sortOrder) end
  if not storyId or not title or objective == nil or (raw.id ~= nil and raw.id ~= '' and not sceneId) or
    ((raw.sortOrder ~= nil and raw.sortOrder ~= '') and (not sortOrder or sortOrder > Config.Limits.sceneOrder)) then
    return feedback(src, 'Scene title, objective, order, or identifier is invalid.')
  end
  local actor = actorName(src)
  local capturePosition = raw.capturePosition == true
  local ok, result, action = pcall(function()
    if not storyExists(storyId) then return nil, 'Choose an existing story first.' end
    local position = nil
    if capturePosition then
      position = currentPosition(src)
      if not position then return nil, 'Current position is unavailable. Ensure OneSync is enabled and try again.' end
    end
    if sceneId then
      local rows = MySQL.query.await('SELECT id,sort_order FROM arachnid_storyteller_scenes WHERE id=? AND story_id=? LIMIT 1', { sceneId, storyId })
      if type(rows) ~= 'table' or not rows[1] then return nil, 'That scene no longer exists in this story.' end
      sortOrder = sortOrder or tonumber(rows[1].sort_order) or 1
      if position then
        MySQL.update.await([[UPDATE arachnid_storyteller_scenes
          SET title=?,objective=?,sort_order=?,x=?,y=?,z=? WHERE id=? AND story_id=?]],
          { title, objective, sortOrder, position.x, position.y, position.z, sceneId, storyId })
      else
        MySQL.update.await([[UPDATE arachnid_storyteller_scenes
          SET title=?,objective=?,sort_order=? WHERE id=? AND story_id=?]], { title, objective, sortOrder, sceneId, storyId })
      end
      MySQL.update.await('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actor, storyId })
      return sceneId, 'updated'
    end
    if not sortOrder then
      local rows = MySQL.query.await('SELECT COALESCE(MAX(sort_order),0) AS max_order FROM arachnid_storyteller_scenes WHERE story_id=?', { storyId })
      sortOrder = ((rows and rows[1] and tonumber(rows[1].max_order)) or 0) + 1
    end
    local newId = MySQL.insert.await([[INSERT INTO arachnid_storyteller_scenes
      (story_id,title,objective,sort_order,x,y,z,created_by) VALUES (?,?,?,?,?,?,?,?)]],
      { storyId, title, objective, sortOrder, position and position.x or nil, position and position.y or nil, position and position.z or nil, actor })
    MySQL.update.await('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actor, storyId })
    return newId, 'created'
  end)
  if not ok or not result then return feedback(src, 'Scene save failed: ' .. tostring(ok and action or result)) end
  logAction(src, ('%s scene #%s in story #%d: %s'):format(action, tostring(result), storyId, title:sub(1, 80)))
  TriggerClientEvent('arachnid_storyteller:select', src, { storyId = storyId, sceneId = result })
  feedback(src, 'Scene beat ' .. action .. '.')
end)

RegisterNetEvent('arachnid_storyteller:sceneDelete', function(rawId)
  local src = source
  if not canManage(src) or not databaseReady then return end
  local id = positiveInteger(rawId)
  if not id then return feedback(src, 'Invalid scene identifier.') end
  local actor = actorName(src)
  local ok, scene, reason = pcall(function()
    local rows = MySQL.query.await('SELECT story_id,title FROM arachnid_storyteller_scenes WHERE id=? LIMIT 1', { id })
    if type(rows) ~= 'table' or not rows[1] then return nil, 'That scene no longer exists.' end
    MySQL.update.await('DELETE FROM arachnid_storyteller_camera_points WHERE scene_id=?', { id })
    MySQL.update.await('DELETE FROM arachnid_storyteller_cutscene_settings WHERE scene_id=?', { id })
    MySQL.update.await('DELETE FROM arachnid_storyteller_scenes WHERE id=?', { id })
    MySQL.update.await('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actor, rows[1].story_id })
    return rows[1]
  end)
  if not ok or not scene then return feedback(src, 'Scene deletion failed: ' .. tostring(ok and reason or scene)) end
  logAction(src, ('Deleted scene #%d from story #%s: %s'):format(id, tostring(scene.story_id), tostring(scene.title):sub(1, 80)))
  feedback(src, 'Scene beat deleted.')
end)

CreateThread(function()
  while true do
    Wait(Config.Flow.tickMs)
    flowTick()
    if activeSession then refreshRtsEngagements(activeSession) end
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    if activeSession then endActiveSession('ended', nil) end
    cleanupOwnedFreezes(nil)
    cleanupAllEncounterEntities()
  end
end)
