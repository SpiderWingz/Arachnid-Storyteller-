local opened = false
local activeCutscene = nil
local activeStorySounds = {}
local activeShakeToken = 0

local function stopCutscene()
  local playback = activeCutscene
  if not playback then return end
  activeCutscene = nil
  if playback.camera and DoesCamExist(playback.camera) then
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(playback.camera, false)
  end
  local ped = PlayerPedId()
  if playback.frozePlayer and ped and ped ~= 0 then
    FreezeEntityPosition(ped, playback.wasFrozen == true)
  end
  if playback.fadeOut and playback.fadeOut > 0 and type(DoScreenFadeOut) == 'function' then
    DoScreenFadeOut(math.floor(playback.fadeOut * 1000))
    local deadline = GetGameTimer() + math.floor(playback.fadeOut * 1000) + 250
    while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end
  end
  if playback.fadeOut and playback.fadeOut > 0 and type(DoScreenFadeIn) == 'function' then
    DoScreenFadeIn(math.floor(playback.fadeOut * 1000))
  end
  SendNUIMessage({ action = 'cutsceneOverlay', visible = false, message = '' })
end

local function headingLerp(from, to, amount)
  local delta = ((to - from + 180) % 360) - 180
  return from + delta * amount
end

local function startCutscene(payload)
  stopCutscene()
  if type(payload) ~= 'table' or type(payload.points) ~= 'table' or #payload.points == 0 then return end
  local settings = type(payload.settings) == 'table' and payload.settings or {}
  local points = payload.points
  local playback = {
    paused = false,
    localPreview = payload.localPreview == true,
    freezePlayers = settings.freezePlayers == true,
    hideHud = settings.hideHud == true,
    letterbox = settings.letterbox ~= false,
    loop = settings.loop == true,
    fadeIn = math.max(0, tonumber(settings.fadeIn) or 0),
    fadeOut = math.max(0, tonumber(settings.fadeOut) or 0)
  }
  activeCutscene = playback
  local ped = PlayerPedId()
  if playback.freezePlayers and ped and ped ~= 0 then
    playback.wasFrozen = type(IsEntityPositionFrozen) == 'function' and IsEntityPositionFrozen(ped) or false
    if not playback.wasFrozen then
      FreezeEntityPosition(ped, true)
      playback.frozePlayer = true
    end
  end
  if playback.fadeIn > 0 and type(DoScreenFadeOut) == 'function' then
    DoScreenFadeOut(math.floor(playback.fadeIn * 1000))
    local deadline = GetGameTimer() + math.floor(playback.fadeIn * 1000) + 250
    while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(0) end
  end
  local camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
  playback.camera = camera
  local first = points[1]
  SetCamCoord(camera, tonumber(first.x) or 0, tonumber(first.y) or 0, tonumber(first.z) or 0)
  SetCamRot(camera, 0.0, 0.0, tonumber(first.heading) or 0, 2)
  SetCamFov(camera, tonumber(first.fov) or tonumber(settings.defaultFov) or 75)
  SetCamActive(camera, true)
  RenderScriptCams(true, false, 0, true, true)
  if playback.fadeIn > 0 and type(DoScreenFadeIn) == 'function' then DoScreenFadeIn(math.floor(playback.fadeIn * 1000)) end

  CreateThread(function()
    local running = true
    local function playFor(durationSeconds, update)
      local remaining = math.max(0, durationSeconds * 1000)
      local previousTime = GetGameTimer()
      while activeCutscene == playback and remaining > 0 do
        local now = GetGameTimer()
        if playback.paused then
          previousTime = now
          Wait(0)
        else
          local elapsed = math.max(0, now - previousTime)
          previousTime = now
          remaining = remaining - elapsed
          if update then update(math.max(0, math.min(1, 1 - remaining / math.max(1, durationSeconds * 1000)))) end
          Wait(0)
        end
      end
      return activeCutscene == playback
    end
    while running and activeCutscene == playback do
      for index = 1, #points do
        local point = points[index]
        if index > 1 then
          local previous = points[index - 1]
          local duration = math.max(0, tonumber(previous.transition_duration) or 0)
          if duration > 0 then
            local completed = playFor(duration, function(amount)
              local sx, sy, sz = tonumber(previous.x) or 0, tonumber(previous.y) or 0, tonumber(previous.z) or 0
              local ex, ey, ez = tonumber(point.x) or sx, tonumber(point.y) or sy, tonumber(point.z) or sz
              SetCamCoord(camera, sx + (ex - sx) * amount, sy + (ey - sy) * amount, sz + (ez - sz) * amount)
              SetCamRot(camera, 0.0, 0.0, headingLerp(tonumber(previous.heading) or 0, tonumber(point.heading) or 0, amount), 2)
              local startFov = tonumber(previous.fov) or tonumber(settings.defaultFov) or 75
              local endFov = tonumber(point.fov) or tonumber(settings.defaultFov) or 75
              SetCamFov(camera, startFov + (endFov - startFov) * amount)
            end)
            if not completed then break end
          end
          if activeCutscene ~= playback then break end
          SetCamCoord(camera, tonumber(point.x) or 0, tonumber(point.y) or 0, tonumber(point.z) or 0)
          SetCamRot(camera, 0.0, 0.0, tonumber(point.heading) or 0, 2)
          SetCamFov(camera, tonumber(point.fov) or tonumber(settings.defaultFov) or 75)
        end
        local message = tostring(point.message or '')
        SendNUIMessage({ action = 'cutsceneOverlay', visible = message ~= '', message = message })
        if not playFor(math.max(0, tonumber(point.hold_duration) or 0)) then break end
        if activeCutscene ~= playback then break end
      end
      if activeCutscene ~= playback or not playback.loop then running = false end
    end
    if activeCutscene == playback then stopCutscene() end
  end)
