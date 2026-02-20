local addonName, addon = ...
local L     = addon.L or {}
local Utils = addon.Utils

---------------------------------------------------------------------------
-- Module registration
---------------------------------------------------------------------------
local module = {}
module.displayName = L["GATEWAY_TRACKER"] or "Gateway Tracker"
module.dbKey       = "gatewayTracker"
addon:RegisterModule("GatewayTracker", module)

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local ITEM_ID      = 188152
local DISPLAY_TEXT = "GATEWAY USABLE"

---------------------------------------------------------------------------
-- Local state
---------------------------------------------------------------------------
local displayFrame   -- the movable on-screen frame
local displayText    -- the FontString inside it
local ticker         -- C_Timer ticker handle
local isUnlocked = false

---------------------------------------------------------------------------
-- ITEM USABILITY CHECK
---------------------------------------------------------------------------

local function IsGatewayUsable()
    -- Must own the item (bag, toy, or equipped)
    local count = GetItemCount(ITEM_ID) or 0
    local hasToy = PlayerHasToy and PlayerHasToy(ITEM_ID)
    if count == 0 and not hasToy then return false end

    -- Must be usable (class, level, etc.)
    local usable = IsUsableItem(ITEM_ID)
    if not usable then return false end

    -- Must not be on cooldown
    local start, duration = GetItemCooldown(ITEM_ID)
    if start and start > 0 and duration and duration > 0 then
        if (start + duration - GetTime()) > 0 then
            return false
        end
    end

    return true
end

---------------------------------------------------------------------------
-- DISPLAY FRAME
---------------------------------------------------------------------------

local function CreateDisplay()
    if displayFrame then return end

    local db = LetoQOLDB.gatewayTracker

    displayFrame = CreateFrame("Frame", "LetoQOLGatewayDisplay", UIParent)
    displayFrame:SetSize(300, 40)
    displayFrame:SetPoint(
        db.position.point,
        UIParent,
        db.position.relPoint or db.position.point,
        db.position.x,
        db.position.y
    )
    displayFrame:SetMovable(true)
    displayFrame:EnableMouse(false)   -- locked by default
    displayFrame:RegisterForDrag("LeftButton")
    displayFrame:SetClampedToScreen(true)
    displayFrame:SetFrameStrata("HIGH")

    displayFrame:SetScript("OnDragStart", function(self)
        if self.unlocked then self:StartMoving() end
    end)
    displayFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        db.position.point    = point
        db.position.relPoint = relPoint or point
        db.position.x        = x
        db.position.y        = y
    end)

    displayText = displayFrame:CreateFontString(nil, "OVERLAY")
    displayText:SetFont(STANDARD_TEXT_FONT, db.textSize, "OUTLINE")
    displayText:SetPoint("CENTER")
    displayText:SetText(DISPLAY_TEXT)
    displayText:SetTextColor(db.textColor.r, db.textColor.g, db.textColor.b)

    displayFrame:Hide()
end

---------------------------------------------------------------------------
-- APPLY SETTINGS (text size, colour)
---------------------------------------------------------------------------

local function ApplySettings()
    if not displayFrame or not displayText then return end
    local db = LetoQOLDB.gatewayTracker

    displayText:SetFont(STANDARD_TEXT_FONT, db.textSize, "OUTLINE")
    displayText:SetTextColor(db.textColor.r, db.textColor.g, db.textColor.b)
end

---------------------------------------------------------------------------
-- CORE UPDATE LOOP
---------------------------------------------------------------------------

function module:CheckAndUpdate()
    if not displayFrame then return end

    local db = LetoQOLDB and LetoQOLDB.gatewayTracker
    if not db or not db.enabled then
        displayFrame:Hide()
        return
    end

    -- Don't touch visibility while unlocked for positioning
    if isUnlocked then return end

    local shouldShow = IsGatewayUsable()

    if shouldShow and db.showOnlyInCombat then
        shouldShow = UnitAffectingCombat("player")
    end

    displayFrame:SetShown(shouldShow)
end

---------------------------------------------------------------------------
-- MODULE LIFECYCLE
---------------------------------------------------------------------------

function module:OnInitialize()
    -- nothing required
end

