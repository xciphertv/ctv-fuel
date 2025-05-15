local Core = exports[Config.CoreResource]:GetCoreObject()
local SharedUtils = require('shared.utils')

-- Process electric charging payment
RegisterNetEvent('cdn-fuel:server:electric:payForCharging', function(amount, paymentType, chargePrice)
    local src = source
    local Player = Core.Functions.GetPlayer(src)
    
    if not Player then return end
    
    local total = math.ceil(amount)
    if amount < 1 then total = 0 end
    
    -- Payment descriptor based on payment type
    local paymentDesc = "Electric Vehicle Charging"
    
    -- Remove money
    if Player.Functions.RemoveMoney(paymentType, total, paymentDesc) then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Electric Charger',
            description = 'Payment successful',
            type = 'success'
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Electric Charger',
            description = 'Payment failed',
            type = 'error'
        })
    end
end)

-- Phone payment system
if Config.RenewedPhonePayment then
    RegisterNetEvent('cdn-fuel:server:electric:phone:payForCharge', function(amount)
        local src = source
        local Player = Core.Functions.GetPlayer(src)
        
        if not Player then return end
        
        -- Calculate charge price
        local chargePrice = Config.ElectricChargingPrice
        
        -- Apply emergency services discount if applicable
        if Config.EmergencyServicesDiscount.enabled then
            local plyJob = Player.PlayerData.job.name
            local isEligible = false
            
            if type(Config.EmergencyServicesDiscount.job) == "table" then
                for i = 1, #Config.EmergencyServicesDiscount.job do
                    if plyJob == Config.EmergencyServicesDiscount.job[i] then
                        isEligible = true
                        break
                    end
                end
            elseif plyJob == Config.EmergencyServicesDiscount.job then
                isEligible = true
            end
            
            if isEligible then
                if Config.EmergencyServicesDiscount.ondutyonly and not Player.PlayerData.job.onduty then
                    -- No discount if not on duty
                else
                    local discount = Config.EmergencyServicesDiscount.discount
                    if discount > 0 then
                        if discount >= 100 then
                            chargePrice = 0
                        else
                            chargePrice = chargePrice * (1 - (discount / 100))
                        end
                    end
                end
            end
        end
        
        -- Calculate total cost
        local cost = amount * chargePrice
        local tax = SharedUtils.GlobalTax(cost)
        local total = math.ceil(cost + tax)
        
        -- Process payment
        local success = Player.Functions.RemoveMoney('bank', total, "Electric Vehicle Charging")
        
        if success then
            TriggerClientEvent('cdn-fuel:client:electric:updateChargeState', src, true, amount)
            
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Electric Charger',
                description = 'Payment successful',
                type = 'success'
            })
        else
            TriggerClientEvent('cdn-fuel:client:electric:updateChargeState', src, false, 0)
            
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'Electric Charger',
                description = 'Not enough money in bank',
                type = 'error'
            })
        end
    end)
    
    -- Refund money if charging is cancelled
    RegisterNetEvent('cdn-fuel:server:electric:phone:refundMoney', function(amount)
        local src = source
        local Player = Core.Functions.GetPlayer(src)
        
        if not Player then return end
        
        if amount <= 0 then return end
        
        Player.Functions.AddMoney('bank', math.ceil(amount), "Electric Charging Refund")
        
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Electric Charger',
            description = 'Refunded $' .. math.ceil(amount),
            type = 'success'
        })
    end)
end