end

CreateThread(function()
  while true do
    local playback = activeCutscene
    if playback then
      if playback.hideHud and type(HideHudAndRadarThisFrame) == 'function' then HideHudAndRadarThisFrame() end
      if playback.letterbox then
        DrawRect(0.5, 0.045, 1.0, 0.09, 0, 0, 0, 255)
        DrawRect(0.5, 0.955, 1.0, 0.09, 0, 0, 0, 255)
      end
      Wait(0)
    else
      Wait(100)
    end
  end
end)

local function close()
  opened = false
  SetNuiFocus(false, false)
  if type(SetNuiFocusKeepInput) == 'function' then SetNuiFocusKeepInput(false) end
  SendNUIMessage({ action = 'close' })
end

RegisterCommand(Config.Command, function()
  if opened then
    close()
  else
    TriggerServerEvent('arachnid_storyteller:requestOpen')
  end
end, false)

RegisterNetEvent('arachnid_storyteller:open', function(payload)
  if type(payload) ~= 'table' then return end
  opened = true
  SetNuiFocus(true, true)
  SendNUIMessage({ action = 'open', payload = payload })
end)

RegisterNetEvent('arachnid_storyteller:data', function(payload)
  if opened and type(payload) == 'table' then
    SendNUIMessage({ action = 'data', payload = payload })
  end
end)

RegisterNetEvent('arachnid_storyteller:feedback', function(message)
  if opened then SendNUIMessage({ action = 'feedback', message = tostring(message) }) end
end)

RegisterNetEvent('arachnid_storyteller:select', function(payload)
  if opened and type(payload) == 'table' then
    SendNUIMessage({ action = 'select', payload = payload })
  end
end)

RegisterNetEvent('arachnid_storyteller:session', function(payload)
  if type(payload) == 'table' then
    if payload.state == 'active' and activeCutscene and activeCutscene.localPreview then stopCutscene() end
    SendNUIMessage({ action = 'session', payload = payload })
  end
end)

RegisterNetEvent('arachnid_storyteller:sessionAdmin', function(payload)
  if type(payload) == 'table' then
    if payload.state == 'active' and activeCutscene and activeCutscene.localPreview then stopCutscene() end
    SendNUIMessage({ action = 'sessionAdmin', payload = payload })
  end
end)

