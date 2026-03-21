local addonName, addon = ...
local L     = addon.L or {}

---------------------------------------------------------------------------
-- Module registration
---------------------------------------------------------------------------
local module = {}
module.displayName = L["CURSOR_RING"] or "Cursor Ring"
module.dbKey       = "cursorRing"
addon:RegisterModule("CursorRing", module)

---------------------------------------------------------------------------
-- Constants
---------------------------------------------------------------------------
local SEGMENT_COUNT = 48
local WHITE_TEX     = "Interface\\BUTTONS\\WHITE8X8"

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
local ringFrame
local mainSegs = {}
local glowSegs = {}

---------------------------------------------------------------------------
-- Geometry: ring = short bars tiled around a circle (no external textures)
---------------------------------------------------------------------------

-- CreateTexture(name, layer) only — on this client the 3rd arg is an XML template name, not subLevel.
local function EnsureSegments(texList, parent, drawLayer, subLevel, count)
    for i = #texList + 1, count do
        local t = parent:CreateTexture(nil, drawLayer)
        t:SetDrawLayer(drawLayer, subLevel)
        t:SetTexture(WHITE_TEX)
        texList[i] = t
    end
    for i = count + 1, #texList do
        texList[i]:Hide()
    end
end

local function LayoutRing(texList, count, radius, thickness)
    if radius < 1 then radius = 1 end
    if thickness < 1 then thickness = 1 end
    local twoPi = math.pi * 2
    for i = 1, count do
        local mid = (i - 0.5) * (twoPi / count)
        local chord = 2 * radius * math.sin(math.pi / count) * 1.08
        local t = texList[i]
        t:SetSize(math.max(chord, 1), thickness)
        t:ClearAllPoints()
        t:SetPoint("CENTER", ringFrame, "CENTER",
            radius * math.cos(mid),
            radius * math.sin(mid))
        t:SetRotation(mid + math.pi / 2)
        t:Show()
    end
end

local function BoundingSize(radius, thickness, glowSpread, glowThickness)
    local ext = radius + thickness * 0.5 + glowSpread + glowThickness * 0.5 + 4
    return math.max(ext * 2, 32)
end

local function RebuildRing()
    local db = LetoQOLDB and LetoQOLDB.cursorRing
    if not db or not ringFrame then return end

    EnsureSegments(mainSegs, ringFrame, "ARTWORK", 1, SEGMENT_COUNT)
    EnsureSegments(glowSegs, ringFrame, "ARTWORK", 0, SEGMENT_COUNT)

    local box = BoundingSize(db.radius, db.thickness, db.glowSpread or 0, db.glowThickness or 0)
    ringFrame:SetSize(box, box)

    LayoutRing(mainSegs, SEGMENT_COUNT, db.radius, db.thickness)

    if db.glowEnabled then
        local gR = db.radius + (db.glowSpread or 0)
        local gT = db.glowThickness or (db.thickness + 2)
        LayoutRing(glowSegs, SEGMENT_COUNT, gR, gT)
        for i = 1, SEGMENT_COUNT do
            glowSegs[i]:Show()
        end
    else
        for i = 1, SEGMENT_COUNT do
            if glowSegs[i] then glowSegs[i]:Hide() end
        end
    end

    module._ApplyColors()
end

function module._ApplyColors()
    local db = LetoQOLDB and LetoQOLDB.cursorRing
    if not db then return end

    local r, g, b = db.color.r, db.color.g, db.color.b
    local a = db.alpha or 1

    for i = 1, SEGMENT_COUNT do
        if mainSegs[i] then
            mainSegs[i]:SetVertexColor(r, g, b, a)
            mainSegs[i]:SetBlendMode("BLEND")
        end
    end

    if db.glowEnabled then
        local ga = (db.glowAlpha or 0.4) * a
        for i = 1, SEGMENT_COUNT do
            if glowSegs[i] then
                glowSegs[i]:SetVertexColor(r, g, b, ga)
                glowSegs[i]:SetBlendMode("ADD")
                glowSegs[i]:Show()
            end
        end
    else
        for i = 1, SEGMENT_COUNT do
            if glowSegs[i] then glowSegs[i]:Hide() end
        end
    end
