local opened = false

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
    SendNUIMessage({ action = 'session', payload = payload })
  end
end)

RegisterNetEvent('arachnid_storyteller:sessionAdmin', function(payload)
  if type(payload) == 'table' then SendNUIMessage({ action = 'sessionAdmin', payload = payload }) end
end)

RegisterNetEvent('arachnid_storyteller:actionMessage', function(payload)
  if type(payload) == 'table' then SendNUIMessage({ action = 'actionMessage', payload = payload }) end
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
    SetNuiFocus(false, false)
    if type(SetNuiFocusKeepInput) == 'function' then SetNuiFocusKeepInput(false) end
  end
end)
