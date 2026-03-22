local _, addon = ...
local L = addon.L or {}

---------------------------------------------------------------------------
-- Local state
---------------------------------------------------------------------------
local configFrame      -- the main options window
local moduleButtons  = {}
local contentPanels  = {}
local selectedModule = nil

---------------------------------------------------------------------------
--  UI HELPERS  (exposed via addon.UI for modules)
---------------------------------------------------------------------------

--- Checkbox -----------------------------------------------------------------
local function CreateCheckbox(parent, x, y, label, checked, onChange)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", x, y)

    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")

    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 1)
    text:SetText(label)
    cb.label = text

    cb:SetChecked(checked)
    cb:SetScript("OnClick", function(self)
        local v = self:GetChecked()
        PlaySound(v and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON
                     or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if onChange then onChange(v) end
    end)
    return cb
end

--- Section header -----------------------------------------------------------
local function CreateSectionHeader(parent, x, y, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText("|cFFFFD100" .. text .. "|r")
    return fs
end

--- Horizontal separator -----------------------------------------------------
local function CreateSeparator(parent, x, y, width)
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", x, y)
    if width then
        sep:SetWidth(width)
    else
        sep:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    end
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.8)
    return sep
end

--- Colour swatch with label -------------------------------------------------
local function CreateColorSwatch(parent, x, y, label, r, g, b, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(220, 26)
    container:SetPoint("TOPLEFT", x, y)

    local swatch = CreateFrame("Button", nil, container)
    swatch:SetSize(22, 22)
    swatch:SetPoint("LEFT", 0, 0)

    local border = swatch:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0.5, 0.5, 0.5, 1)

    local swatchBg = swatch:CreateTexture(nil, "ARTWORK")
    swatchBg:SetAllPoints()
    swatchBg:SetColorTexture(r, g, b, 1)
    swatch.bg = swatchBg

    if label and label ~= "" then
        local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", swatch, "RIGHT", 6, 0)
        lbl:SetText(label)
        container.label = lbl
    end

    swatch:SetScript("OnClick", function()
        local info = {
            r = r, g = g, b = b,
            hasOpacity = false,
            swatchFunc = function()
                local nr, ng, nb = ColorPickerFrame:GetColorRGB()
                r, g, b = nr, ng, nb
                swatchBg:SetColorTexture(nr, ng, nb, 1)
                if onChange then onChange(nr, ng, nb) end
            end,
            cancelFunc = function(prev)
                r, g, b = prev.r, prev.g, prev.b
                swatchBg:SetColorTexture(prev.r, prev.g, prev.b, 1)
                if onChange then onChange(prev.r, prev.g, prev.b) end
            end,
        }
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            ColorPickerFrame.previousValues = { r = info.r, g = info.g, b = info.b }
            ColorPickerFrame.func          = info.swatchFunc
            ColorPickerFrame.cancelFunc    = info.cancelFunc
            ColorPickerFrame:SetColorRGB(info.r, info.g, info.b)
            ColorPickerFrame:Show()
        end
    end)

    function container:SetSwatchColor(nr, ng, nb)
        r, g, b = nr, ng, nb
        swatchBg:SetColorTexture(nr, ng, nb, 1)
    end

    function container:SetEnabled(enabled)
        if enabled then
            swatch:Enable()
            swatch:SetAlpha(1)
            if container.label then container.label:SetTextColor(1, 1, 1) end
        else
            swatch:Disable()
            swatch:SetAlpha(0.4)
            if container.label then container.label:SetTextColor(0.5, 0.5, 0.5) end
        end
    end

    return container
end

--- Radio-button group -------------------------------------------------------
local function CreateRadioGroup(parent, x, y, options, selected, onChange)
    local buttons = {}
    local group = CreateFrame("Frame", nil, parent)
    group:SetPoint("TOPLEFT", x, y)
    group:SetSize(300, #options * 28)

    for i, option in ipairs(options) do
        local btn = CreateFrame("CheckButton", nil, group)
        btn:SetSize(20, 20)
        btn:SetPoint("TOPLEFT", 0, -((i - 1) * 28))

        btn:SetNormalTexture("Interface\\Buttons\\UI-RadioButton")
        btn:SetHighlightTexture("Interface\\Buttons\\UI-RadioButton")
        btn:SetCheckedTexture("Interface\\Buttons\\UI-RadioButton")

        local normal    = btn:GetNormalTexture()
        local checked_t = btn:GetCheckedTexture()
        local highlight = btn:GetHighlightTexture()
        normal:SetTexCoord(0, 0.25, 0, 1)
        checked_t:SetTexCoord(0.25, 0.5, 0, 1)
        highlight:SetTexCoord(0.5, 0.75, 0, 1)

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", btn, "RIGHT", 4, 0)
        lbl:SetText(option.label)
        btn.label = lbl
        btn.value = option.value

        btn:SetChecked(option.value == selected)
        btn:SetScript("OnClick", function(self)
            for _, b in ipairs(buttons) do
                b:SetChecked(b.value == self.value)
            end
            if onChange then onChange(self.value) end
        end)

        buttons[i] = btn
    end

    function group:SetSelected(value)
        for _, b in ipairs(buttons) do
            b:SetChecked(b.value == value)
        end
    end

    return group
end

--- Slider with label + value readout ----------------------------------------
local function CreateSlider(parent, x, y, label, minVal, maxVal, step, currentValue, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(280, 42)
    container:SetPoint("TOPLEFT", x, y)

    local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 0, 0)
    lbl:SetText(label)

    local valText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valText:SetPoint("TOPRIGHT", 0, 0)
    valText:SetText(tostring(currentValue))

    local slider = CreateFrame("Slider", nil, container)
    slider:SetPoint("TOPLEFT", 2, -16)
    slider:SetPoint("TOPRIGHT", -2, -16)
    slider:SetHeight(14)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(currentValue)

    -- track background
    local bg = slider:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 0, -5)
    bg:SetPoint("BOTTOMRIGHT", 0, 5)
    bg:SetColorTexture(0.2, 0.2, 0.2, 0.8)

    -- thumb
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(12, 20)
    thumb:SetColorTexture(0.6, 0.6, 0.6, 1)
    slider:SetThumbTexture(thumb)

    -- min / max labels
    local minLbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minLbl:SetPoint("TOPLEFT", slider, "BOTTOMLEFT", 0, -2)
    minLbl:SetText(tostring(minVal))
    minLbl:SetTextColor(0.6, 0.6, 0.6)

    local maxLbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxLbl:SetPoint("TOPRIGHT", slider, "BOTTOMRIGHT", 0, -2)
    maxLbl:SetText(tostring(maxVal))
    maxLbl:SetTextColor(0.6, 0.6, 0.6)

    slider:SetScript("OnValueChanged", function(_, val)
        val = math.floor(val / step + 0.5) * step
        valText:SetText(tostring(val))
        if onChange then onChange(val) end
    end)

    function container:SetValue(v)
        slider:SetValue(v)
    end

    return container
end

--- Sound picker (left/right arrows + play preview) -------------------------
local function CreateSoundPicker(parent, x, y, label, sounds, currentValue, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(480, 26)
    container:SetPoint("TOPLEFT", x, y)

    -- Label
    local lbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetText(label)
    lbl:SetWidth(90)
    lbl:SetJustifyH("LEFT")

    -- Find current index
    local currentIdx = 1
    for i, s in ipairs(sounds) do
        if s.value == currentValue then currentIdx = i; break end
    end

    -- Left arrow
    local leftBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    leftBtn:SetSize(22, 22)
    leftBtn:SetPoint("LEFT", lbl, "RIGHT", 4, 0)
    leftBtn:SetText("<")

    -- Sound name display
    local nameText = container:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("LEFT", leftBtn, "RIGHT", 4, 0)
    nameText:SetWidth(120)
    nameText:SetJustifyH("CENTER")
    nameText:SetText(sounds[currentIdx].label)

    -- Right arrow
    local rightBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    rightBtn:SetSize(22, 22)
    rightBtn:SetPoint("LEFT", nameText, "RIGHT", 4, 0)
    rightBtn:SetText(">")

    -- Play preview button
    local playBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    playBtn:SetSize(22, 22)
    playBtn:SetPoint("LEFT", rightBtn, "RIGHT", 6, 0)
    playBtn:SetNormalFontObject("GameFontNormal")
    playBtn:SetText("\226\150\182")  -- ▶

    local function UpdateDisplay()
        nameText:SetText(sounds[currentIdx].label)
    end

    leftBtn:SetScript("OnClick", function()
        currentIdx = currentIdx - 1
        if currentIdx < 1 then currentIdx = #sounds end
        UpdateDisplay()
        if onChange then onChange(sounds[currentIdx].value) end
    end)

    rightBtn:SetScript("OnClick", function()
        currentIdx = currentIdx + 1
        if currentIdx > #sounds then currentIdx = 1 end
        UpdateDisplay()
        if onChange then onChange(sounds[currentIdx].value) end
    end)

    playBtn:SetScript("OnClick", function()
        local val = sounds[currentIdx].value
        if val and val > 0 then PlaySound(val) end
    end)

    return container
end

---------------------------------------------------------------------------
-- Publish helpers so modules can use them in CreateSettingsPanel()
---------------------------------------------------------------------------
addon.UI = {
    CreateCheckbox      = CreateCheckbox,
    CreateSectionHeader = CreateSectionHeader,
    CreateSeparator     = CreateSeparator,
    CreateColorSwatch   = CreateColorSwatch,
    CreateRadioGroup    = CreateRadioGroup,
    CreateSlider        = CreateSlider,
    CreateSoundPicker   = CreateSoundPicker,
}

---------------------------------------------------------------------------
-- Scrollable module settings (right panel)
---------------------------------------------------------------------------
local function UpdateSettingsScrollHeight(scrollFrame)
    local child = scrollFrame and scrollFrame.scrollChild
    if not child then return end

    local viewH = math.max(scrollFrame:GetHeight() or 1, 1)
    local sw = scrollFrame:GetWidth() or 520
    local w = math.max(sw - 28, 200)
    child:SetWidth(w)

    local scTop = child:GetTop()
    if not scTop then
        child:SetHeight(viewH)
        return
    end

    local maxDown = 0
    local function consider(obj)
        if not obj or not obj.GetBottom then return end
        if obj.IsShown and not obj:IsShown() then return end
        local b = obj:GetBottom()
        if not b then return end
        local down = scTop - b
        if down > maxDown then maxDown = down end
    end
    local function walkSubtree(f)
        if not f then return end
        consider(f)
        local kids = { f:GetChildren() }
        for i = 1, #kids do
            walkSubtree(kids[i])
        end
        local regs = { f:GetRegions() }
        for i = 1, #regs do
            consider(regs[i])
        end
    end

    local tops = { child:GetChildren() }
    for i = 1, #tops do
        walkSubtree(tops[i])
    end
    local topRegs = { child:GetRegions() }
    for i = 1, #topRegs do
        consider(topRegs[i])
    end

    child:SetHeight(math.max(math.ceil(maxDown + 48), viewH))
end

local function DeferUpdateSettingsScroll(scrollFrame)
    if not scrollFrame then return end
    C_Timer.After(0, function()
        if scrollFrame:IsShown() then
            UpdateSettingsScrollHeight(scrollFrame)
        end
    end)
end

---------------------------------------------------------------------------
-- Module selection (left-panel highlight + right-panel swap)
---------------------------------------------------------------------------
local function SelectModule(moduleName)
    selectedModule = moduleName
    for name, btn in pairs(moduleButtons) do
        if name == moduleName then
            btn.bg:SetColorTexture(0.18, 0.38, 0.58, 0.85)
            btn.selected = true
        else
            btn.bg:SetColorTexture(0, 0, 0, 0)
            btn.selected = false
        end
    end
    for name, panel in pairs(contentPanels) do
        panel:SetShown(name == moduleName)
    end
    local sf = contentPanels[moduleName]
    if sf then
        sf:SetVerticalScroll(0)
        DeferUpdateSettingsScroll(sf)
    end
end

---------------------------------------------------------------------------
-- Build the configuration window (called once, on demand)
---------------------------------------------------------------------------
local function CreateConfigFrame()
    if configFrame then return configFrame end

    -- Main frame -----------------------------------------------------------
    local f = CreateFrame("Frame", "LetoQOLConfigFrame", UIParent, "BackdropTemplate")
    f:SetSize(780, 500)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)

    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.06, 0.06, 0.06, 0.97)
    f:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)

    -- Closable with Escape -------------------------------------------------
    table.insert(UISpecialFrames, "LetoQOLConfigFrame")

    -- Title bar ------------------------------------------------------------
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetPoint("TOPLEFT", 4, -4)
    titleBar:SetPoint("TOPRIGHT", -4, -4)
    titleBar:SetHeight(30)
    local titleBg = titleBar:CreateTexture(nil, "BACKGROUND")
    titleBg:SetAllPoints()
    titleBg:SetColorTexture(0.1, 0.1, 0.1, 0.9)

    local title = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("LEFT", 12, 0)
    title:SetText("|cFF00CCFFLetoQOL|r")

    local subtitle = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 8, 0)
    subtitle:SetText("|cFF888888v5.0.1|r")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)

    -- Left panel (module list) ---------------------------------------------
    local left = CreateFrame("Frame", nil, f, "BackdropTemplate")
    left:SetPoint("TOPLEFT", 8, -40)
    left:SetPoint("BOTTOMLEFT", 8, 8)
    left:SetWidth(220)
    left:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    left:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    left:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    -- Right panel (settings area) ------------------------------------------
    local right = CreateFrame("Frame", nil, f, "BackdropTemplate")
    right:SetPoint("TOPLEFT", left, "TOPRIGHT", 6, 0)
    right:SetPoint("BOTTOMRIGHT", -8, 8)
    right:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    right:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    right:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    f.leftPanel  = left
    f.rightPanel = right

    -- Populate module buttons + content panels -----------------------------
    local btnIdx = 0
    local firstName = nil
    for name, mod in pairs(addon.modules) do
        if not firstName then firstName = name end
        btnIdx = btnIdx + 1
        local displayName = mod.displayName or name

        -- Button in the left panel
        local btn = CreateFrame("Button", nil, left)
        btn:SetSize(left:GetWidth() - 16, 30)
        btn:SetPoint("TOPLEFT", 8, -(8 + (btnIdx - 1) * 34))

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0)
        btn.bg = bg

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btnText:SetPoint("LEFT", 10, 0)
        btnText:SetText(displayName)
        btn.text     = btnText
        btn.selected = false

        btn:SetScript("OnEnter", function(self)
            if not self.selected then self.bg:SetColorTexture(0.25, 0.25, 0.25, 0.5) end
        end)
        btn:SetScript("OnLeave", function(self)
            if not self.selected then self.bg:SetColorTexture(0, 0, 0, 0) end
        end)
        btn:SetScript("OnClick", function()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
            SelectModule(name)
        end)

        moduleButtons[name] = btn

        -- Scrollable content (fills inner right panel; avoids overflow on tall modules)
        local scrollFrame = CreateFrame("ScrollFrame", nil, right, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 8, -8)
        scrollFrame:SetPoint("BOTTOMRIGHT", -28, 8)

        local scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollFrame:SetScrollChild(scrollChild)
        scrollFrame.scrollChild = scrollChild
        scrollFrame:Hide()

        scrollFrame:SetScript("OnShow", function(self)
            DeferUpdateSettingsScroll(self)
        end)

        if mod.CreateSettingsPanel then
            mod:CreateSettingsPanel(scrollChild)
        end

        contentPanels[name] = scrollFrame
    end

    f:SetScript("OnSizeChanged", function()
        if selectedModule and contentPanels[selectedModule] then
            DeferUpdateSettingsScroll(contentPanels[selectedModule])
        end
    end)

    -- Select the first module by default
    if firstName then SelectModule(firstName) end

    f:Hide()
    configFrame = f
    return f
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
function addon:IsConfigOpen()
    return configFrame and configFrame:IsShown()
end

function addon:ToggleConfig()
    if not configFrame then CreateConfigFrame() end
    local willShow = not configFrame:IsShown()
    configFrame:SetShown(willShow)
    if willShow and selectedModule and contentPanels[selectedModule] then
        DeferUpdateSettingsScroll(contentPanels[selectedModule])
    end
end

function addon:InitConfig()
    if not configFrame then CreateConfigFrame() end
end