RegisterNetEvent('arachnid_storyteller:rtsSnapshot', function(payload)
  if opened and type(payload) == 'table' then SendNUIMessage({ action = 'rtsSnapshot', payload = payload }) end
end)

RegisterNetEvent('arachnid_storyteller:actionMessage', function(payload)
  if type(payload) == 'table' then SendNUIMessage({ action = 'actionMessage', payload = payload }) end
end)

RegisterNetEvent('arachnid_storyteller:cutscenePlay', startCutscene)
RegisterNetEvent('arachnid_storyteller:cutscenePause', function()
  if activeCutscene then activeCutscene.paused = true end
end)
RegisterNetEvent('arachnid_storyteller:cutsceneResume', function()
  if activeCutscene then activeCutscene.paused = false end
end)
RegisterNetEvent('arachnid_storyteller:cutsceneStop', stopCutscene)

local function cleanupStoryEffects()
  for _, soundId in pairs(activeStorySounds) do
    if type(StopSound) == 'function' then pcall(StopSound, soundId) end
    if type(ReleaseSoundId) == 'function' then pcall(ReleaseSoundId, soundId) end
  end
  activeStorySounds = {}
  activeShakeToken = activeShakeToken + 1
  if type(StopGameplayCamShaking) == 'function' then pcall(StopGameplayCamShaking, false) end
  if type(DoScreenFadeIn) == 'function' then DoScreenFadeIn(500) end
  SendNUIMessage({ action = 'storyEffectCleanup' })
end

RegisterNetEvent('arachnid_storyteller:storyEffect', function(payload)
  if type(payload) ~= 'table' then return end
  local kind = payload.kind
  if kind == 'cleanup' then return cleanupStoryEffects() end
  if kind == 'play_sound' then
    local key = tostring(payload.soundId or '')
    if key == '' or type(GetSoundId) ~= 'function' or type(PlaySoundFrontend) ~= 'function' then return end
    if activeStorySounds[key] then
      if type(StopSound) == 'function' then pcall(StopSound, activeStorySounds[key]) end
      if type(ReleaseSoundId) == 'function' then pcall(ReleaseSoundId, activeStorySounds[key]) end
    end
    local soundId = GetSoundId()
    activeStorySounds[key] = soundId
    PlaySoundFrontend(soundId, tostring(payload.name or ''), tostring(payload.set or ''), false)
    if type(SetVariableOnSound) == 'function' then
      pcall(SetVariableOnSound, soundId, 'Volume', tonumber(payload.volume) or 1.0)
      pcall(SetVariableOnSound, soundId, 'Pitch', tonumber(payload.pitch) or 100)
    end
  elseif kind == 'stop_sound' then
    local key = tostring(payload.soundId or '')
    local soundId = activeStorySounds[key]
    if soundId then
      if type(StopSound) == 'function' then pcall(StopSound, soundId) end
      if type(ReleaseSoundId) == 'function' then pcall(ReleaseSoundId, soundId) end
      activeStorySounds[key] = nil
    end
  elseif kind == 'screen_fade' then
    local data = type(payload.data) == 'table' and payload.data or {}
    local milliseconds = math.floor((tonumber(data.duration) or 0) * 1000)
    if data.direction == 'out' and type(DoScreenFadeOut) == 'function' then DoScreenFadeOut(milliseconds)
    elseif type(DoScreenFadeIn) == 'function' then DoScreenFadeIn(milliseconds) end
  elseif kind == 'announcement' or kind == 'subtitle' then
    local data = type(payload.data) == 'table' and payload.data or {}
    SendNUIMessage({ action = 'storyEffectMessage', kind = kind, text = tostring(data.text or ''), duration = tonumber(data.duration) or 5 })
  elseif kind == 'screen_shake' then
    local data = type(payload.data) == 'table' and payload.data or {}
    activeShakeToken = activeShakeToken + 1
    local token = activeShakeToken
    CreateThread(function()
      local frequency = math.max(0, tonumber(data.frequency) or 1)
      local amplitude = math.max(0, math.min(1, (tonumber(data.amplitude) or 1) / 10))
      local endsAt = GetGameTimer() + math.floor((tonumber(data.duration) or 2) * 1000)
      if frequency <= 0 or type(ShakeGameplayCam) ~= 'function' then return end
      local halfPeriod = math.max(10, math.floor(500 / frequency))
      while activeShakeToken == token and GetGameTimer() < endsAt do
        pcall(ShakeGameplayCam, 'SMALL_EXPLOSION_SHAKE', amplitude)
        Wait(math.min(halfPeriod, math.max(0, endsAt - GetGameTimer())))
        if type(StopGameplayCamShaking) == 'function' then pcall(StopGameplayCamShaking, false) end
        Wait(math.min(halfPeriod, math.max(0, endsAt - GetGameTimer())))
      end
      if activeShakeToken == token and type(StopGameplayCamShaking) == 'function' then pcall(StopGameplayCamShaking, false) end
    end)
  end
end)

