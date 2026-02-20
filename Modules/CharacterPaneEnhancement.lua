local addonName, addon = ...
local L     = addon.L or {}
local Utils = addon.Utils

---------------------------------------------------------------------------
-- Module registration
---------------------------------------------------------------------------
local module = {}
module.displayName = L["CHARACTER_PANE_ENHANCEMENT"] or "Character Pane Enhancement"
module.dbKey       = "charPaneEnhancement"
addon:RegisterModule("CharacterPaneEnhancement", module)

---------------------------------------------------------------------------
-- Equipment-slot metadata
--   side = INNER direction (where info text is placed toward the model)
--   enchantable = whether we should warn about a missing enchant
---------------------------------------------------------------------------
local SLOT_DATA = {
    { id = 1,  name = "HeadSlot",          side = "LEFT",   enchantable = false },
    { id = 2,  name = "NeckSlot",          side = "LEFT",   enchantable = false },
    { id = 3,  name = "ShoulderSlot",      side = "LEFT",   enchantable = false },
    { id = 15, name = "BackSlot",          side = "LEFT",   enchantable = true  },
    { id = 5,  name = "ChestSlot",         side = "LEFT",   enchantable = true  },
    { id = 9,  name = "WristSlot",         side = "LEFT",   enchantable = true  },
    { id = 10, name = "HandsSlot",         side = "RIGHT",  enchantable = false },
    { id = 6,  name = "WaistSlot",         side = "RIGHT",  enchantable = false },
    { id = 7,  name = "LegsSlot",          side = "RIGHT",  enchantable = true  },
    { id = 8,  name = "FeetSlot",          side = "RIGHT",  enchantable = true  },
    { id = 11, name = "Finger0Slot",       side = "RIGHT",  enchantable = true  },
    { id = 12, name = "Finger1Slot",       side = "RIGHT",  enchantable = true  },
    { id = 13, name = "Trinket0Slot",      side = "RIGHT",  enchantable = false },
    { id = 14, name = "Trinket1Slot",      side = "RIGHT",  enchantable = false },
    { id = 16, name = "MainHandSlot",      side = "BOTTOM", enchantable = true  },
    { id = 17, name = "SecondaryHandSlot", side = "BOTTOM", enchantable = true  },
}

---------------------------------------------------------------------------
-- Hidden scanning tooltip (fallback for enchant detection)
---------------------------------------------------------------------------
local scanTip = CreateFrame("GameTooltip", "LetoQOLScanTip", nil, "GameTooltipTemplate")
scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")

---------------------------------------------------------------------------
-- Overlay storage  { [slotID] = { ilvlText, infoText, slotData } }
---------------------------------------------------------------------------
local slotOverlays = {}

---------------------------------------------------------------------------
-- DATA HELPERS
---------------------------------------------------------------------------

--- Item level for an equipment slot
local function GetSlotItemLevel(slotID)
    if C_Item and C_Item.GetCurrentItemLevel and ItemLocation then
        local loc = ItemLocation:CreateFromEquipmentSlot(slotID)
        if C_Item.DoesItemExist(loc) then
            return C_Item.GetCurrentItemLevel(loc)
        end
    end
    local link = GetInventoryItemLink("player", slotID)
    if link and GetDetailedItemLevelInfo then
        return GetDetailedItemLevelInfo(link)
    end
    return nil
end

--- Item quality (0-5) for an equipment slot
local function GetSlotItemQuality(slotID)
    if C_Item and C_Item.GetItemQuality and ItemLocation then
        local loc = ItemLocation:CreateFromEquipmentSlot(slotID)
        if C_Item.DoesItemExist(loc) then
            return C_Item.GetItemQuality(loc)
        end
    end
    local link = GetInventoryItemLink("player", slotID)
    if link then
        local _, _, quality = GetItemInfo(link)
        return quality
    end
    return nil
end

