-- Variables
local config = require 'config.client'
local sharedConfig = require 'config.shared'
local isLoggedIn = LocalPlayer.state.isLoggedIn
local meterIsOpen = false
local meterActive = false
local lastLocation = nil
local mouseActive = false
local pickupLocation, dropOffLocation = nil, nil

-- used for polyzones
local isInsidePickupZone = false
local isInsideDropZone = false

local meterData = {
    fareAmount = 6,
    currentFare = 0,
    distanceTraveled = 0
}

local NpcData = {
    Active = false,
    CurrentNpc = nil,
    LastNpc = nil,
    CurrentDeliver = nil,
    LastDeliver = nil,
    Npc = nil,
    NpcBlip = nil,
    DeliveryBlip = nil,
    NpcTaken = false,
    NpcDelivered = false,
    CountDown = 180
}

local taxiPed = nil

local function resetNpcTask()
    NpcData = {
        Active = false,
        CurrentNpc = nil,
        LastNpc = nil,
        CurrentDeliver = nil,
        LastDeliver = nil,
        Npc = nil,
        NpcBlip = nil,
        DeliveryBlip = nil,
        NpcTaken = false,
        NpcDelivered = false
    }
end

local function resetMeter()
    meterData = {
        fareAmount = 6,
        currentFare = 0,
        distanceTraveled = 0
    }
end

local function whitelistedVehicle()
    local veh = GetEntityModel(cache.vehicle)

    if not veh then
        return false
    end

    if veh == `dynasty` then
        return true
    end

    for i = 1, #config.allowedVehicles, 1 do
        if veh == joaat(config.allowedVehicles[i].model) then
            return true
        end
    end

    return false
end

local function isDriver()
    return cache.seat == -1
end

local zone
local delieveryZone