RegisterNetEvent('arachnid_storyteller:denied', function(message)
  TriggerEvent('chat:addMessage', {
    args = { 'Arachnid Storyteller', message or 'You do not have permission to use /STTool.' }
  })
end)

RegisterNUICallback('close', function(_, cb)
  close()
  cb({ ok = true })
end)

RegisterNUICallback('refresh', function(_, cb)
  if opened then TriggerServerEvent('arachnid_storyteller:requestData') end
  cb({ ok = true })
end)

RegisterNUICallback('storySave', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:storySave', data.story)
  end
  cb({ ok = true })
end)

RegisterNUICallback('storyDelete', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:storyDelete', data.id)
  end
  cb({ ok = true })
end)

RegisterNUICallback('sceneSave', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:sceneSave', data.scene)
  end
  cb({ ok = true })
end)

RegisterNUICallback('sceneDelete', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:sceneDelete', data.id)
  end
  cb({ ok = true })
end)

RegisterNUICallback('sessionStart', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:sessionStart', data)
  end
  cb({ ok = true })
end)

RegisterNUICallback('sessionNext', function(_, cb)
  if opened then TriggerServerEvent('arachnid_storyteller:sessionNext') end
  cb({ ok = true })
end)

RegisterNUICallback('sessionSelectScene', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:sessionSelectScene', data.sceneId)
  end
  cb({ ok = true })
end)

RegisterNUICallback('sessionStop', function(_, cb)
  if opened then TriggerServerEvent('arachnid_storyteller:sessionStop') end
  cb({ ok = true })
end)

RegisterNUICallback('sessionObjectiveSave', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:sessionObjectiveSave', data.text)
  end
  cb({ ok = true })
end)

RegisterNUICallback('sessionObjectiveStatus', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:sessionObjectiveStatus', data.status)
  end
  cb({ ok = true })
end)

RegisterNUICallback('cameraPointCapture', function(data, cb)
  if opened and type(data) == 'table' then
    local ped = PlayerPedId()
    local configuredWeapon = Config.Camera.Tool.weapon
    if configuredWeapon ~= nil and configuredWeapon ~= '' then
      local expectedWeapon = type(configuredWeapon) == 'number' and configuredWeapon or GetHashKey(configuredWeapon)
      if GetSelectedPedWeapon(ped) ~= expectedWeapon then
        SendNUIMessage({ action = 'feedback', message = 'Equip the configured camera tool before capturing a node.' })
        cb({ ok = false, error = 'camera_tool_not_equipped' })
        return
      end
    end
    TriggerServerEvent('arachnid_storyteller:cameraPointCapture', data.sceneId, GetEntityHeading(ped), data.distance)
  end
  cb({ ok = true })
end)

RegisterNUICallback('cameraPointSave', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:cameraPointSave', data.point)
  end
  cb({ ok = true })
end)

RegisterNUICallback('cameraPointDelete', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:cameraPointDelete', data.id)
  end
  cb({ ok = true })
end)

RegisterNUICallback('sceneCutsceneSettingsSave', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:sceneCutsceneSettingsSave', data)
  end
  cb({ ok = true })
end)