--- Durability percentage for an equipment slot (nil if item has no durability)
local function GetSlotDurability(slotID)
    local current, maximum = GetInventoryItemDurability(slotID)
    if current and maximum and maximum > 0 then
        return current / maximum * 100
    end
    return nil
end

--- Overall durability percentage across all equipped items
local function GetOverallDurability()
    local totalCur, totalMax = 0, 0
    for slot = 1, 18 do
        local cur, mx = GetInventoryItemDurability(slot)
        if cur and mx then
            totalCur = totalCur + cur
            totalMax = totalMax + mx
        end
    end
    if totalMax > 0 then
        return totalCur / totalMax * 100
    end
    return nil
end

--- Does the item link contain a non-zero enchant ID?
local function HasEnchant(itemLink)
    if not itemLink then return false end
    local itemString = itemLink:match("item:([%d:%-]+)")
    if not itemString then return false end
    local fields = { strsplit(":", itemString) }
    local enchantID = tonumber(fields[2])
    return enchantID ~= nil and enchantID > 0
end

---------------------------------------------------------------------------
-- ENCHANT DETECTION  (robust, multi-method)
---------------------------------------------------------------------------

--- Dynamically discover the C_TooltipInfo line type for enchantments
local ENCHANT_LINE_TYPE
do
    if Enum and Enum.TooltipDataLineType then
        -- Try direct access first (known name)
        ENCHANT_LINE_TYPE = rawget(Enum.TooltipDataLineType, "ItemEnchantment")
                         or rawget(Enum.TooltipDataLineType, "Enchant")
        -- Dynamic search as fallback
        if not ENCHANT_LINE_TYPE then
            for k, v in pairs(Enum.TooltipDataLineType) do
                if type(k) == "string" and k:lower():find("enchant") then
                    ENCHANT_LINE_TYPE = v
                    break
                end
            end
        end
    end
end

--- Multi-locale prefix patterns (used to strip the label prefix)
local ENCHANT_PREFIXES = {
    "^Enchanted: ",    -- enUS / enGB
    "^Verzaubert: ",   -- deDE
    "^Enchanté : ",    -- frFR
    "^Encantado: ",    -- esES / esMX / ptBR
    "^Наложено: ",     -- ruRU
    "^附魔：",          -- zhCN / zhTW
    "^마법부여: ",       -- koKR
}

--- Strip the locale-specific "Enchanted: " prefix from a text string
local function StripEnchantPrefix(text)
    if not text then return text end
    for _, prefix in ipairs(ENCHANT_PREFIXES) do
        local stripped = text:gsub(prefix, "")
        if stripped ~= text then return stripped end
    end
    return text
end

--- Remove ALL WoW escape markup so we get pure readable text
---   |A:...|a  = Atlas texture    |T...|t  = inline texture
---   |cXXXXXXXX / |r             = colour codes
---   |H...|h...|h                = hyperlinks (keep display text)
local function StripWoWMarkup(text)
    if not text then return text end
    text = text:gsub("|A.-|a", "")                     -- atlas icons
    text = text:gsub("|T.-|t", "")                     -- inline textures
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")       -- colour start
    text = text:gsub("|r", "")                         -- colour reset
    text = text:gsub("|H.-|h(.-)|h", "%1")            -- hyperlinks
    text = text:gsub("|K.-|k", "")                     -- battle-pet links
    text = text:gsub("|n", " ")                        -- newlines
    text = text:gsub("  +", " ")                       -- collapse spaces
    text = text:match("^%s*(.-)%s*$") or text          -- trim
    return text
end

