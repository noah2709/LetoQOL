local addonName, addon = ...

---------------------------------------------------------------------------
-- Global reference so other addons/macros can access the API
---------------------------------------------------------------------------
LetoQOL = addon

---------------------------------------------------------------------------
-- Module registry
---------------------------------------------------------------------------
addon.modules = {}

function addon:RegisterModule(name, mod)
    self.modules[name] = mod
    mod.name = name
end

---------------------------------------------------------------------------
-- Default saved-variable values
---------------------------------------------------------------------------
local defaults = {
    charPaneEnhancement = {
        enabled             = true,
        showItemLevel       = true,
        showEnchants        = true,
        showGems            = true,
        showMissingEnchants = true,
        showAvgItemLevel    = true,
        showDurability      = true,
        showTotalDurability = true,
        ilvlColorMode       = "quality",   -- "quality" | "custom"
        ilvlCustomColor     = { r = 1, g = 1, b = 1 },
    },
    gatewayTracker = {
        enabled          = true,
        textSize         = 24,
        textColor        = { r = 0, g = 1, b = 0 },
        position         = { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 },
        showOnlyInCombat = false,
    },
    petReminder = {
        enabled          = true,
        textSize         = 24,
        textColor        = { r = 1, g = 1, b = 1 },
        position         = { point = "CENTER", relPoint = "CENTER", x = 0, y = 150 },
        showOnlyInGroup  = false,
    },
    focusInterrupt = {
        enabled        = true,
        markerIndex    = 8,  -- Skull by default
        autoMarkFocus  = true,
        markMode       = "focus",  -- "focus" | "mouseover"
    },
    autoRoleAccept = {
        enabled = true,
    },
    npcHelper = {
        enabled        = true,
        autoRepair     = true,
        useGuildRepair = true,
        autoSellJunk   = true,
    },
    teleportCompendium = {
        enabled = true,
    },
    hideTalkingHead = {
        enabled = true,
    },
    cursorRing = {
        enabled        = true,
        color          = { r = 0.25, g = 0.9, b = 1 },
        alpha          = 1,
        radius         = 18,
        thickness      = 3,
        glowEnabled    = true,
        glowAlpha      = 0.4,
        glowSpread     = 6,
        glowThickness  = 6,
    },
}

---------------------------------------------------------------------------
-- Helper – access the DB from anywhere via addon:GetDB()
---------------------------------------------------------------------------
function addon:GetDB()
    return LetoQOLDB
end

---------------------------------------------------------------------------
-- Bootstrap
---------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= addonName then return end

        -- Saved variables -------------------------------------------------
        if not LetoQOLDB then
            LetoQOLDB = addon.Utils.DeepCopy(defaults)
        else
            addon.Utils.MergeDefaults(LetoQOLDB, defaults)
        end

        -- Initialise modules -----------------------------------------------
        for _, mod in pairs(addon.modules) do
            if mod.OnInitialize then mod:OnInitialize() end
        end

        self:UnregisterEvent("ADDON_LOADED")

    elseif event == "PLAYER_LOGIN" then
        -- Enable modules ---------------------------------------------------
        for _, mod in pairs(addon.modules) do
            if mod.OnEnable then mod:OnEnable() end
        end

        -- Slash command ----------------------------------------------------
        SLASH_LETOQOL1 = "/qol"
        SlashCmdList["LETOQOL"] = function()
            addon:ToggleConfig()
        end

        -- Welcome message --------------------------------------------------
        local L = addon.L or {}
        print("|cFF00CCFF[LetoQOL]|r " .. (L["ADDON_LOADED"] or "Loaded. Type /qol to open settings."))
    end
end)

