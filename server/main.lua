local sharedConfig = require 'config.shared'
local ITEMS = exports.ox_inventory:Items()

local function nearTaxi(src)
    local ped = GetPlayerPed(src)
    local coords = GetEntityCoords(ped)
    for _, v in pairs(sharedConfig.npcLocations.deliverLocations) do
        local dist = #(coords - v.xyz)
        if dist < 20 then
            return true
        end
    end
end

local activeMissions = {}

lib.callback.register('qb-taxi:server:spawnTaxi', function(source, model, coords)
    local netId, veh = qbx.spawnVehicle({
        model = model,
        spawnSource = coords,
        warp = GetPlayerPed(source --[[@as number]]),
    })

    local plate = 'TAXI' .. math.random(1000, 9999)
    SetVehicleNumberPlateText(veh, plate)
    TriggerClientEvent('vehiclekeys:client:SetOwner', source, plate)
    return netId
end)

RegisterNetEvent('qb-taxi:server:startNpcMission', function(distance)
    local src = source
    activeMissions[src] = {
        distance = distance,
        active = true
    }
end)

RegisterNetEvent('qb-taxi:server:NpcPay', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player or player.PlayerData.job.name ~= 'taxi' then
        DropPlayer(src, 'Attempting To Exploit')
        return
    end

    if not activeMissions[src] or not activeMissions[src].active then
        return
    end

    if nearTaxi(src) then
        local distance = activeMissions[src].distance
        if distance > 4000 then distance = 4000 end

        local payment = math.floor((distance / 1000 * sharedConfig.meter.defaultPrice) + sharedConfig.meter
            .startingPrice)
        local chance = math.random(1, 5)
        if chance == 1 then payment += math.random(10, 20) end

        exports.qbx_core:AddMoney(src, 'cash', payment)
        activeMissions[src] = nil
    else
        DropPlayer(src, 'Attempting To Exploit (Distance mismatch)')
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    activeMissions[src] = nil
end)