--- Return the enchant **name** for a given slot, or nil if not enchanted.
--- Priority: C_TooltipInfo line-type → C_TooltipInfo prefix match →
---           scanning tooltip prefix → scanning tooltip green text → fallback
local function GetSlotEnchantText(slotID)
    local link = GetInventoryItemLink("player", slotID)
    if not link or not HasEnchant(link) then return nil end

    -----------------------------------------------------------------
    -- Method 1 – C_TooltipInfo (Dragonflight / TWW / 12.x)
    -----------------------------------------------------------------
    if C_TooltipInfo and C_TooltipInfo.GetInventoryItem then
        local ok, data = pcall(C_TooltipInfo.GetInventoryItem, "player", slotID)
        if ok and data and data.lines then
            -- Surface args so leftText is available
            if TooltipUtil and TooltipUtil.SurfaceArgs then
                pcall(TooltipUtil.SurfaceArgs, data)
                for _, line in ipairs(data.lines) do
                    pcall(TooltipUtil.SurfaceArgs, line)
                end
            end

            -- 1a) Find line by its TYPE enum (most reliable)
            if ENCHANT_LINE_TYPE then
                for _, line in ipairs(data.lines) do
                    if line.type == ENCHANT_LINE_TYPE and line.leftText then
                        return StripWoWMarkup(StripEnchantPrefix(line.leftText))
                    end
                end
            end

            -- 1b) Find line by prefix pattern
            for _, line in ipairs(data.lines) do
                if line.leftText then
                    local stripped = StripEnchantPrefix(line.leftText)
                    if stripped ~= line.leftText then
                        return StripWoWMarkup(stripped)
                    end
                end
            end
        end
    end

    -----------------------------------------------------------------
    -- Method 2 – Classic scanning tooltip
    -----------------------------------------------------------------
    scanTip:ClearLines()
    scanTip:SetInventoryItem("player", slotID)

    -- 2a) look for the "Enchanted:" prefix line
    for i = 1, scanTip:NumLines() do
        local textLine = _G["LetoQOLScanTipTextLeft" .. i]
        if textLine then
            local text = textLine:GetText()
            if text then
                local stripped = StripEnchantPrefix(text)
                if stripped ~= text then
                    return StripWoWMarkup(stripped)
                end
            end
        end
    end

    -- 2b) look for the first GREEN text line (enchant effect colour)
    for i = 1, scanTip:NumLines() do
        local textLine = _G["LetoQOLScanTipTextLeft" .. i]
        if textLine then
            local text = textLine:GetText()
            if text and text ~= "" then
                local r, g, b = textLine:GetTextColor()
                if g > 0.9 and r < 0.15 and b < 0.15 then
                    return StripWoWMarkup(text)
                end
            end
        end
    end

    return "Enchanted"   -- absolute last-resort fallback
end

---------------------------------------------------------------------------
-- GEM DETECTION
---------------------------------------------------------------------------

--- Return an array of { name, link, icon } for filled gem sockets
local function GetSlotGems(slotID)
    local link = GetInventoryItemLink("player", slotID)
    if not link then return {} end

    local gems = {}
    for i = 1, 4 do
        local gemName, gemLink = GetItemGem(link, i)
        if gemName and gemLink then
            local icon
            local gemItemID = gemLink:match("item:(%d+)")
            if gemItemID then
                gemItemID = tonumber(gemItemID)
                if C_Item and C_Item.GetItemIconByID then
                    icon = C_Item.GetItemIconByID(gemItemID)
                end
                if not icon and GetItemIcon then
                    icon = GetItemIcon(gemItemID)
                end
            end
            table.insert(gems, {
                name = gemName,
                link = gemLink,
                icon = icon or 136243,
            })
        end
    end
    return gems
end

---------------------------------------------------------------------------
-- OVERLAY UPDATE (per-slot)
--
-- LEFT / RIGHT column layout:
--   ilvlText  =  below the icon, outside       "157 💎💎" or "💎💎 157"
--   infoText  =  inner side, vertically centred "Enchant Name"
--
-- BOTTOM (weapon) layout:
--   ilvlText  =  above the icon                 "163 💎"
--   infoText  =  to the left (MH) / right (OH)  "Enchant Name"
---------------------------------------------------------------------------