local function getDeliveryLocation()
    NpcData.CurrentDeliver = math.random(1, #sharedConfig.npcLocations.deliverLocations)
    if NpcData.LastDeliver then
        while NpcData.LastDeliver ~= NpcData.CurrentDeliver do
            NpcData.CurrentDeliver = math.random(1, #sharedConfig.npcLocations.deliverLocations)
        end
    end

    if NpcData.DeliveryBlip then
        RemoveBlip(NpcData.DeliveryBlip)
    end
    NpcData.DeliveryBlip = AddBlipForCoord(sharedConfig.npcLocations.deliverLocations[NpcData.CurrentDeliver].x,
        sharedConfig.npcLocations.deliverLocations[NpcData.CurrentDeliver].y,
        sharedConfig.npcLocations.deliverLocations[NpcData.CurrentDeliver].z)
    SetBlipColour(NpcData.DeliveryBlip, 3)
    SetBlipRoute(NpcData.DeliveryBlip, true)
    SetBlipRouteColour(NpcData.DeliveryBlip, 3)
    NpcData.LastDeliver = NpcData.CurrentDeliver
    if not config.useTarget then -- added checks to disable distance checking if polyzone option is used
        CreateThread(function()
            while true do
                local pos = GetEntityCoords(cache.ped)
                local dist = #(pos - vec3(sharedConfig.npcLocations.deliverLocations[NpcData.CurrentDeliver].x, sharedConfig.npcLocations.deliverLocations[NpcData.CurrentDeliver].y, sharedConfig.npcLocations.deliverLocations[NpcData.CurrentDeliver].z))
                if dist < 20 then
                    DrawMarker(2, sharedConfig.npcLocations.deliverLocations[NpcData.CurrentDeliver].x,
                        sharedConfig.npcLocations.deliverLocations[NpcData.CurrentDeliver].y,
                        sharedConfig.npcLocations.deliverLocations[NpcData.CurrentDeliver].z, 0.0, 0.0, 0.0, 0.0, 0.0,
                        0.0, 0.3, 0.3, 0.3, 255, 255, 255, 255, false, false, 0, true, "", "", false)
                    if dist < 10 then
                        qbx.drawText3d({
                            text = locale('info.drop_off_npc'),
                            coords = sharedConfig.npcLocations
                                .deliverLocations[NpcData.CurrentDeliver].xyz
                        })
                        if IsControlJustPressed(0, 38) then
                            TaskLeaveVehicle(NpcData.Npc, cache.vehicle, 0)
                            SetEntityAsMissionEntity(NpcData.Npc, false, true)
                            SetEntityAsNoLongerNeeded(NpcData.Npc)
                            local targetCoords = sharedConfig.npcLocations.takeLocations[NpcData.LastNpc]
                            TaskGoStraightToCoord(NpcData.Npc, targetCoords.x, targetCoords.y, targetCoords.z, 1.0, -1,
                                0.0, 0.0)
                            SendNUIMessage({
                                action = 'toggleMeter'
                            })
                            if NpcData.NpcTaken then
                                TriggerServerEvent('qb-taxi:server:NpcPay')
                            end
                            meterActive = false
                            sharedConfig.meter.useGpsPrice = false
                            SendNUIMessage({
                                action = 'resetMeter'
                            })

                            pickupLocation, dropOffLocation = nil, nil

                            exports.qbx_core:Notify(locale('info.person_was_dropped_off'), 'success')
                            if NpcData.DeliveryBlip then
                                RemoveBlip(NpcData.DeliveryBlip)
                            end
                            local RemovePed = function(p)
                                SetTimeout(60000, function()
                                    DeletePed(p)
                                end)
                            end
                            RemovePed(NpcData.Npc)
                            resetNpcTask()
                            break
                        end
                    end
                end
                Wait(0)
            end
        end)
    end
end

local function callNpcPoly()
    CreateThread(function()
        while not NpcData.NpcTaken do
            if isInsidePickupZone then
                if IsControlJustPressed(0, 38) then
                    lib.hideTextUI()
                    local veh = cache.vehicle
                    local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(veh), 0

                    for i = maxSeats - 1, 0, -1 do
                        if IsVehicleSeatFree(veh, i) then
                            freeSeat = i
                            break
                        end
                    end

                    lastLocation = GetEntityCoords(cache.ped)
                    ClearPedTasksImmediately(NpcData.Npc)
                    FreezeEntityPosition(NpcData.Npc, false)
                    TaskEnterVehicle(NpcData.Npc, veh, -1, freeSeat, 1.0, 0)
                    exports.qbx_core:Notify(locale('info.go_to_location'), 'inform')
                    if NpcData.NpcBlip then
                        RemoveBlip(NpcData.NpcBlip)
                    end
                    getDeliveryLocation()
                    pickupLocation = GetEntityCoords(cache.ped)
                    dropOffLocation = config.pzLocations.dropLocations[NpcData.CurrentDeliver].coord.xyz
                    local distance = CalculateTravelDistanceBetweenPoints(pickupLocation.x, pickupLocation.y,
                        pickupLocation.z, dropOffLocation.x, dropOffLocation.y, dropOffLocation.z)
                    if distance <= 0 then
                        distance = #(pickupLocation - dropOffLocation)
                    end
                    TriggerServerEvent('qb-taxi:server:startNpcMission', distance)

                    sharedConfig.meter.useGpsPrice = true
                    meterIsOpen = true
                    meterActive = true

                    SendNUIMessage({
                        action = 'openMeter',
                        toggle = true,
                        meterData = sharedConfig.meter
                    })
                    SendNUIMessage({
                        action = 'toggleMeter'
                    })
                    NpcData.NpcTaken = true
                    createNpcDeliveryLocation()
                    zone:remove()
                    lib.hideTextUI()
                end
            end
            Wait(0)
        end
    end)
end

local function onEnterCallZone()
    if whitelistedVehicle() and not isInsidePickupZone and not NpcData.NpcTaken then
        isInsidePickupZone = true
        lib.showTextUI(locale('info.call_npc'), { position = 'left-center' })
        callNpcPoly()
    end
end

local function onExitCallZone()
    lib.hideTextUI()
    isInsidePickupZone = false
end

local function createNpcPickUpLocation()
    zone = lib.zones.box({
        coords = config.pzLocations.takeLocations[NpcData.CurrentNpc].coord,
        size = vec3(config.pzLocations.takeLocations[NpcData.CurrentNpc].height,
            config.pzLocations.takeLocations[NpcData.CurrentNpc].width,
            (config.pzLocations.takeLocations[NpcData.CurrentNpc].maxZ - config.pzLocations.takeLocations[NpcData.CurrentNpc].minZ)),
        rotation = config.pzLocations.takeLocations[NpcData.CurrentNpc].heading,
        debug = config.debugPoly,
        onEnter = onEnterCallZone,
        onExit = onExitCallZone
    })
end

local function enumerateEntitiesWithinDistance(entities, isPlayerEntities, coords, maxDistance)
    local nearbyEntities = {}
    if coords then
        coords = vec3(coords.x, coords.y, coords.z)
    else
        coords = GetEntityCoords(cache.ped)
    end
    for k, entity in pairs(entities) do
        local distance = #(coords - GetEntityCoords(entity))
        if distance <= maxDistance then
            nearbyEntities[#nearbyEntities + 1] = isPlayerEntities and k or entity
        end
    end
    return nearbyEntities
end

local function getVehiclesInArea(coords, maxDistance) -- Vehicle inspection in designated area
    return enumerateEntitiesWithinDistance(GetGamePool('CVehicle'), false, coords, maxDistance)
end

local function isSpawnPointClear(coords, maxDistance) -- Check the spawn point to see if it's empty or not:
    return #getVehiclesInArea(coords, maxDistance) == 0
end

local function getVehicleSpawnPoint()
    local near = nil
    local distance = 10000
    for k, v in pairs(config.cabSpawns) do
        if isSpawnPointClear(vec3(v.x, v.y, v.z), 2.5) then
            local pos = GetEntityCoords(cache.ped)
            local cur_distance = #(pos - vec3(v.x, v.y, v.z))
            if cur_distance < distance then
                distance = cur_distance
                near = k
            end
        end
    end
    return near
end

local function calculateFareAmount()
    if meterActive then
        local startPos = lastLocation
        local newPos = GetEntityCoords(cache.ped)
        if startPos ~= newPos then
            local newDistance = #(startPos - newPos)
            lastLocation = newPos

            meterData['distanceTraveled'] += (newDistance / 1000)

            local fareAmount = 0

            if sharedConfig.meter.useGpsPrice and pickupLocation and dropOffLocation then
                local distanceBetweenPickupAndDropoff = CalculateTravelDistanceBetweenPoints(pickupLocation.x,
                        pickupLocation.y, pickupLocation.z, dropOffLocation.x, dropOffLocation.y, dropOffLocation.z) /
                    1000 -- Convert to kilometers
                fareAmount = (distanceBetweenPickupAndDropoff * sharedConfig.meter.defaultPrice) +
                    sharedConfig.meter.startingPrice
            else
                fareAmount = ((meterData['distanceTraveled']) * sharedConfig.meter.defaultPrice) +
                    sharedConfig.meter.startingPrice
            end

            meterData['currentFare'] = math.floor(fareAmount)


            SendNUIMessage({
                action = 'updateMeter',
                meterData = meterData
            })
        end
    end
end

local function onEnterDropZone()
    if whitelistedVehicle() and not isInsideDropZone and NpcData.NpcTaken then
        isInsideDropZone = true
        lib.showTextUI(locale('info.drop_off_npc'), { position = 'left-center' })
        dropNpcPoly()
    end
end

local function onExitDropZone()
    lib.hideTextUI()
    isInsideDropZone = false
end

function createNpcDeliveryLocation()
    delieveryZone = lib.zones.box({
        coords = config.pzLocations.dropLocations[NpcData.CurrentDeliver].coord,
        size = vec3(config.pzLocations.dropLocations[NpcData.CurrentDeliver].height,
            config.pzLocations.dropLocations[NpcData.CurrentDeliver].width,
            (config.pzLocations.dropLocations[NpcData.CurrentDeliver].maxZ - config.pzLocations.dropLocations[NpcData.CurrentDeliver].minZ)),
        rotation = config.pzLocations.dropLocations[NpcData.CurrentDeliver].heading,
        debug = config.debugPoly,
        onEnter = onEnterDropZone,
        onExit = onExitDropZone
    })
end

function dropNpcPoly()
    CreateThread(function()
        while NpcData.NpcTaken do
            if isInsideDropZone then
                if IsControlJustPressed(0, 38) then
                    lib.hideTextUI()
                    local veh = cache.vehicle
                    TaskLeaveVehicle(NpcData.Npc, veh, 0)
                    Wait(1000)
                    SetVehicleDoorShut(veh, 3, false)
                    SetEntityAsMissionEntity(NpcData.Npc, false, true)
                    SetEntityAsNoLongerNeeded(NpcData.Npc)
                    local targetCoords = sharedConfig.npcLocations.takeLocations[NpcData.LastNpc]
                    TaskGoStraightToCoord(NpcData.Npc, targetCoords.x, targetCoords.y, targetCoords.z, 1.0, -1, 0.0, 0.0)
                    SendNUIMessage({
                        action = 'toggleMeter'
                    })
                    if NpcData.NpcTaken then
                        TriggerServerEvent('qb-taxi:server:NpcPay')
                    end
                    meterActive = false
                    sharedConfig.meter.useGpsPrice = false
                    SendNUIMessage({
                        action = 'resetMeter'
                    })
                    exports.qbx_core:Notify(locale('info.person_was_dropped_off'), 'success')
                    if NpcData.DeliveryBlip ~= nil then
                        RemoveBlip(NpcData.DeliveryBlip)
                    end
                    local RemovePed = function(p)
                        SetTimeout(60000, function()
                            DeletePed(p)
                        end)
                    end
                    RemovePed(NpcData.Npc)
                    resetNpcTask()
                    delieveryZone:remove()
                    lib.hideTextUI()
                    break
                end
            end
            Wait(0)
        end
    end)
end

local function setLocationsBlip()
    if not config.useBlips then return end
    local taxiBlip = AddBlipForCoord(config.locations.main.coords.x, config.locations.main.coords.y,
        config.locations.main.coords.z)
    SetBlipSprite(taxiBlip, 198)
    SetBlipDisplay(taxiBlip, 4)
    SetBlipScale(taxiBlip, 0.6)
    SetBlipAsShortRange(taxiBlip, true)
    SetBlipColour(taxiBlip, 5)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(locale('info.blip_name'))
    EndTextCommandSetBlipName(taxiBlip)
end

local function taxiGarage()
    local registeredMenu = {
        id = 'garages_depotlist',
        title = locale('menu.taxi_menu_header'),
        options = {}
    }
    local options = {}
    for _, v in pairs(config.allowedVehicles) do
        options[#options + 1] = {
            title = v.label,
            event = 'qb-taxi:client:TakeVehicle',
            args = { model = v.model },
            icon = 'fa-solid fa-taxi'
        }
    end

    registeredMenu['options'] = options
    lib.registerContext(registeredMenu)
    lib.showContext('garages_depotlist')
end

RegisterNetEvent('qb-taxi:client:TakeVehicle', function(data)
    local SpawnPoint = getVehicleSpawnPoint()
    if SpawnPoint then
        local coords = config.cabSpawns[SpawnPoint]
        local CanSpawn = isSpawnPointClear(coords, 2.0)
        if CanSpawn then
            local netId = lib.callback.await('qb-taxi:server:spawnTaxi', false, data.model, coords)
            local veh = NetToVeh(netId)
            SetVehicleFuelLevel(veh, 100.0)
            SetVehicleEngineOn(veh, true, true, false)
        else
            exports.qbx_core:Notify(locale('info.no_spawn_point'), 'error')
        end
    else
        exports.qbx_core:Notify(locale('info.no_spawn_point'), 'error')
        return
    end
end)

-- Events
RegisterNetEvent('qb-taxi:client:DoTaxiNpc', function()
    if whitelistedVehicle() then
        if not NpcData.Active then
            NpcData.CurrentNpc = math.random(1, #sharedConfig.npcLocations.takeLocations)
            if NpcData.LastNpc ~= nil then
                while NpcData.LastNpc ~= NpcData.CurrentNpc do
                    NpcData.CurrentNpc = math.random(1, #sharedConfig.npcLocations.takeLocations)
                end
            end

            local Gender = math.random(1, #config.npcSkins)
            local PedSkin = math.random(1, #config.npcSkins[Gender])
            local model = GetHashKey(config.npcSkins[Gender][PedSkin])
            lib.requestModel(model)
            NpcData.Npc = CreatePed(3, model, sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].x,
                sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].y,
                sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].z - 0.98,
                sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].w, true, true)
            SetModelAsNoLongerNeeded(model)
            PlaceObjectOnGroundProperly(NpcData.Npc)
            FreezeEntityPosition(NpcData.Npc, true)
            if NpcData.NpcBlip ~= nil then
                RemoveBlip(NpcData.NpcBlip)
            end
            exports.qbx_core:Notify(locale('info.npc_on_gps'), 'success')

            -- added checks to disable distance checking if polyzone option is used
            if config.useTarget then
                createNpcPickUpLocation()
            end

            NpcData.NpcBlip = AddBlipForCoord(sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].x,
                sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].y,
                sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].z)
            SetBlipColour(NpcData.NpcBlip, 3)
            SetBlipRoute(NpcData.NpcBlip, true)
            SetBlipRouteColour(NpcData.NpcBlip, 3)
            NpcData.LastNpc = NpcData.CurrentNpc
            NpcData.Active = true

            -- added checks to disable distance checking if polyzone option is used
            if not config.useTarget then
                CreateThread(function()
                    while not NpcData.NpcTaken do
                        local pos = GetEntityCoords(cache.ped)
                        local dist = #(pos - vec3(sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].x, sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].y, sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].z))

                        if dist < 20 then
                            DrawMarker(2, sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].x,
                                sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].y,
                                sharedConfig.npcLocations.takeLocations[NpcData.CurrentNpc].z, 0.0, 0.0, 0.0, 0.0, 0.0,
                                0.0, 0.3, 0.3, 0.3, 255, 255, 255, 255, false, false, 0, true, "", "", false)

                            if dist < 10 then
                                qbx.drawText3d({
                                    text = locale('info.call_npc'),
                                    coords = sharedConfig.npcLocations
                                        .takeLocations[NpcData.CurrentNpc].xyz
                                })
                                if IsControlJustPressed(0, 38) then
                                    local maxSeats, freeSeat = GetVehicleMaxNumberOfPassengers(cache.vehicle), 0

                                    for i = maxSeats - 1, 0, -1 do
                                        if IsVehicleSeatFree(cache.vehicle, i) then
                                            freeSeat = i
                                            break
                                        end
                                    end

                                    lastLocation = GetEntityCoords(cache.ped)
                                    ClearPedTasksImmediately(NpcData.Npc)
                                    FreezeEntityPosition(NpcData.Npc, false)
                                    TaskEnterVehicle(NpcData.Npc, cache.vehicle, -1, freeSeat, 1.0, 0)
                                    exports.qbx_core:Notify(locale('info.go_to_location'), 'inform')
                                    if NpcData.NpcBlip ~= nil then
                                        RemoveBlip(NpcData.NpcBlip)
                                    end
                                    getDeliveryLocation()
                                    pickupLocation = GetEntityCoords(cache.ped)
                                    dropOffLocation = config.pzLocations.dropLocations[NpcData.CurrentDeliver].coord.xyz
                                    local distance = CalculateTravelDistanceBetweenPoints(pickupLocation.x,
                                        pickupLocation.y, pickupLocation.z, dropOffLocation.x, dropOffLocation.y,
                                        dropOffLocation.z)
                                    if distance <= 0 then
                                        distance = #(pickupLocation - dropOffLocation)
                                    end
                                    TriggerServerEvent('qb-taxi:server:startNpcMission', distance)

                                    sharedConfig.meter.useGpsPrice = true
                                    meterIsOpen = true
                                    meterActive = true
                                    NpcData.NpcTaken = true

                                    SendNUIMessage({
                                        action = 'openMeter',
                                        toggle = true,
                                        meterData = sharedConfig.meter
                                    })
                                    SendNUIMessage({
                                        action = 'toggleMeter'
                                    })
                                end
                            end
                        end

                        Wait(0)
                    end
                end)
            end
        else
            exports.qbx_core:Notify(locale('error.already_mission'), 'error')
        end
    else
        exports.qbx_core:Notify(locale('error.not_in_taxi'), 'error')
    end
