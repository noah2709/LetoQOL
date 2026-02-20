local addonName, addon = ...
local L     = addon.L or {}
local Utils = addon.Utils

---------------------------------------------------------------------------
-- Module registration
---------------------------------------------------------------------------
local module = {}
module.displayName = L["PET_REMINDER"] or "Pet Reminder"
module.dbKey       = "petReminder"
addon:RegisterModule("PetReminder", module)

---------------------------------------------------------------------------
-- Pet classes (only these get the reminder)
---------------------------------------------------------------------------
local PET_CLASSES = {
    HUNTER      = true,
    DEATHKNIGHT = true,
    WARLOCK     = true,
}

---------------------------------------------------------------------------
-- Local state
---------------------------------------------------------------------------
local isPetClass     = false
local displayFrame   -- draggable anchor frame
local displayText    -- FontString
local isUnlocked     = false

---------------------------------------------------------------------------
-- PET CHECKS
---------------------------------------------------------------------------

--- Is the player's pet alive and present?
local function HasPet()
    return UnitExists("pet") and not UnitIsDead("pet")
end

--- Is the pet currently in Passive stance?
local function IsPetPassive()
    if not HasPet() then return false end
    for i = 1, (NUM_PET_ACTION_SLOTS or 10) do
        local name, _, isToken, isActive = GetPetActionInfo(i)
        if isToken and isActive and name == "PET_MODE_PASSIVE" then
            return true
        end
    end
    return false
end

---------------------------------------------------------------------------
-- DISPLAY FRAME
---------------------------------------------------------------------------

local function CreateDisplay()
    if displayFrame then return end

    local db = LetoQOLDB.petReminder

    displayFrame = CreateFrame("Frame", "LetoQOLPetReminderDisplay", UIParent)
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
    displayText:SetTextColor(db.textColor.r, db.textColor.g, db.textColor.b)
    displayText:SetText("")

    displayFrame:Hide()
end

---------------------------------------------------------------------------
-- APPLY SETTINGS
---------------------------------------------------------------------------

local function ApplySettings()
    if not displayFrame or not displayText then return end
    local db = LetoQOLDB.petReminder
    displayText:SetFont(STANDARD_TEXT_FONT, db.textSize, "OUTLINE")
    displayText:SetTextColor(db.textColor.r, db.textColor.g, db.textColor.b)
end

---------------------------------------------------------------------------
-- CORE UPDATE
---------------------------------------------------------------------------

function module:CheckAndUpdate()
    if not displayFrame then return end
    if not isPetClass then displayFrame:Hide(); return end

    local db = LetoQOLDB and LetoQOLDB.petReminder
    if not db or not db.enabled then
        displayFrame:Hide()
        return
    end

    -- Don't touch while unlocked for positioning
    if isUnlocked then return end

    -- Group filter
    if db.showOnlyInGroup then
        if not (IsInGroup() or IsInRaid()) then
            displayFrame:Hide()
            return
        end
    end

    -- Priority: pet missing > pet passive
    if not HasPet() then
        displayText:SetText(L["PET_MISSING"] or "**Pet missing!**")
        displayFrame:Show()
    elseif IsPetPassive() then
        displayText:SetText(L["PET_PASSIVE"] or "**Pet passive!**")
        displayFrame:Show()
    else
        displayFrame:Hide()
    end
end

---------------------------------------------------------------------------
-- MODULE LIFECYCLE
---------------------------------------------------------------------------

function module:OnInitialize()
    local _, playerClass = UnitClass("player")
    isPetClass = PET_CLASSES[playerClass] or false
end

function module:OnEnable()
    if not isPetClass then return end

    CreateDisplay()

    local ef = CreateFrame("Frame")
    ef:RegisterEvent("UNIT_PET")
    ef:RegisterEvent("PET_BAR_UPDATE")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")
    ef:RegisterEvent("GROUP_ROSTER_UPDATE")
    ef:RegisterEvent("PLAYER_REGEN_DISABLED")
    ef:RegisterEvent("PLAYER_REGEN_ENABLED")
    ef:RegisterEvent("PET_BAR_UPDATE_USABLE")
    ef:SetScript("OnEvent", function(_, event, arg1)
        if event == "UNIT_PET" and arg1 ~= "player" then return end
        self:CheckAndUpdate()
    end)
    self.eventFrame = ef

    -- Polling fallback every 1 s
    self.ticker = C_Timer.NewTicker(1, function()
        self:CheckAndUpdate()
    end)
end

---------------------------------------------------------------------------
-- SETTINGS PANEL
---------------------------------------------------------------------------

function module:CreateSettingsPanel(parent)
    local db = LetoQOLDB.petReminder
    local UI = addon.UI
    local y  = 0

    -- Title
    UI.CreateSectionHeader(parent, 0, y, L["PET_REMINDER"] or "Pet Reminder")
    y = y - 30
    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Enabled
    UI.CreateCheckbox(parent, 0, y, L["ENABLED"] or "Enabled", db.enabled, function(v)
        db.enabled = v
        self:CheckAndUpdate()
    end)
    y = y - 34

    -- Show only in Party / Raid
    UI.CreateCheckbox(parent, 0, y, L["SHOW_ONLY_IN_GROUP"] or "Show only in Party / Raid", db.showOnlyInGroup, function(v)
        db.showOnlyInGroup = v
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
            displayText:SetText(L["PET_MISSING"] or "**Pet missing!**")
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
        db.position = { point = "CENTER", relPoint = "CENTER", x = 0, y = 150 }
        if displayFrame then
            displayFrame:ClearAllPoints()
            displayFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
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
            displayText:SetText(L["PET_MISSING"] or "**Pet missing!**")
            displayFrame:Show()
            C_Timer.After(3, function()
                if not isUnlocked then
                    self:CheckAndUpdate()
                end
            end)
        end
    end)
end