RegisterNUICallback('cutscenePreview', function(data, cb)
  if opened and type(data) == 'table' then TriggerServerEvent('arachnid_storyteller:cutscenePreview', data.sceneId) end
  cb({ ok = true })
end)

RegisterNUICallback('cutscenePreviewStop', function(_, cb)
  if opened then TriggerServerEvent('arachnid_storyteller:cutscenePreviewStop') end
  cb({ ok = true })
end)

RegisterNUICallback('sessionCutscenePlay', function(data, cb)
  if opened and type(data) == 'table' then TriggerServerEvent('arachnid_storyteller:sessionCutscenePlay', data.sceneId) end
  cb({ ok = true })
end)

RegisterNUICallback('sessionCutsceneStop', function(_, cb)
  if opened then TriggerServerEvent('arachnid_storyteller:sessionCutsceneStop') end
  cb({ ok = true })
end)

RegisterNUICallback('sessionCutscenePause', function(_, cb)
  if opened then TriggerServerEvent('arachnid_storyteller:sessionCutscenePause') end
  cb({ ok = true })
end)

RegisterNUICallback('sessionCutsceneResume', function(_, cb)
  if opened then TriggerServerEvent('arachnid_storyteller:sessionCutsceneResume') end
  cb({ ok = true })
end)

RegisterNUICallback('areaSave', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:areaSave', data.area)
  end
  cb({ ok = true })
end)

RegisterNUICallback('areaDelete', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:areaDelete', data.id)
  end
  cb({ ok = true })
end)

RegisterNUICallback('flowSave', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:flowSave', data)
  end
  cb({ ok = true })
end)

RegisterNUICallback('teleportSave', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:teleportSave', data)
  end
  cb({ ok = true })
end)

RegisterNUICallback('teleportDelete', function(data, cb)
  if opened and type(data) == 'table' then
    TriggerServerEvent('arachnid_storyteller:teleportDelete', data.id, data.storyId)
  end
  cb({ ok = true })
end)

RegisterNUICallback('spawnPointSave', function(data, cb)
  if opened and type(data) == 'table' then TriggerServerEvent('arachnid_storyteller:spawnPointSave', data) end
  cb({ ok = true })
end)

RegisterNUICallback('spawnPointDelete', function(data, cb)
  if opened and type(data) == 'table' then TriggerServerEvent('arachnid_storyteller:spawnPointDelete', data.id, data.storyId) end
  cb({ ok = true })
end)

RegisterNUICallback('sessionEncounterAction', function(data, cb)
  if opened and type(data) == 'table' then TriggerServerEvent('arachnid_storyteller:sessionEncounterAction', data) end
  cb({ ok = true })
end)

RegisterNUICallback('requestRtsSnapshot', function(_, cb)
  if opened then TriggerServerEvent('arachnid_storyteller:requestRtsSnapshot') end
  cb({ ok = true })
end)

RegisterNUICallback('sessionWorldAction', function(data, cb)
  if opened and type(data) == 'table' then TriggerServerEvent('arachnid_storyteller:sessionWorldAction', data) end
  cb({ ok = true })
end)

RegisterNUICallback('sessionEffectAction', function(data, cb)
  if opened and type(data) == 'table' then TriggerServerEvent('arachnid_storyteller:sessionEffectAction', data) end
  cb({ ok = true })
end)

RegisterNUICallback('sessionPause', function(_, cb)
  if opened then TriggerServerEvent('arachnid_storyteller:sessionPause') end
  cb({ ok = true })
end)

RegisterNUICallback('sessionResume', function(_, cb)
  if opened then TriggerServerEvent('arachnid_storyteller:sessionResume') end
  cb({ ok = true })
end)

CreateThread(function()
  Wait(1500)
  TriggerServerEvent('arachnid_storyteller:requestSession')
end)

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    stopCutscene()
    cleanupStoryEffects()
    SetNuiFocus(false, false)
    if type(SetNuiFocusKeepInput) == 'function' then SetNuiFocusKeepInput(false) end
  end
end)
