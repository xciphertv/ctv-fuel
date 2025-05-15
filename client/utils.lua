local Core = exports[Config.CoreResource]:GetCoreObject()
local Utils = {}

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