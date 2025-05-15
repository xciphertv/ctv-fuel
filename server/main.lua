local Core = exports[Config.CoreResource]:GetCoreObject()
local SharedUtils = require('shared.utils')

-- Fuel payment processing
lib.callback.register('cdn-fuel:server:payForFuel', function(source, amount, paymentType, fuelPrice)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player then return false end
    
    local total = math.ceil(amount)
    if amount < 1 then total = 0 end
    
    -- Payment descriptor based on payment type
    local paymentDesc = "Gas Station Fuel Purchase"
    
    -- Remove money based on payment type
    if Player.Functions.RemoveMoney(paymentType, total, paymentDesc) then
        return true
    else
        return false
    end
end)

-- Jerry Can purchase processing
RegisterNetEvent('cdn-fuel:server:purchaseJerryCan', function(paymentType)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local tax = SharedUtils.GlobalTax(Config.JerryCanPrice)
    local total = math.ceil(Config.JerryCanPrice + tax)
    
    -- Check if player can afford
    if not Player.Functions.RemoveMoney(paymentType, total, "Jerry Can Purchase") then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Fuel System',
            description = 'Not enough money',
            type = 'error'
        })
        return
    end
    
    -- Add jerry can to inventory
    if Config.UseOxInventory then
        exports.ox_inventory:AddItem(src, 'jerrycan', 1, {fuel = Config.JerryCanGas})
    else
        Player.Functions.AddItem("jerrycan", 1, false, {gasamount = Config.JerryCanGas})
        TriggerClientEvent('inventory:client:ItemBox', src, Core.Shared.Items['jerrycan'], "add")
    end
    
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Fuel System',
        description = 'Purchased jerry can',
        type = 'success'
    })
end)

-- Update jerry can fuel level
RegisterNetEvent('cdn-fuel:server:updateJerryCan', function(action, amount, itemData)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player then return end
    
    if Config.UseOxInventory then
        -- Get current fuel amount
        local currentFuel = tonumber(itemData.metadata.fuel)
        local newFuel
        
        if action == "add" then
            newFuel = math.min(currentFuel + amount, Config.JerryCanCap)
        else
            newFuel = math.max(currentFuel - amount, 0)
        end
        
        -- Update item metadata
        exports.ox_inventory:SetMetadata(src, itemData.slot, {fuel = newFuel})
    else
        -- Get player inventory items
        local items = Player.PlayerData.items
        
        -- Find and update jerry can
        for slot, item in pairs(items) do
            if item.name == 'jerrycan' and slot == itemData.slot then
                if not item.info then item.info = {} end
                if not item.info.gasamount then item.info.gasamount = 0 end
                
                if action == "add" then
                    item.info.gasamount = math.min(item.info.gasamount + amount, Config.JerryCanCap)
                else
                    item.info.gasamount = math.max(item.info.gasamount - amount, 0)
                end
                
                Player.Functions.SetInventory(items)
                break
            end
        end
    end
end)

-- Update syphoning kit fuel level
RegisterNetEvent('cdn-fuel:server:updateSyphonKit', function(action, amount, itemData)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player then return end
    
    if Config.UseOxInventory then
        -- Get current fuel amount
        local currentFuel = tonumber(itemData.metadata.fuel) or 0
        local newFuel
        
        if action == "add" then
            newFuel = math.min(currentFuel + amount, Config.SyphonKitCap)
        else
            newFuel = math.max(currentFuel - amount, 0)
        end
        
        -- Update item metadata
        exports.ox_inventory:SetMetadata(src, itemData.slot, {fuel = newFuel})
    else
        -- Get player inventory items
        local items = Player.PlayerData.items
        
        -- Find and update syphoning kit
        for slot, item in pairs(items) do
            if item.name == 'syphoningkit' and slot == itemData.slot then
                if not item.info then item.info = {} end
                if not item.info.gasamount then item.info.gasamount = 0 end
                
                if action == "add" then
                    item.info.gasamount = math.min(item.info.gasamount + amount, Config.SyphonKitCap)
                else
                    item.info.gasamount = math.max(item.info.gasamount - amount, 0)
                end
                
                Player.Functions.SetInventory(items)
                break
            end
        end
    end
end)

-- Syphoning police alert
RegisterNetEvent('cdn-fuel:server:callPolice', function(coords)
    local src = source
    local players = Core.Functions.GetQBPlayers()
    
    for _, Player in pairs(players) do
        if Player.PlayerData.job.name == 'police' and Player.PlayerData.job.onduty then
            TriggerClientEvent('cdn-fuel:client:createSyphonBlip', Player.PlayerData.source, coords)
        end
    end
end)

-- Register usable items
if Config.UseJerryCan then
    if Config.UseOxInventory then
        exports.ox_inventory:registerHook('usedItem:jerrycan', function(data)
            TriggerClientEvent('cdn-fuel:client:jerryCanMenu', data.source, data.item)
            return false
        end)
    else
        Core.Functions.CreateUseableItem("jerrycan", function(source, item)
            TriggerClientEvent('cdn-fuel:client:jerryCanMenu', source, item)
        end)
    end
end

if Config.UseSyphoning then
    if Config.UseOxInventory then
        exports.ox_inventory:registerHook('usedItem:syphoningkit', function(data)
            TriggerClientEvent('cdn-fuel:client:syphonMenu', data.source, data.item)
            return false
        end)
    else
        Core.Functions.CreateUseableItem("syphoningkit", function(source, item)
            TriggerClientEvent('cdn-fuel:client:syphonMenu', source, item)
        end)
    end
end

-- Version checker
local function CheckVersion(err, responseText, headers)
    local curVersion = LoadResourceFile(GetCurrentResourceName(), "version")
    
    if not responseText then
        print("^1CDN-Fuel version check failed^7")
        return
    end
    
    if curVersion and responseText then
        local color = curVersion == responseText and "^2" or "^1"
        
        print("^1----------------------------------------------------------------------------------^7")
        print("CDN-Fuel's latest version is: ^2"..responseText.."^7!\nYour current version: "..color..""..curVersion.."^7!")
        print("^1----------------------------------------------------------------------------------^7")
    end
end

-- Check for updates on resource start
AddEventHandler('onResourceStart', function(resource)
    if resource == GetCurrentResourceName() then
        local updatePath = "/CodineDev/cdn-fuel"
        PerformHttpRequest("https://raw.githubusercontent.com"..updatePath.."/master/version", CheckVersion, "GET")
    end
end)