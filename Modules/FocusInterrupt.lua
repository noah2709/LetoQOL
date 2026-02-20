local addonName, addon = ...
local L     = addon.L or {}
local Utils = addon.Utils

---------------------------------------------------------------------------
-- Module registration
---------------------------------------------------------------------------
local module = {}
module.displayName = L["FOCUS_INTERRUPT"] or "Focus Interrupt"
module.dbKey       = "focusInterrupt"
addon:RegisterModule("FocusInterrupt", module)

---------------------------------------------------------------------------
-- Keybinding header  (shows up in ESC → Key Bindings → AddOns → LetoQOL)
-- Bindings.xml declares the binding; these globals provide the display names.
---------------------------------------------------------------------------
BINDING_HEADER_LETOQOL = "LetoQOL"
_G["BINDING_NAME_CLICK LetoQOLFocusMarkBtn:LeftButton"] =
        L["MARK_FOCUS_TARGET"] or "Mark Focus Target"

---------------------------------------------------------------------------
-- Raid Target Marker data
---------------------------------------------------------------------------
local MARKERS = {
    { index = 1, chat = "{rt1}", name = "Star",     icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1" },
    { index = 2, chat = "{rt2}", name = "Circle",   icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_2" },
    { index = 3, chat = "{rt3}", name = "Diamond",  icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_3" },
    { index = 4, chat = "{rt4}", name = "Triangle", icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_4" },
    { index = 5, chat = "{rt5}", name = "Moon",     icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_5" },
    { index = 6, chat = "{rt6}", name = "Square",   icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_6" },
    { index = 7, chat = "{rt7}", name = "Cross",    icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_7" },
    { index = 8, chat = "{rt8}", name = "Skull",    icon = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8" },
}

---------------------------------------------------------------------------
-- Chat announcement (on ready check)
---------------------------------------------------------------------------
local function GetChatChannel()
    if IsInGroup() then
        return "PARTY"
    end
    return nil
end

local function AnnounceInterrupt()
    local db = LetoQOLDB and LetoQOLDB.focusInterrupt
    if not db or not db.enabled then return end

    local channel = GetChatChannel()
    if not channel then return end

    local marker = MARKERS[db.markerIndex] or MARKERS[1]
    local msg = "My focus interrupt is " .. marker.chat

    SendChatMessage(msg, channel)
end

---------------------------------------------------------------------------
-- MARK FOCUS / MOUSEOVER TARGET  (SecureActionButton + /tm macro)
---------------------------------------------------------------------------
local markBtn

local function BuildMacroText(markerIndex, mode)
    local idx = markerIndex or 8
    if mode == "mouseover" then
        -- Set mouseover as focus, target it, mark it, switch back
        return "/focus [@mouseover,exists]\n/target [@mouseover,exists]\n/tm " .. idx .. "\n/targetlasttarget"
    else
        -- Target focus unit, mark it, switch back
        return "/targetfocus\n/tm " .. idx .. "\n/targetlasttarget"
    end
end

local function CreateMarkButton(db)
    if markBtn then return end

    markBtn = CreateFrame("Button", "LetoQOLFocusMarkBtn", UIParent,
                          "SecureActionButtonTemplate")
    markBtn:SetSize(28, 28)
    markBtn:SetFrameStrata("MEDIUM")
    markBtn:RegisterForClicks("AnyUp", "AnyDown")

    -- Secure macro action
    markBtn:SetAttribute("type", "macro")
    markBtn:SetAttribute("macrotext", BuildMacroText(db.markerIndex, db.markMode))

    -- Icon (shows current marker)
    local icon = markBtn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. (db.markerIndex or 8))
    markBtn.icon = icon

    -- Highlight on hover
    local hl = markBtn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.25)

    -- Tooltip  (shows keybind + mode)
    markBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local label = L["MARK_FOCUS_TARGET"] or "Mark Focus Target"
        local key = GetBindingKey("CLICK LetoQOLFocusMarkBtn:LeftButton")
        if key then
            GameTooltip:SetText(label .. "  |cFFFFD100(" .. key .. ")|r")
        else
            GameTooltip:SetText(label)
        end
        local modeLabel = db.markMode == "mouseover"
            and (L["MARK_MODE_MOUSEOVER"] or "Mouseover")
            or  (L["MARK_MODE_FOCUS"] or "Focus Target")
        GameTooltip:AddLine((L["MARK_MODE"] or "Mark Mode") .. ": |cFFFFFFFF" .. modeLabel .. "|r",
                            0.7, 0.7, 0.7)
        GameTooltip:AddLine(L["MARK_FOCUS_KEYBIND_HINT"]
            or "Bind via ESC → Key Bindings → LetoQOL", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    markBtn:SetScript("OnLeave", GameTooltip_Hide)

    -- Anchor to FocusFrame if available, otherwise fallback
    markBtn:ClearAllPoints()
    if FocusFrame then
        markBtn:SetPoint("LEFT", FocusFrame, "RIGHT", 4, 0)
    else
        markBtn:SetPoint("CENTER", UIParent, "CENTER", 300, 200)
    end

    -- Button is always hidden – interaction via keybind only
    markBtn:Hide()

    -- Store update helpers on the module
    module._UpdateMarkButton = function()
        if InCombatLockdown() then return end
        local idx = db.markerIndex or 8
        markBtn:SetAttribute("macrotext", BuildMacroText(idx, db.markMode))
        markBtn.icon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. idx)
    end
end

---------------------------------------------------------------------------
-- MODULE LIFECYCLE
---------------------------------------------------------------------------

function module:OnInitialize()
    -- nothing required
end

function module:OnEnable()
    local db = LetoQOLDB and LetoQOLDB.focusInterrupt
    if not db then return end

    -- Ready check announcements
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("READY_CHECK")
    ef:SetScript("OnEvent", function(_, event)
        if event == "READY_CHECK" then
            AnnounceInterrupt()
        end
    end)
    self.eventFrame = ef

    -- Mark button (secure)
    CreateMarkButton(db)
end

---------------------------------------------------------------------------
-- SETTINGS PANEL
---------------------------------------------------------------------------

function module:CreateSettingsPanel(parent)
    local db = LetoQOLDB.focusInterrupt
    local UI = addon.UI
    local y  = 0

    -- Title
    UI.CreateSectionHeader(parent, 0, y, L["FOCUS_INTERRUPT"] or "Focus Interrupt")
    y = y - 30
    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Enabled
    UI.CreateCheckbox(parent, 0, y, L["ENABLED"] or "Enabled", db.enabled, function(v)
        db.enabled = v
        if module._UpdateMarkButton then module._UpdateMarkButton() end
    end)
    y = y - 40

    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Description
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, y)
    desc:SetText(L["FOCUS_INTERRUPT_DESC"] or "On ready check, announces your focus interrupt marker in party chat.")
    desc:SetTextColor(0.7, 0.7, 0.7)
    desc:SetWidth(480)
    desc:SetWordWrap(true)
    desc:SetJustifyH("LEFT")
    y = y - 24

    -- Preview of the message
    local previewLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    previewLabel:SetPoint("TOPLEFT", 0, y)
    previewLabel:SetText("|cFFFFD100" .. (L["PREVIEW"] or "Preview") .. ":|r")
    y = y - 20

    local previewText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    previewText:SetPoint("TOPLEFT", 0, y)

    local function UpdatePreview()
        local marker = MARKERS[db.markerIndex] or MARKERS[1]
        local iconStr = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. marker.index .. ":16|t"
        previewText:SetText("My focus interrupt is " .. iconStr)
    end
    UpdatePreview()
    y = y - 34

    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Icon Picker
    local pickerHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pickerHeader:SetPoint("TOPLEFT", 0, y)
    pickerHeader:SetText("|cFFFFD100" .. (L["ICON_PICKER"] or "Icon Picker") .. "|r")
    y = y - 26

    local ICON_SIZE   = 36
    local ICON_GAP    = 8

    local iconButtons = {}
    for i, marker in ipairs(MARKERS) do
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(ICON_SIZE, ICON_SIZE)
        btn:SetPoint("TOPLEFT", (i - 1) * (ICON_SIZE + ICON_GAP), y)

        local tex = btn:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(marker.icon)
        btn.icon = tex

        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetPoint("TOPLEFT", -3, 3)
        border:SetPoint("BOTTOMRIGHT", 3, -3)
        border:SetColorTexture(1, 0.82, 0, 0.6)
        border:SetDrawLayer("OVERLAY", -1)
        border:Hide()
        btn.border = border

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(marker.name)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        btn:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
            db.markerIndex = marker.index
            for _, b in ipairs(iconButtons) do b.border:Hide() end
            btn.border:Show()
            UpdatePreview()
            if module._UpdateMarkButton then module._UpdateMarkButton() end
        end)

        if marker.index == db.markerIndex then btn.border:Show() end
        iconButtons[i] = btn
    end

    y = y - ICON_SIZE - 16

    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Mark Mode: Focus / Mouseover toggle buttons
    local modeLabel = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modeLabel:SetPoint("TOPLEFT", 0, y)
    modeLabel:SetText("|cFFFFD100" .. (L["MARK_MODE"] or "Mark Mode") .. ":|r")
    y = y - 4

    local focusBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    focusBtn:SetSize(130, 24)
    focusBtn:SetPoint("TOPLEFT", 120, y)
    focusBtn:SetText(L["MARK_MODE_FOCUS"] or "Focus Target")

    local moBtn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    moBtn:SetSize(130, 24)
    moBtn:SetPoint("LEFT", focusBtn, "RIGHT", 6, 0)
    moBtn:SetText(L["MARK_MODE_MOUSEOVER"] or "Mouseover")

    local function UpdateModeButtons()
        if db.markMode == "mouseover" then
            moBtn:GetFontString():SetTextColor(0, 1, 0)
            focusBtn:GetFontString():SetTextColor(1, 1, 1)
        else
            focusBtn:GetFontString():SetTextColor(0, 1, 0)
            moBtn:GetFontString():SetTextColor(1, 1, 1)
        end
    end
    UpdateModeButtons()

    focusBtn:SetScript("OnClick", function()
        db.markMode = "focus"
        UpdateModeButtons()
        if module._UpdateMarkButton then module._UpdateMarkButton() end
    end)

    moBtn:SetScript("OnClick", function()
        db.markMode = "mouseover"
        UpdateModeButtons()
        if module._UpdateMarkButton then module._UpdateMarkButton() end
    end)

    y = y - 32

    -- Description for mark focus
    local markDesc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    markDesc:SetPoint("TOPLEFT", 0, y)
    markDesc:SetText(L["AUTO_MARK_FOCUS_DESC"] or "Shows a small button near the focus frame. Click it (or press the keybind) to mark your target with the selected icon.")
    markDesc:SetTextColor(0.7, 0.7, 0.7)
    markDesc:SetWidth(480)
    markDesc:SetWordWrap(true)
    markDesc:SetJustifyH("LEFT")
    y = y - 30

    -- Keybind hint
    local keybindHint = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keybindHint:SetPoint("TOPLEFT", 0, y)
    local currentKey = GetBindingKey("CLICK LetoQOLFocusMarkBtn:LeftButton")
    if currentKey then
        keybindHint:SetText("|cFF00FF00" .. (L["CURRENT_KEYBIND"] or "Current Keybind") .. ": " .. currentKey .. "|r")
    else
        keybindHint:SetText("|cFFFFD100" .. (L["MARK_FOCUS_KEYBIND_HINT"]
            or "Bind via ESC → Key Bindings → LetoQOL") .. "|r")
    end
    keybindHint:SetWidth(480)
    keybindHint:SetWordWrap(true)
    keybindHint:SetJustifyH("LEFT")
end
