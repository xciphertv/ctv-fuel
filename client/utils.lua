local Core = exports[Config.CoreResource]:GetCoreObject()
local Utils = {}

function Utils.LoadAnimDict(dict)
    if not HasAnimDictLoaded(dict) then
        RequestAnimDict(dict)
        while not HasAnimDictLoaded(dict) do
            Wait(10)
        end
    end
end

-- Vehicle-related utilities
function Utils.GetFuel(vehicle)
    return DecorGetFloat(vehicle, Config.FuelDecor)
end

function Utils.SetFuel(vehicle, fuel)
    if type(fuel) == 'number' and fuel >= 0 and fuel <= 100 then
        SetVehicleFuelLevel(vehicle, fuel + 0.0)
        DecorSetFloat(vehicle, Config.FuelDecor, GetVehicleFuelLevel(vehicle))
    end
end

function Utils.IsVehicleElectric(vehicle)
    if not vehicle or vehicle == 0 then return false end
    
    local vehModel = GetEntityModel(vehicle)
    local vehName = string.lower(GetDisplayNameFromVehicleModel(vehModel))
    
    return Config.ElectricVehicles[vehName] and Config.ElectricVehicles[vehName].isElectric
end

function Utils.GetClosestPump(coords, isElectric)
    local ped = PlayerPedId()
    local pumpModels = isElectric and {'electric_charger'} or Config.FuelPumpModels
    local closest = 1000.0
    local closestPump = nil
    local coordsToUse = coords or GetEntityCoords(ped)
    
    -- Get all objects in the area
    local objects = GetGamePool('CObject')
    
    for _, object in ipairs(objects) do
        local objModel = GetEntityModel(object)
        
        -- Check if the object is a fuel pump or electric charger
        for _, model in ipairs(pumpModels) do
            local modelHash = type(model) == 'string' and joaat(model) or model
            
            if objModel == modelHash then
                local pumpCoords = GetEntityCoords(object)
                local dist = #(coordsToUse - pumpCoords)
                
                if dist < closest then
                    closest = dist
                    closestPump = object
                end
            end
        end
    end
    
    if Config.FuelDebug and not closestPump then
        print((isElectric and "No electric charger" or "No fuel pump") .. " found nearby")
    end
    
    -- Return the coordinates and the entity
    return closestPump and GetEntityCoords(closestPump) or vector3(0, 0, 0), closestPump or 0
end

function Utils.IsPlayerNearVehicle()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local vehicle = Utils.GetClosestVehicle(coords)
    
    if not vehicle or vehicle == 0 then return false end
    
    local vehicleCoords = GetEntityCoords(vehicle)
    local dist = #(coords - vehicleCoords)
    
    return dist < 2.5
end

function Utils.GetClosestVehicle(coords)
    local ped = PlayerPedId()
    local vehicles = GetGamePool('CVehicle')
    local closestDistance = -1
    local closestVehicle = -1
    
    if coords then
        coords = type(coords) == 'table' and vec3(coords.x, coords.y, coords.z) or coords
    else
        coords = GetEntityCoords(ped)
    end
    
    for i = 1, #vehicles do
        local vehicleCoords = GetEntityCoords(vehicles[i])
        local distance = #(vehicleCoords - coords)
        
        if closestDistance == -1 or closestDistance > distance then
            closestVehicle = vehicles[i]
            closestDistance = distance
        end
    end
    
    return closestVehicle, closestDistance
end

function Utils.IsVehicleBlacklisted(veh)
    if not veh or veh == 0 then return false end
    
    local vehModel = GetEntityModel(veh)
    local vehName = string.lower(GetDisplayNameFromVehicleModel(vehModel))
    
    -- Check if electric vehicle and electric charging is disabled
    if not Config.ElectricVehicleCharging and 
       Config.ElectricVehicles[vehName] and 
       Config.ElectricVehicles[vehName].isElectric then
        return true
    end
    
    -- Check explicit blacklist
    if Config.NoFuelUsage[vehName] and Config.NoFuelUsage[vehName].blacklisted then
        return true
    end
    
    return false
end

-- Export utilities for external use
exports('GetFuel', Utils.GetFuel)
exports('SetFuel', Utils.SetFuel)

return Utils