local databaseReady = false
local statuses = { draft = true, published = true, archived = true }

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

local function snapshot()
  local stories = MySQL.query.await([[SELECT id,title,summary,status,created_by,updated_by,created_at,updated_at
    FROM arachnid_storyteller_stories
    ORDER BY FIELD(status,'published','draft','archived'),updated_at DESC,id DESC]]) or {}
  local scenes = MySQL.query.await([[SELECT id,story_id,title,objective,sort_order,x,y,z,created_by,created_at,updated_at
    FROM arachnid_storyteller_scenes ORDER BY story_id ASC,sort_order ASC,id ASC]]) or {}
  local scenesByStory = {}
  for _, scene in ipairs(scenes) do
    scenesByStory[scene.story_id] = scenesByStory[scene.story_id] or {}
    scenesByStory[scene.story_id][#scenesByStory[scene.story_id] + 1] = scene
  end
  for _, story in ipairs(stories) do
    story.scenes = scenesByStory[story.id] or {}
    story.scene_count = #story.scenes
  end
  return { stories = stories, serverTime = os.date('!%Y-%m-%d %H:%M:%S UTC') }
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
    MySQL.update.await('DELETE FROM arachnid_storyteller_scenes WHERE story_id=?', { id })
    MySQL.update.await('DELETE FROM arachnid_storyteller_stories WHERE id=?', { id })
    return rows[1].title
  end)
  if not ok or not title then return feedback(src, 'Story deletion failed: ' .. tostring(ok and reason or title)) end
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
    MySQL.update.await('DELETE FROM arachnid_storyteller_scenes WHERE id=?', { id })
    MySQL.update.await('UPDATE arachnid_storyteller_stories SET updated_by=? WHERE id=?', { actor, rows[1].story_id })
    return rows[1]
  end)
  if not ok or not scene then return feedback(src, 'Scene deletion failed: ' .. tostring(ok and reason or scene)) end
  logAction(src, ('Deleted scene #%d from story #%s: %s'):format(id, tostring(scene.story_id), tostring(scene.title):sub(1, 80)))
  feedback(src, 'Scene beat deleted.')
end)