end)

RegisterNetEvent('qb-taxi:client:toggleMeter', function()
    if cache.vehicle then
        if whitelistedVehicle() then
            if not meterIsOpen and isDriver() then
                SendNUIMessage({
                    action = 'openMeter',
                    toggle = true,
                    meterData = sharedConfig.meter
                })
                meterIsOpen = true
            else
                SendNUIMessage({
                    action = 'openMeter',
                    toggle = false
                })
                meterIsOpen = false
            end
        else
            exports.qbx_core:Notify(locale('error.missing_meter'), 'error')
        end
    else
        exports.qbx_core:Notify(locale('error.no_vehicle'), 'error')
    end
end)

RegisterNetEvent('qb-taxi:client:enableMeter', function()
    if meterIsOpen then
        SendNUIMessage({
            action = 'toggleMeter'
        })
    else
        exports.qbx_core:Notify(locale('error.not_active_meter'), 'error')
    end
end)

RegisterNetEvent('qb-taxi:client:toggleMuis', function()
    Wait(400)
    if meterIsOpen then
        if not mouseActive then
            SetNuiFocus(true, true)
            mouseActive = true
        end
    else
        exports.qbx_core:Notify(locale('error.no_meter_sight'), 'error')
    end
end)

RegisterNetEvent('qb-taxijob:client:requestcab', function()
    taxiGarage()
end)

