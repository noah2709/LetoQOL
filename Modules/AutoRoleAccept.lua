local addonName, addon = ...
local L = addon.L or {}

---------------------------------------------------------------------------
-- Module registration
---------------------------------------------------------------------------
local module = {}
module.displayName = L["AUTO_ROLE_ACCEPT"] or "Auto Role Accept"
module.dbKey       = "autoRoleAccept"
addon:RegisterModule("AutoRoleAccept", module)

---------------------------------------------------------------------------
-- MODULE LIFECYCLE
---------------------------------------------------------------------------

function module:OnInitialize()
    -- nothing required
end

function module:OnEnable()
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("LFG_ROLE_CHECK_SHOW")
    ef:SetScript("OnEvent", function()
        local db = LetoQOLDB and LetoQOLDB.autoRoleAccept
        if not db or not db.enabled then return end

        -- Confirm the role popup automatically
        CompleteLFGRoleCheck(true)
    end)
    self.eventFrame = ef
end

---------------------------------------------------------------------------
-- SETTINGS PANEL
---------------------------------------------------------------------------

function module:CreateSettingsPanel(parent)
    local db = LetoQOLDB.autoRoleAccept
    local UI = addon.UI
    local y  = 0

    -- Title
    UI.CreateSectionHeader(parent, 0, y, L["AUTO_ROLE_ACCEPT"] or "Auto Role Accept")
    y = y - 30
    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Enabled
    UI.CreateCheckbox(parent, 0, y, L["ENABLED"] or "Enabled", db.enabled, function(v)
        db.enabled = v
    end)
    y = y - 40

    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Description
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, y)
    desc:SetText(L["AUTO_ROLE_ACCEPT_DESC"] or "Automatically confirms your role when the group leader queues for content.")
    desc:SetTextColor(0.7, 0.7, 0.7)
    desc:SetWidth(480)
    desc:SetWordWrap(true)
    desc:SetJustifyH("LEFT")
end


