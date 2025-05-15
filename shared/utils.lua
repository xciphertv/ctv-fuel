-- Shared utility functions
local SharedUtils = {}

-- Calculate global tax
function SharedUtils.GlobalTax(value)
    if Config.GlobalTax < 0.1 then
        return 0
    end
    local tax = (value / 100 * Config.GlobalTax)
    return tax
end

-- Format numbers with commas
function SharedUtils.FormatNumber(amount)
    local formatted = amount
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k==0) then
            break
        end
    end
    return formatted
end

-- Calculate percentage
function SharedUtils.PercentOf(percent, maxvalue)
    if tonumber(percent) and tonumber(maxvalue) then
        return (maxvalue * percent) / 100
    end
    return false
end

-- Round numbers to a specified decimal place
function SharedUtils.Round(num, numDecimalPlaces)
    local mult = 10^(numDecimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- Convert a string to title case
function SharedUtils.TitleCase(str)
    return string.gsub(str, "(%a)([%w_']*)",
        function(first, rest)
            return first:upper() .. rest:lower()
        end
    )
end

-- Check if table contains a value
function SharedUtils.TableContains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

-- Get table length
function SharedUtils.TableLength(table)
    local count = 0
    for _ in pairs(table) do
        count = count + 1
    end
    return count
end

-- Clone a table
function SharedUtils.TableClone(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = SharedUtils.TableClone(orig_value)
        end
    else
        copy = orig
    end
    return copy
end

return SharedUtils