-- NUI Callbacks

RegisterNUICallback('enableMeter', function(data, cb)
    meterActive = data.enabled
    if not meterActive then resetMeter() end
    lastLocation = GetEntityCoords(cache.ped)
    cb('ok')
end)

RegisterNUICallback('hideMouse', function(_, cb)
    SetNuiFocus(false, false)
    mouseActive = false
    cb('ok')
end)

-- Threads
local isWhitelisted = false
CreateThread(function()
    while true do
        Wait(1000)
        isWhitelisted = whitelistedVehicle()
    end
end)

CreateThread(function()
    while true do
        Wait(200)
        if isWhitelisted then
            calculateFareAmount()
        end
    end
end)

CreateThread(function()
    while true do
        if not isWhitelisted then
            if meterIsOpen then
                SendNUIMessage({
                    action = 'openMeter',
                    toggle = false
                })
                meterIsOpen = false
            end
        end
        Wait(200)
    end
end)

local function init()
    if QBX.PlayerData.job.name == 'taxi' then
        setLocationsBlip()

        for i = 1, #config.allowedVehicles, 1 do
            local model = config.allowedVehicles[i].model

            exports.ox_target:removeModel(model, {
                'taxi:toggleMeter',
                'taxi:useMeter',
                'taxi:npcMission'
            })

            exports.ox_target:addModel(model, {
                {
                    label = 'Affichage Taximetre',
                    name = 'taxi:toggleMeter',
                    event = 'qb-taxi:client:toggleMeter',
                    distance = 3,
                    canInteract = function()
                        return isDriver()
                    end,
                },
                {
                    label = 'Start/Stop Taximetre',
                    name = 'taxi:useMeter',
                    event = 'qb-taxi:client:enableMeter',
                    distance = 3,
                    canInteract = function()
                        return isDriver()
                    end,
                },
                {
                    label = 'Mission PNJ',
                    name = 'taxi:npcMission',
                    event = 'qb-taxi:client:DoTaxiNpc',
                    distance = 3,
                    canInteract = function()
                        return isDriver()
                    end,
                },
            })
        end
    end
end

RegisterNetEvent('QBCore:Client:OnJobUpdate', function()
    init()
end)

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    isLoggedIn = true
    init()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    isLoggedIn = false
end)

CreateThread(function()
    if not isLoggedIn then return end
    init()
end)