--- Build the iLvl colour string
local function IlvlColorString(slotID, db)
    local ilvl = GetSlotItemLevel(slotID)
    if not ilvl then return nil end
    local r, g, b
    if db.ilvlColorMode == "quality" then
        local quality = GetSlotItemQuality(slotID)
        r, g, b = Utils.GetQualityColor(quality)
    else
        local c = db.ilvlCustomColor
        r, g, b = c.r, c.g, c.b
    end
    local hex = string.format("|cFF%02X%02X%02X", r * 255, g * 255, b * 255)
    return hex .. tostring(ilvl) .. "|r"
end

--- Build a table of gem inline-icon strings
local function GemIconStrings(slotID, db)
    local icons = {}
    if not db.showGems then return icons end
    local gems = GetSlotGems(slotID)
    for _, gem in ipairs(gems) do
        if gem.icon then
            table.insert(icons, Utils.InlineIcon(gem.icon, 12))
        end
    end
    return icons
end

local function UpdateSlotOverlay(overlay)
    local db = LetoQOLDB and LetoQOLDB.charPaneEnhancement
    if not db then return end

    local slotData = overlay.slotData
    local slotID   = slotData.id
    local link     = GetInventoryItemLink("player", slotID)

    -- Nothing equipped – hide everything ----------------------------------
    if not link then
        overlay.ilvlText:Hide()
        overlay.infoText:Hide()
        return
    end

    -- 1) ITEM LEVEL + GEMS -----------------------------------------------
    local parts    = {}
    local hasParts = false

    local ilvlStr  = db.showItemLevel and IlvlColorString(slotID, db) or nil
    local gemStrs  = GemIconStrings(slotID, db)

    if slotData.side == "RIGHT" then
        -- Gems first (inner / left), then iLvl
        for _, g in ipairs(gemStrs) do table.insert(parts, g); hasParts = true end
        if ilvlStr then table.insert(parts, ilvlStr); hasParts = true end
    else
        -- iLvl first, then gems (inner / right for LEFT, or just after for BOTTOM)
        if ilvlStr then table.insert(parts, ilvlStr); hasParts = true end
        for _, g in ipairs(gemStrs) do table.insert(parts, g); hasParts = true end
    end

    if hasParts then
        overlay.ilvlText:SetText(table.concat(parts, " "))
        overlay.ilvlText:Show()
    else
        overlay.ilvlText:Hide()
    end

    -- 2) ENCHANT NAME  ---------------------------------------------------
    if db.showEnchants then
        local enchantText = GetSlotEnchantText(slotID)
        if enchantText then
            overlay.infoText:SetText("|cFF00FF00" .. Utils.Abbreviate(enchantText, 24) .. "|r")
            overlay.infoText:Show()
        elseif slotData.enchantable and db.showMissingEnchants then
            overlay.infoText:SetText("|cFFFF4444" .. (L["NOT_ENCHANTED"] or "Not Enchanted") .. "|r")
            overlay.infoText:Show()
        else
            overlay.infoText:Hide()
        end
    else
        overlay.infoText:Hide()
    end

    -- 3) DURABILITY  ------------------------------------------------------
    if db.showDurability and overlay.durabilityText then
        local durPct = GetSlotDurability(slotID)
        if durPct then
            local r, g, b = 0.6, 0.6, 0.6  -- grey for full
            if durPct < 25 then
                r, g, b = 1, 0.2, 0.2       -- red
            elseif durPct < 50 then
                r, g, b = 1, 0.5, 0          -- orange
            elseif durPct < 75 then
                r, g, b = 1, 1, 0            -- yellow
            end
            overlay.durabilityText:SetText(string.format("%d%%", durPct))
            overlay.durabilityText:SetTextColor(r, g, b)
            overlay.durabilityText:Show()
        else
            overlay.durabilityText:Hide()
        end
    elseif overlay.durabilityText then
        overlay.durabilityText:Hide()
    end
