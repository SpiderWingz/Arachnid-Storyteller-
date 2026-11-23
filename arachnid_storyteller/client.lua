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

AddEventHandler('onResourceStop', function(resource)
  if resource == GetCurrentResourceName() then
    SetNuiFocus(false, false)
    if type(SetNuiFocusKeepInput) == 'function' then SetNuiFocusKeepInput(false) end
  end
end)