end

local function CreateRingFrame()
    if ringFrame then return end

    ringFrame = CreateFrame("Frame", "LetoQOLCursorRing", UIParent)
    ringFrame:SetFrameStrata("TOOLTIP")
    ringFrame:SetFrameLevel(5000)
    ringFrame:EnableMouse(false)
    ringFrame:SetAlpha(1)
    ringFrame:SetScript("OnUpdate", function(self)
        local db = LetoQOLDB and LetoQOLDB.cursorRing
        if not db or not db.enabled then
            self:Hide()
            return
        end
        self:Show()
        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        x = x / scale
        y = y / scale
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    end)
    ringFrame:Hide()
end

function module:Refresh()
    local db = LetoQOLDB and LetoQOLDB.cursorRing
    CreateRingFrame()
    if not ringFrame then return end
    if not db or not db.enabled then
        ringFrame:Hide()
        return
    end
    RebuildRing()
    ringFrame:Show()
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function module:OnInitialize()
end

function module:OnEnable()
    CreateRingFrame()
    self:Refresh()
end

---------------------------------------------------------------------------
-- Settings UI
---------------------------------------------------------------------------

function module:CreateSettingsPanel(parent)
    local db = LetoQOLDB.cursorRing
    local UI = addon.UI
    local y = 0

    UI.CreateSectionHeader(parent, 0, y, L["CURSOR_RING"] or "Cursor Ring")
    y = y - 30
    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    UI.CreateCheckbox(parent, 0, y, L["ENABLED"] or "Enabled", db.enabled, function(v)
        db.enabled = v
        module:Refresh()
    end)
    y = y - 40

    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, y)
    desc:SetWidth(480)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(true)
    desc:SetTextColor(0.7, 0.7, 0.7)
    desc:SetText(L["CURSOR_RING_DESC"]
        or "A ring that follows the mouse. Does not intercept clicks (including right-click camera).")
    y = y - 36

    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    UI.CreateColorSwatch(parent, 0, y, L["CURSOR_RING_COLOR"] or "Ring Color",
        db.color.r, db.color.g, db.color.b,
        function(r, g, b)
            db.color.r, db.color.g, db.color.b = r, g, b
            module._ApplyColors()
        end)
    y = y - 40

    UI.CreateSlider(parent, 0, y, L["CURSOR_RING_OPACITY"] or "Opacity", 0.1, 1, 0.05, db.alpha, function(val)
        db.alpha = val
        module._ApplyColors()
    end)
    y = y - 55

    UI.CreateSlider(parent, 0, y, L["CURSOR_RING_RADIUS"] or "Radius", 6, 80, 1, db.radius, function(val)
        db.radius = val
        RebuildRing()
    end)
    y = y - 55

    UI.CreateSlider(parent, 0, y, L["CURSOR_RING_THICKNESS"] or "Thickness", 1, 16, 1, db.thickness, function(val)
        db.thickness = val
        RebuildRing()
    end)
    y = y - 55

    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    UI.CreateSectionHeader(parent, 0, y, L["CURSOR_RING_GLOW"] or "Glow")
    y = y - 26

    UI.CreateCheckbox(parent, 0, y, L["ENABLED"] or "Enabled", db.glowEnabled, function(v)
        db.glowEnabled = v
        RebuildRing()
    end)
    y = y - 34

    UI.CreateSlider(parent, 0, y, L["CURSOR_RING_GLOW_ALPHA"] or "Glow brightness", 0, 1, 0.05, db.glowAlpha, function(val)
        db.glowAlpha = val
        module._ApplyColors()
    end)
    y = y - 55

    UI.CreateSlider(parent, 0, y, L["CURSOR_RING_GLOW_SPREAD"] or "Glow spread", 0, 24, 1, db.glowSpread, function(val)
        db.glowSpread = val
        RebuildRing()
    end)
    y = y - 55

    UI.CreateSlider(parent, 0, y, L["CURSOR_RING_GLOW_THICKNESS"] or "Glow thickness", 1, 24, 1, db.glowThickness, function(val)
        db.glowThickness = val
        RebuildRing()
    end)
end
