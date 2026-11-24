local databaseReady = false
local activeSession = nil
local statuses = { draft = true, published = true, archived = true }
local objectiveStatuses = { active = true, completed = true, failed = true }
local areaShapes = { sphere = true, box = true }
local frozenByArachnid = {}

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
  wait_objective = true, wait_area = true, ['end'] = true,
  send_message = true, freeze_players = true, unfreeze_players = true, set_health = true,
  set_armor = true, give_weapon = true, strip_weapon = true, strip_all_weapons = true,
  teleport_players = true, kill_players = true, respawn_players = true, change_job = true
}
local flowOutputs = {
  start = { next = true }, scene = { next = true }, delay = { next = true },
  branch = { ['true'] = true, ['false'] = true }, random_branch = { success = true, failure = true },
  set_variable = { next = true }, add_variable = { next = true }, subtract_variable = { next = true },
  objective = { next = true }, wait_objective = { completed = true, failed = true },
  wait_area = { next = true }, ['end'] = {},
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

  local graph = { nodes = {}, links = {} }
  local nodes, starts, ends, hasPlayerActions, hasVorpActions, hasRespawn, hasChangeJob = {}, 0, 0, false, false, false, false
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
    elseif kind == 'wait_area' then
      local areaId = positiveInteger(rawData.areaId)
      if not areaId or not areaById[tostring(areaId)] then return nil, 'An area wait references a missing saved area.' end
      data.areaId = areaId
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
    if not from or not to or from.type == 'end' or rawLink.toSocket ~= 'in' or to.type == 'start' or
      not flowOutputs[from.type][rawLink.fromSocket] then
      return nil, 'A flow connection uses a missing node or invalid port.'
    end
    local outputKey = rawLink.fromNode .. ':' .. rawLink.fromSocket
    if outgoing[outputKey] or incoming[rawLink.toNode] then return nil, 'Each output and input port can have only one connection.' end
    outgoing[outputKey] = rawLink.toNode
    incoming[rawLink.toNode] = true
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
    if hasVorpActions then
      local core, coreError = getVorpCore()
      if not core then return nil, coreError end
      if (hasRespawn and (type(core.Player) ~= 'table' or type(core.Player.Respawn) ~= 'function')) or
        (hasChangeJob and type(core.getUser) ~= 'function') then
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
      if node.type ~= 'start' and not incoming[id] then return nil, ('Connect an input to node %s.'):format(id) end
    end
  end
  return graph, nil, {
    nodes = nodes, outgoing = outgoing, areas = areaById, teleports = teleportById,
    hasPlayerActions = hasPlayerActions, hasVorpActions = hasVorpActions
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
    audience = {
      mode = current.audience and current.audience.mode or 'all',
      count = current.audience and current.audience.mode ~= 'all' and #(current.audience.participants or {}) or #GetPlayers(),
      areaLabel = current.audience and current.audience.areaLabel or nil
    },
    startedAt = current.startedAt,
    startedBy = current.startedBy,
    flow = current.flowRuntime and {
      state = current.flowRuntime.paused and 'paused' or 'running',
      waiting = current.flowRuntime.waiting and current.flowRuntime.waiting.kind or nil,
      nodeId = current.flowRuntime.waiting and current.flowRuntime.waiting.nodeId or current.flowRuntime.currentNode,
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

local function endActiveSession(mode, actor)
  if not activeSession then return end
  local ended = activeSession
  activeSession = nil
  cleanupOwnedFreezes(ended.runtimeId)
  if actor then logAction(actor, ('Ended live session for story #%s: %s'):format(tostring(ended.storyId), ended.storyTitle:sub(1, 80))) end
  broadcastSession(mode or 'ended', ended)
end

local function flowRoute(runtime, nodeId, port)
  local destination = runtime.outgoing[nodeId .. ':' .. port]
  if not destination then return nil end
  return destination
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

local function flowActionTargets(session, targetMode)
  local targets = flowAudiencePlayers(session)
  if targetMode == 'random' then
    if #targets == 0 then return {} end
    return { targets[math.random(1, #targets)] }
  end
  return targets
end

local function vorpCharacterFor(sourceId, core)
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
  if not activeSession or not activeSession.flowRuntime then return end
  local session, runtime = activeSession, activeSession.flowRuntime
  if runtime.paused then return end
  local waiting = runtime.waiting
  if waiting then
    local ready, port = false, waiting.port
    if waiting.kind == 'delay' then
      ready = waiting.untilTime and GetGameTimer() >= waiting.untilTime or false
    elseif waiting.kind == 'objective' then
      local status = session.objective and session.objective.status
      if status == 'completed' or status == 'failed' then ready, port = true, status end
    elseif waiting.kind == 'area' then
      ready = flowAreaSatisfied(session, waiting.area)
    end
    if not ready then return end
    runtime.waiting = nil
    runtime.currentNode = flowRoute(runtime, waiting.nodeId, port)
  end

  local steps = 0
  while activeSession == session and not runtime.paused and runtime.currentNode and steps < Config.Flow.maxStepsPerTick do
    local node = runtime.nodes[runtime.currentNode]
    if not node then return flowFault('Flow reached a missing node.') end
    runtime.currentNode = nil
    steps = steps + 1
    local nextPort = 'next'
    if node.type == 'start' then
      runtime.currentNode = flowRoute(runtime, node.id, nextPort)
    elseif node.type == 'scene' then
      local targetIndex
      for index, scene in ipairs(session.scenes) do if tonumber(scene.id) == tonumber(node.data.sceneId) then targetIndex = index break end end
      if not targetIndex then return flowFault('A scene referenced by the active flow was removed.') end
      activateSessionScene(targetIndex, session.startedBy)
      broadcastSession('flow_scene')
      runtime.currentNode = flowRoute(runtime, node.id, nextPort)
    elseif node.type == 'delay' then
      if node.data.seconds <= 0 then
        runtime.currentNode = flowRoute(runtime, node.id, nextPort)
      else
        runtime.waiting = { kind = 'delay', nodeId = node.id, port = nextPort, untilTime = GetGameTimer() + math.floor(node.data.seconds * 1000) }
        broadcastSession('flow_waiting')
        return
      end
    elseif node.type == 'branch' then
      runtime.currentNode = flowRoute(runtime, node.id, flowCompare(runtime, node.data) and 'true' or 'false')
    elseif node.type == 'random_branch' then
      local succeeds = math.random(1, 10000) <= math.floor(node.data.chance * 100)
      runtime.currentNode = flowRoute(runtime, node.id, succeeds and 'success' or 'failure')
    elseif node.type == 'set_variable' then
      runtime.variables[node.data.variable] = { type = node.data.valueType, value = node.data.value }
      runtime.currentNode = flowRoute(runtime, node.id, nextPort)
    elseif node.type == 'add_variable' or node.type == 'subtract_variable' then
      local current = runtime.variables[node.data.variable]
      if current and current.type ~= 'number' then return flowFault('Add/subtract requires a numeric variable: ' .. node.data.variable) end
      local value = current and current.value or 0
      local amount = node.data.amount * (node.type == 'add_variable' and 1 or -1)
      local result = value + amount
      if result ~= result or math.abs(result) > Config.Flow.maxVariableNumber then return flowFault('Variable result exceeds the configured limit.') end
      runtime.variables[node.data.variable] = { type = 'number', value = result }
      runtime.currentNode = flowRoute(runtime, node.id, nextPort)
    elseif node.type == 'objective' then
      session.objective = { text = node.data.text, status = 'active', updatedAt = os.time(), updatedBy = session.startedBy }
      broadcastSession('objective_updated')
      runtime.currentNode = flowRoute(runtime, node.id, nextPort)
    elseif node.type == 'wait_objective' then
      local status = session.objective and session.objective.status
      if status == 'completed' or status == 'failed' then
        runtime.currentNode = flowRoute(runtime, node.id, status)
      else
        runtime.waiting = { kind = 'objective', nodeId = node.id }
        broadcastSession('flow_waiting')
        return
      end
    elseif node.type == 'wait_area' then
      local area = runtime.areas[tostring(node.data.areaId)]
      if not area then return flowFault('An area referenced by the active flow is unavailable.') end
      if flowAreaSatisfied(session, area) then
        runtime.currentNode = flowRoute(runtime, node.id, nextPort)
      else
        runtime.waiting = { kind = 'area', nodeId = node.id, port = nextPort, area = area }
        broadcastSession('flow_waiting')
        return
      end
    elseif flowActionSettings[node.type] then
      -- Advance before calling the effect so Resume cannot execute a partially
      -- completed action again if one target causes the node to pause.
      runtime.currentNode = flowRoute(runtime, node.id, nextPort)
      local callOk, actionOk, actionError = pcall(executePlayerAction, session, node)
      if not callOk then return flowFault(tostring(actionOk)) end
      if not actionOk then return flowFault(actionError) end
    elseif node.type == 'end' then
      if activeSession == session then endActiveSession('ended', session.startedBySource) end
      return
    else
      return flowFault('Flow contains an unsupported node type.')
    end
    if not runtime.currentNode and activeSession == session then return flowFault('Flow reached an unconnected output.') end
  end
  if steps >= Config.Flow.maxStepsPerTick and runtime.currentNode then broadcastSession('flow_running') end
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
  local flowRows = MySQL.query.await('SELECT graph_json FROM arachnid_storyteller_flows WHERE story_id=? LIMIT 1', { id }) or {}
  local flow = nil
  if flowRows[1] then
    local decoded, value = pcall(json.decode, flowRows[1].graph_json)
    if not decoded or type(value) ~= 'table' then return nil, 'Saved flow data is invalid; open and resave the graph.' end
    flow = value
  end
  return { id = story.id, title = story.title, scenes = scenes, flow = flow }
end

local function snapshot()
  local stories = MySQL.query.await([[SELECT id,title,summary,status,created_by,updated_by,created_at,updated_at
    FROM arachnid_storyteller_stories
    ORDER BY FIELD(status,'published','draft','archived'),updated_at DESC,id DESC]]) or {}
  local scenes = MySQL.query.await([[SELECT id,story_id,title,objective,sort_order,x,y,z,created_by,created_at,updated_at
    FROM arachnid_storyteller_scenes ORDER BY story_id ASC,sort_order ASC,id ASC]]) or {}
  local cameraPoints = MySQL.query.await([[SELECT id,scene_id,label,message,sort_order,x,y,z,heading,fov,hold_duration,
    transition_duration,created_by,created_at,updated_at FROM arachnid_storyteller_camera_points
    ORDER BY scene_id ASC,sort_order ASC,id ASC]]) or {}
  local areas = MySQL.query.await([[SELECT id,label,shape,x,y,z,radius,width,depth,height,created_by,created_at,updated_at
    FROM arachnid_storyteller_areas ORDER BY label ASC,id ASC]]) or {}
  local teleports = MySQL.query.await([[SELECT id,story_id,label,x,y,z,heading,created_by,created_at,updated_at
    FROM arachnid_storyteller_teleports ORDER BY story_id ASC,label ASC,id ASC]]) or {}
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
  for _, marker in ipairs(teleports) do
    teleportsByStory[marker.story_id] = teleportsByStory[marker.story_id] or {}
    teleportsByStory[marker.story_id][#teleportsByStory[marker.story_id] + 1] = marker
  end
  for _, scene in ipairs(scenes) do
    scene.camera_points = camerasByScene[scene.id] or {}
    scene.camera_point_count = #scene.camera_points
    scenesByStory[scene.story_id] = scenesByStory[scene.story_id] or {}
    scenesByStory[scene.story_id][#scenesByStory[scene.story_id] + 1] = scene
  end
  for _, story in ipairs(stories) do
    story.scenes = scenesByStory[story.id] or {}
    story.scene_count = #story.scenes
    story.flow = flowsByStory[tostring(story.id)]
    story.teleports = teleportsByStory[story.id] or {}
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
      maxDelaySeconds = Config.Flow.maxDelaySeconds
    },
    camera = {
      defaultPlacementDistance = Config.Camera.Tool.defaultPlacementDistance,
      maxPlacementDistance = Config.Camera.Tool.maxPlacementDistance,
      toolConfigured = Config.Camera.Tool.weapon ~= ''
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
  end
  local actor = actorName(src)
  local actorIdentifier = GetPlayerIdentifierByType(src, 'license') or GetPlayerIdentifier(src, 0) or tostring(src)
  activeSession = {
    storyId = story.id,
    storyTitle = story.title,
    scenes = story.scenes,
    sceneIndex = 1,
    audience = audience,
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
      currentNode = startId,
      variables = {},
      waiting = nil,
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
  if runtime.waiting and runtime.waiting.kind == 'delay' and runtime.waiting.untilTime then
    runtime.waiting.remaining = math.max(0, runtime.waiting.untilTime - GetGameTimer())
    runtime.waiting.untilTime = nil
  end
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
  if runtime.waiting and runtime.waiting.kind == 'delay' and not runtime.waiting.untilTime then
    runtime.waiting.untilTime = GetGameTimer() + (runtime.waiting.remaining or 0)
    runtime.waiting.remaining = nil
  end
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
    MySQL.update.await('DELETE FROM arachnid_storyteller_flows WHERE story_id=?', { id })
    MySQL.update.await('DELETE FROM arachnid_storyteller_teleports WHERE story_id=?', { id })
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
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then cleanupOwnedFreezes(nil) end
end)