function module:OnEnable()
    CreateDisplay()

    -- Events that might change item usability
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("BAG_UPDATE_COOLDOWN")
    ef:RegisterEvent("BAG_UPDATE")
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    ef:RegisterEvent("UNIT_INVENTORY_CHANGED")
    ef:SetScript("OnEvent", function()
        self:CheckAndUpdate()
    end)
    self.eventFrame = ef

    -- Reliable polling every 0.5 s
    ticker = C_Timer.NewTicker(0.5, function()
        self:CheckAndUpdate()
    end)
end

---------------------------------------------------------------------------
-- SETTINGS PANEL
---------------------------------------------------------------------------

function module:CreateSettingsPanel(parent)
    local db = LetoQOLDB.gatewayTracker
    local UI = addon.UI
    local y  = 0

    -- Title
    UI.CreateSectionHeader(parent, 0, y, L["GATEWAY_TRACKER"] or "Gateway Tracker")
    y = y - 30
    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Enabled
    UI.CreateCheckbox(parent, 0, y, L["ENABLED"] or "Enabled", db.enabled, function(v)
        db.enabled = v
        self:CheckAndUpdate()
    end)
    y = y - 34

    -- Show only in Combat
    UI.CreateCheckbox(parent, 0, y, L["SHOW_ONLY_IN_COMBAT"] or "Show only in Combat", db.showOnlyInCombat, function(v)
        db.showOnlyInCombat = v
        self:CheckAndUpdate()
    end)
    y = y - 40

    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Text Size
    UI.CreateSlider(parent, 0, y, L["TEXT_SIZE"] or "Text Size", 10, 60, 1, db.textSize, function(val)
        db.textSize = val
        ApplySettings()
    end)
    y = y - 55

    -- Text Color
    UI.CreateColorSwatch(parent, 0, y, L["TEXT_COLOR"] or "Text Color",
        db.textColor.r, db.textColor.g, db.textColor.b,
        function(r, g, b)
            db.textColor.r = r
            db.textColor.g = g
            db.textColor.b = b
            ApplySettings()
        end
    )
    y = y - 40

    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Position section
    UI.CreateSectionHeader(parent, 0, y, L["TEXT_POSITION"] or "Text Position")
    y = y - 26

    local posDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    posDesc:SetPoint("TOPLEFT", 0, y)
    posDesc:SetText(L["DRAG_TO_MOVE"] or "Drag the text on screen to reposition it.")
    posDesc:SetTextColor(0.7, 0.7, 0.7)
    y = y - 26

    -- Unlock / Lock button
    local lockBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    lockBtn:SetSize(130, 24)
    lockBtn:SetPoint("TOPLEFT", 0, y)
    lockBtn:SetText(L["UNLOCK_POSITION"] or "Unlock")

    lockBtn:SetScript("OnClick", function()
        CreateDisplay()
        if not displayFrame then return end
        if isUnlocked then
            -- LOCK
            isUnlocked = false
            displayFrame.unlocked = false
            displayFrame:EnableMouse(false)
            lockBtn:SetText(L["UNLOCK_POSITION"] or "Unlock")
            self:CheckAndUpdate()
        else
            -- UNLOCK
            isUnlocked = true
            displayFrame.unlocked = true
            displayFrame:EnableMouse(true)
            ApplySettings()
            displayFrame:Show()
            lockBtn:SetText(L["LOCK_POSITION"] or "Lock")
        end
    end)

    -- Reset Position button
    local resetBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    resetBtn:SetSize(130, 24)
    resetBtn:SetPoint("LEFT", lockBtn, "RIGHT", 10, 0)
    resetBtn:SetText(L["RESET_POSITION"] or "Reset Position")
    resetBtn:SetScript("OnClick", function()
        db.position = { point = "CENTER", relPoint = "CENTER", x = 0, y = 200 }
        if displayFrame then
            displayFrame:ClearAllPoints()
            displayFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
        end
    end)

    -- Test / Preview button
    local testBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    testBtn:SetSize(130, 24)
    testBtn:SetPoint("LEFT", resetBtn, "RIGHT", 10, 0)
    testBtn:SetText(L["TEST_POSITION"] or "Test / Preview")
    testBtn:SetScript("OnClick", function()
        CreateDisplay()
        if displayFrame then
            ApplySettings()
            displayFrame:Show()
            C_Timer.After(3, function()
                if not isUnlocked then
                    self:CheckAndUpdate()
                end
            end)
        end
    end)
end

