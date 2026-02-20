local addonName, addon = ...
local L = addon.L or {}

---------------------------------------------------------------------------
-- Module registration
---------------------------------------------------------------------------
local module = {}
module.displayName = L["HIDE_TALKING_HEAD"] or "Hide Talking Head"
module.dbKey       = "hideTalkingHead"
addon:RegisterModule("HideTalkingHead", module)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function DisableTalkingHead()
    if not TalkingHeadFrame then return end

    TalkingHeadFrame:UnregisterAllEvents()
    TalkingHeadFrame:Hide()
end

local function EnableTalkingHead()
    if not TalkingHeadFrame then return end

    -- Re-register the events the Talking Head frame normally listens to
    TalkingHeadFrame:RegisterEvent("TALKINGHEAD_REQUESTED")
    TalkingHeadFrame:RegisterEvent("TALKINGHEAD_CLOSE")
    TalkingHeadFrame:RegisterEvent("SOUNDKIT_FINISHED")
    TalkingHeadFrame:RegisterEvent("LOADING_SCREEN_ENABLED")
end

---------------------------------------------------------------------------
-- MODULE LIFECYCLE
---------------------------------------------------------------------------

function module:OnInitialize()
    -- nothing required
end

function module:OnEnable()
    local db = LetoQOLDB and LetoQOLDB.hideTalkingHead
    if not db then return end

    -- The Blizzard_TalkingHeadUI addon is load-on-demand.
    -- It may or may not be loaded yet when our addon enables.
    local function ApplyState()
        if db.enabled then
            DisableTalkingHead()
        else
            EnableTalkingHead()
        end
    end

    -- If TalkingHeadFrame already exists, apply immediately
    if TalkingHeadFrame then
        ApplyState()
    end

    -- Hook into the addon loading to catch when Blizzard_TalkingHeadUI loads
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("ADDON_LOADED")
    ef:SetScript("OnEvent", function(_, event, loadedAddon)
        if loadedAddon == "Blizzard_TalkingHeadUI" then
            -- Small delay to let the frame fully initialise
            C_Timer.After(0.1, ApplyState)
            ef:UnregisterEvent("ADDON_LOADED")
        end
    end)

    -- Also hook Show so that even if something else triggers it, we block it
    if TalkingHeadFrame then
        hooksecurefunc(TalkingHeadFrame, "Show", function(frame)
            if db.enabled then
                frame:Hide()
            end
        end)
    else
        -- Wait for the frame to exist, then hook
        local hookFrame = CreateFrame("Frame")
        hookFrame:RegisterEvent("ADDON_LOADED")
        hookFrame:SetScript("OnEvent", function(_, _, loadedAddon)
            if loadedAddon == "Blizzard_TalkingHeadUI" then
                C_Timer.After(0.1, function()
                    if TalkingHeadFrame then
                        hooksecurefunc(TalkingHeadFrame, "Show", function(frame)
                            if db.enabled then
                                frame:Hide()
                            end
                        end)
                        ApplyState()
                    end
                end)
                hookFrame:UnregisterEvent("ADDON_LOADED")
            end
        end)
    end

    self.ApplyState = ApplyState
end

---------------------------------------------------------------------------
-- SETTINGS PANEL
---------------------------------------------------------------------------

function module:CreateSettingsPanel(parent)
    local db = LetoQOLDB.hideTalkingHead
    local UI = addon.UI
    local y  = 0

    -- Title
    UI.CreateSectionHeader(parent, 0, y, L["HIDE_TALKING_HEAD"] or "Hide Talking Head")
    y = y - 30
    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Enabled
    UI.CreateCheckbox(parent, 0, y, L["ENABLED"] or "Enabled", db.enabled, function(v)
        db.enabled = v
        if self.ApplyState then self.ApplyState() end
    end)
    y = y - 40

    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Description
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, y)
    desc:SetText(L["HIDE_TALKING_HEAD_DESC"] or "Hides the Talking Head popup that appears during quests and events.")
    desc:SetTextColor(0.7, 0.7, 0.7)
    desc:SetWidth(480)
    desc:SetWordWrap(true)
    desc:SetJustifyH("LEFT")
end