end

---------------------------------------------------------------------------
-- MODULE LIFECYCLE
---------------------------------------------------------------------------

function module:OnInitialize()
    -- nothing required
end

function module:OnEnable()
    local function EnsureAndUpdate()
        self:CreateOverlays()
        self:Update()
    end

    if PaperDollFrame then
        PaperDollFrame:HookScript("OnShow", function()
            C_Timer.After(0.05, EnsureAndUpdate)
        end)
        PaperDollFrame:HookScript("OnHide", function()
            if self.overlayFrame then self.overlayFrame:Hide() end
        end)
    end

    -- Hook WoW's built-in Item Level display to show decimal ---------------
    if PaperDollFrame_SetItemLevel then
        hooksecurefunc("PaperDollFrame_SetItemLevel", function(statFrame, unit)
            local db = LetoQOLDB and LetoQOLDB.charPaneEnhancement
            if not db or not db.enabled or not db.showAvgItemLevel then return end
            if unit ~= "player" then return end
            if not statFrame or not statFrame.Value then return end
            local _, avgEquipped = GetAverageItemLevel()
            if avgEquipped and avgEquipped > 0 then
                statFrame.Value:SetText(string.format("%.2f", avgEquipped))
            end
        end)
    end

    -- React to gear changes -----------------------------------------------
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    ef:RegisterEvent("UNIT_INVENTORY_CHANGED")
    ef:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    ef:SetScript("OnEvent", function(_, event, arg1)
        if event == "UNIT_INVENTORY_CHANGED" and arg1 ~= "player" then return end
        if CharacterFrame and CharacterFrame:IsShown() then
            C_Timer.After(0.05, function() self:Update() end)
        end
    end)
    self.eventFrame = ef
end

---------------------------------------------------------------------------
-- OVERLAY CREATION  (single frame at HIGH strata, called once)
--
-- All FontStrings live on one overlay frame parented to PaperDollFrame.
--
-- LEFT column:
--   ilvlText  – below icon, INNER side (right)   "157 💎💎"
--   infoText  – inner side, vertically centred    "Enchant Name"
--
-- RIGHT column:
--   ilvlText  – below icon, INNER side (left)    "💎💎 157"
--   infoText  – inner side, vertically centred    "Enchant Name"
--
-- BOTTOM (weapons):
--   ilvlText  – above the icon                    "163 💎"
--   infoText  – bottom-left of MH / bottom-right of OH
---------------------------------------------------------------------------

