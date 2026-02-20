local _, addon = ...

addon.Utils = {}
local Utils = addon.Utils

--- Deep-copy a table (recursive)
function Utils.DeepCopy(orig)
    if type(orig) ~= "table" then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[k] = Utils.DeepCopy(v)
    end
    return copy
end

--- Merge default values into a target table (non-destructive)
function Utils.MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            if type(v) == "table" then
                target[k] = Utils.DeepCopy(v)
            else
                target[k] = v
            end
        elseif type(v) == "table" and type(target[k]) == "table" then
            Utils.MergeDefaults(target[k], v)
        end
    end
end

--- Get RGB colour for an item quality (0-5)
function Utils.GetQualityColor(quality)
    if quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
        local c = ITEM_QUALITY_COLORS[quality]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

--- Return an inline-texture escape sequence for use in FontStrings
function Utils.InlineIcon(icon, size)
    size = size or 14
    if not icon then return "" end
    return string.format("|T%s:%d:%d:0:0|t", tostring(icon), size, size)
end

--- Abbreviate a string to *maxLen* characters (with ".." suffix)
function Utils.Abbreviate(text, maxLen)
    if not text then return "" end
    maxLen = maxLen or 20
    if #text > maxLen then
        return text:sub(1, maxLen - 2) .. ".."
    end
    return text
end


