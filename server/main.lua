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

RegisterNetEvent('qb-taxi:server:NpcPay', function(payment)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if player.PlayerData.job.name == 'taxi' then
        if nearTaxi(src) then
            local chance = math.random(1, 5)
            if chance == 1 then payment += math.random(10, 20) end
            player.Functions.AddMoney('cash', payment)
        else
            DropPlayer(src, 'Attempting To Exploit')
        end
    else
        DropPlayer(src, 'Attempting To Exploit')
    end
end)