function module:CreateOverlays()
    if self.overlaysCreated then return end

    local parent = PaperDollFrame or CharacterFrame
    if not parent then return end

    -- One overlay frame for ALL slot decorations
    local frame = CreateFrame("Frame", "LetoQOLCharOverlay", parent)
    frame:SetAllPoints(parent)
    frame:SetFrameStrata("HIGH")
    self.overlayFrame = frame

    for _, slotData in ipairs(SLOT_DATA) do
        local slotButton = _G["Character" .. slotData.name]
        if slotButton then
            local overlay = { slotData = slotData }

            ---------------------------------------------------------------
            -- iLvl + Gems
            ---------------------------------------------------------------
            local ilvlText = frame:CreateFontString(nil, "OVERLAY")
            ilvlText:SetFont(STANDARD_TEXT_FONT, 11, "OUTLINE")

            if slotData.side == "LEFT" then
                -- Flush with bottom edge of icon, extends inward (right)
                ilvlText:SetPoint("BOTTOMLEFT", slotButton, "BOTTOMRIGHT", 2, 0)
                ilvlText:SetJustifyH("LEFT")
            elseif slotData.side == "RIGHT" then
                -- Flush with bottom edge of icon, extends inward (left)
                ilvlText:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMLEFT", -2, 0)
                ilvlText:SetJustifyH("RIGHT")
            else -- BOTTOM (weapons) → above the icon
                ilvlText:SetPoint("BOTTOM", slotButton, "TOP", 0, 1)
                ilvlText:SetJustifyH("CENTER")
            end
            ilvlText:Hide()
            overlay.ilvlText = ilvlText

            ---------------------------------------------------------------
            -- Enchant name
            ---------------------------------------------------------------
            local infoText = frame:CreateFontString(nil, "OVERLAY")
            infoText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
            infoText:SetWidth(155)
            infoText:SetWordWrap(false)

            if slotData.side == "LEFT" then
                -- Inner side (right of the slot)
                infoText:SetPoint("LEFT", slotButton, "RIGHT", 2, 0)
                infoText:SetJustifyH("LEFT")
            elseif slotData.side == "RIGHT" then
                -- Inner side (left of the slot)
                infoText:SetPoint("RIGHT", slotButton, "LEFT", -2, 0)
                infoText:SetJustifyH("RIGHT")
            else -- BOTTOM (weapons)
                if slotData.id == 16 then
                    -- MainHand → enchant LEFT, flush with bottom edge
                    infoText:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMLEFT", -2, 0)
                    infoText:SetJustifyH("RIGHT")
                else
                    -- SecondaryHand → enchant RIGHT, flush with bottom edge
                    infoText:SetPoint("BOTTOMLEFT", slotButton, "BOTTOMRIGHT", 2, 0)
                    infoText:SetJustifyH("LEFT")
                end
            end
            infoText:Hide()
            overlay.infoText = infoText

            ---------------------------------------------------------------
            -- Durability % (overlaid on the icon, bottom-centre)
            ---------------------------------------------------------------
            local durText = frame:CreateFontString(nil, "OVERLAY")
            durText:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
            durText:SetPoint("BOTTOM", slotButton, "BOTTOM", 0, 2)
            durText:SetJustifyH("CENTER")
            durText:Hide()
            overlay.durabilityText = durText

            slotOverlays[slotData.id] = overlay
        end
    end

    -------------------------------------------------------------------
    -- Total Durability display (top of character pane)
    -------------------------------------------------------------------
    local totalDurText = frame:CreateFontString(nil, "OVERLAY")
    totalDurText:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
    totalDurText:SetPoint("TOPLEFT", parent, "TOPLEFT", 72, -4)
    totalDurText:SetJustifyH("LEFT")
    totalDurText:Hide()
    self.totalDurabilityText = totalDurText

    self.overlaysCreated = true
end

--- Refresh every overlay
function module:Update()
    if not self.overlaysCreated then return end

    -- Show / hide overlay frame with the paper doll
    if self.overlayFrame then
        self.overlayFrame:SetShown(PaperDollFrame and PaperDollFrame:IsVisible())
    end

    local db = LetoQOLDB and LetoQOLDB.charPaneEnhancement
    if not db or not db.enabled then
        for _, ov in pairs(slotOverlays) do
            ov.ilvlText:Hide()
            ov.infoText:Hide()
            if ov.durabilityText then ov.durabilityText:Hide() end
        end
        if self.totalDurabilityText then self.totalDurabilityText:Hide() end
        return
    end

    for _, ov in pairs(slotOverlays) do
        UpdateSlotOverlay(ov)
    end

    -- Total durability ------------------------------------------------------
    if db.showTotalDurability and self.totalDurabilityText then
        local pct = GetOverallDurability()
        if pct then
            local r, g, b = 0.6, 0.6, 0.6
            if pct < 25 then
                r, g, b = 1, 0.2, 0.2
            elseif pct < 50 then
                r, g, b = 1, 0.5, 0
            elseif pct < 75 then
                r, g, b = 1, 1, 0
            end
            self.totalDurabilityText:SetText(
                string.format("|cFF%02X%02X%02X%d%%|r Durability", r*255, g*255, b*255, pct)
            )
            self.totalDurabilityText:Show()
        else
            self.totalDurabilityText:Hide()
        end
    elseif self.totalDurabilityText then
        self.totalDurabilityText:Hide()
    end
end

---------------------------------------------------------------------------
-- SETTINGS PANEL (created inside the Config window's right panel)
---------------------------------------------------------------------------

function module:CreateSettingsPanel(parent)
    local db = LetoQOLDB.charPaneEnhancement
    local UI = addon.UI
    local y  = 0

    -- Title
    UI.CreateSectionHeader(parent, 0, y, L["CHARACTER_PANE_ENHANCEMENT"] or "Character Pane Enhancement")
    y = y - 30
    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Enabled
    UI.CreateCheckbox(parent, 0, y, L["ENABLED"] or "Enabled", db.enabled, function(v)
        db.enabled = v;  self:Update()
    end)
    y = y - 34

    -- Show Item Level
    UI.CreateCheckbox(parent, 0, y, L["SHOW_ITEM_LEVEL"] or "Show Item Level", db.showItemLevel, function(v)
        db.showItemLevel = v;  self:Update()
    end)
    y = y - 30

    -- Show Enchants
    UI.CreateCheckbox(parent, 0, y, L["SHOW_ENCHANTS"] or "Show Enchants", db.showEnchants, function(v)
        db.showEnchants = v;  self:Update()
    end)
    y = y - 30

    -- Show Gems
    UI.CreateCheckbox(parent, 0, y, L["SHOW_GEMS"] or "Show Gems", db.showGems, function(v)
        db.showGems = v;  self:Update()
    end)
    y = y - 30

    -- Highlight Missing Enchants
    UI.CreateCheckbox(parent, 0, y, L["SHOW_MISSING_ENCHANTS"] or "Highlight Missing Enchants", db.showMissingEnchants, function(v)
        db.showMissingEnchants = v;  self:Update()
    end)
    y = y - 30

    -- Show Average Item Level (decimal)
    UI.CreateCheckbox(parent, 0, y, L["SHOW_AVG_ITEM_LEVEL"] or "Show Average Item Level (decimal)", db.showAvgItemLevel, function(v)
        db.showAvgItemLevel = v;  self:Update()
    end)
    y = y - 30

    -- Show Durability % (per item)
    UI.CreateCheckbox(parent, 0, y, L["SHOW_DURABILITY"] or "Show Durability % (per item)", db.showDurability, function(v)
        db.showDurability = v;  self:Update()
    end)
    y = y - 30

    -- Show Total Durability %
    UI.CreateCheckbox(parent, 0, y, L["SHOW_TOTAL_DURABILITY"] or "Show Total Durability %", db.showTotalDurability, function(v)
        db.showTotalDurability = v;  self:Update()
    end)
    y = y - 44

    -- Colour section -------------------------------------------------------
    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    UI.CreateSectionHeader(parent, 0, y, L["ILVL_COLOR"] or "Item Level Color")
    y = y - 30

    local colorSwatch = UI.CreateColorSwatch(
        parent, 230, y - 24, "",
        db.ilvlCustomColor.r, db.ilvlCustomColor.g, db.ilvlCustomColor.b,
        function(r, g, b)
            db.ilvlCustomColor.r = r
            db.ilvlCustomColor.g = g
            db.ilvlCustomColor.b = b
            self:Update()
        end
    )

    UI.CreateRadioGroup(parent, 0, y, {
        { label = L["ILVL_COLOR_QUALITY"] or "Item Quality Color", value = "quality" },
        { label = L["ILVL_COLOR_CUSTOM"]  or "Custom Color",       value = "custom"  },
    }, db.ilvlColorMode, function(value)
        db.ilvlColorMode = value
        colorSwatch:SetEnabled(value == "custom")
        self:Update()
    end)

    colorSwatch:SetEnabled(db.ilvlColorMode == "custom")
end
