local addonName, addon = ...
local L = addon.L or {}

---------------------------------------------------------------------------
-- Module registration
---------------------------------------------------------------------------
local module = {}
module.displayName = L["TELEPORT_COMPENDIUM"] or "Teleport Compendium"
module.dbKey       = "teleportCompendium"
addon:RegisterModule("TeleportCompendium", module)

---------------------------------------------------------------------------
-- Local state
---------------------------------------------------------------------------
local teleportCategories = {}   -- spells: { spellID, name, displayName, icon }
local mapButton                 -- button on the World Map
local compendiumPanel           -- the main panel frame
local scrollFrame, scrollChild
local uiElements = {}           -- all dynamic UI (for cleanup)
local panelDirty = true         -- needs rebuild

---------------------------------------------------------------------------
-- Forward declarations
---------------------------------------------------------------------------
local TogglePanel

---------------------------------------------------------------------------
-- Known home-type spell IDs
---------------------------------------------------------------------------
local HOME_SPELLS = {
    8690,       -- Hearthstone
}

---------------------------------------------------------------------------
-- Display label from spell description (locale-specific phrasing).
-- Falls back to spell name (Hearthstone, unknown wording, etc.)
---------------------------------------------------------------------------
-- Capture until sentence end. Do NOT use %n here — in Lua patterns that is NOT newline; it
-- matches the letter "n", so names like "Operation: Mechagon" / "The Underrot" truncate early.
local TELEPORT_DESC_PATTERNS = {
    "Teleport to the entrance to ([^%.\n]+)",       -- enUS / enGB
    "Teleportiert zum Eingang von ([^%.\n]+)",      -- deDE
}

local function DungeonNameFromSpellDescription(spellID)
    if not spellID or not C_Spell or not C_Spell.GetSpellDescription then
        return nil
    end
    local desc = C_Spell.GetSpellDescription(spellID)
    if not desc or desc == "" then return nil end
    -- Strip color codes and bold asterisks from description text
    local plain = desc
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
        :gsub("%*+", "")
    for _, pattern in ipairs(TELEPORT_DESC_PATTERNS) do
        local dungeon = plain:match(pattern)
        if dungeon then
            return strtrim(dungeon)
        end
    end
    return nil
end

local function ResolveDisplayName(spellID, spellName)
    return DungeonNameFromSpellDescription(spellID) or spellName
end

--- Remove duplicate flyout slots (same spell ID or same display label / name).
local function DedupeSpellList(spells)
    local idSeen, dispSeen = {}, {}
    local out = {}
    for _, s in ipairs(spells) do
        if not idSeen[s.spellID] then
            idSeen[s.spellID] = true
            local d = strtrim(s.displayName or s.name or "")
            local key = string.lower(d)
            if key ~= "" and dispSeen[key] then
                -- second spell id for same dungeon label
            else
                if key ~= "" then dispSeen[key] = true end
                table.insert(out, s)
            end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- SCAN TELEPORTS
---------------------------------------------------------------------------
local function ScanTeleports()
    wipe(teleportCategories)

    -- 1) Home spells -------------------------------------------------------
    local homeSpells = {}
    for _, spellID in ipairs(HOME_SPELLS) do
        local known = IsPlayerSpell and IsPlayerSpell(spellID)
                   or IsSpellKnown  and IsSpellKnown(spellID)
        if known then
            local info = C_Spell.GetSpellInfo(spellID)
            if info then
                table.insert(homeSpells, {
                    spellID     = spellID,
                    name        = info.name,
                    displayName = ResolveDisplayName(spellID, info.name),
                    icon        = info.iconID,
                })
            end
        end
    end

    -- 2) Brute-force scan all flyout IDs for "Hero's Path" -----------------
    local seen = {}
    for flyoutID = 1, 500 do
        local ok, name, desc, numSlots, isKnown = pcall(GetFlyoutInfo, flyoutID)
        if ok and name and isKnown and name:find("Hero's Path") then
            local expansion = name:match("Hero's Path:%s*(.+)") or name
            if not seen[expansion] then
                seen[expansion] = true
                local spells = {}
                for slot = 1, numSlots do
                    local slotOk, spellID, overrideSpellID, isKnownSlot =
                        pcall(GetFlyoutSlotInfo, flyoutID, slot)
                    if slotOk and isKnownSlot and spellID then
                        local useID = (overrideSpellID and overrideSpellID > 0)
                                      and overrideSpellID or spellID
                        local sInfo = C_Spell.GetSpellInfo(useID)
                        if sInfo then
                            table.insert(spells, {
                                spellID     = useID,
                                name        = sInfo.name,
                                displayName = ResolveDisplayName(useID, sInfo.name),
                                icon        = sInfo.iconID,
                            })
                        end
                    end
                end
                spells = DedupeSpellList(spells)
                table.sort(spells, function(a, b)
                    return a.displayName < b.displayName
                end)
                if #spells > 0 then
                    table.insert(teleportCategories, { name = expansion, spells = spells })
                end
            end
        end
    end

    -- 3) Also scan spellbook for non-flyout "Hero's Path" spells -----------
    if C_SpellBook and C_SpellBook.GetNumSpellBookItems then
        local bank     = Enum.SpellBookSpellBank.Player
        local numItems = C_SpellBook.GetNumSpellBookItems(bank) or 0
        for i = 1, numItems do
            local ok2, itemInfo = pcall(C_SpellBook.GetSpellBookItemInfo, i, bank)
            if ok2 and itemInfo and itemInfo.spellID
               and itemInfo.itemType == Enum.SpellBookItemType.Spell then
                local sInfo = C_Spell.GetSpellInfo(itemInfo.spellID)
                if sInfo and sInfo.name and sInfo.name:find("Hero's Path") then
                    local expansion = sInfo.name:match("Hero's Path:%s*(.+)") or sInfo.name
                    if not seen[expansion] then
                        seen[expansion] = true
                        table.insert(teleportCategories, {
                            name   = expansion,
                            spells = { {
                                spellID     = itemInfo.spellID,
                                name        = sInfo.name,
                                displayName = ResolveDisplayName(itemInfo.spellID, sInfo.name),
                                icon        = sInfo.iconID,
                            } },
                        })
                    end
                end
            end
        end
    end

    -- 4) Sort categories alphabetically ------------------------------------
    table.sort(teleportCategories, function(a, b) return a.name < b.name end)

    -- 5) Insert Home at the top --------------------------------------------
    if #homeSpells > 0 then
        table.insert(teleportCategories, 1, { name = "Home", spells = homeSpells })
    end

    panelDirty = true
end

---------------------------------------------------------------------------
-- CREATE MAP BUTTON  (small icon on the World Map border)
---------------------------------------------------------------------------
local function CreateMapButton()
    if mapButton then return end
    if not WorldMapFrame then return end

    mapButton = CreateFrame("Button", "LetoQOLTeleportBtn", WorldMapFrame.BorderFrame,
                            "BackdropTemplate")
    mapButton:SetSize(36, 36)
    mapButton:SetFrameStrata("HIGH")
    mapButton:SetFrameLevel(WorldMapFrame.BorderFrame:GetFrameLevel() + 10)

    -- Anchor on the far right edge, aligned with the other icon buttons
    mapButton:SetPoint("TOPLEFT", WorldMapFrame, "TOPRIGHT", 2, -260)

    -- Dark background so the icon pops
    mapButton:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    mapButton:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    mapButton:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)   -- gold-ish border

    local icon = mapButton:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 4, -4)
    icon:SetPoint("BOTTOMRIGHT", -4, 4)
    icon:SetTexture("Interface\\Icons\\Spell_Arcane_PortalDalaran")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    mapButton.icon = icon

    local hl = mapButton:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -3)
    hl:SetPoint("BOTTOMRIGHT", -3, 3)
    hl:SetColorTexture(1, 1, 1, 0.25)

    mapButton:SetScript("OnClick", function()
        TogglePanel()
    end)

    mapButton:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1, 0.82, 0, 1)  -- bright gold on hover
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["TELEPORT_COMPENDIUM"] or "Teleport Compendium")
        GameTooltip:Show()
    end)
    mapButton:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
        GameTooltip_Hide()
    end)
end

---------------------------------------------------------------------------
-- Scroll child width = viewport minus scrollbar (otherwise text is clipped on the right).
---------------------------------------------------------------------------
local function ApplyTeleportScrollInnerWidth()
    if not scrollFrame or not scrollChild then return end
    local width = scrollFrame:GetWidth()
    if not width or width <= 0 then return end
    local bar = scrollFrame.ScrollBar
    local inner = width - (bar and bar.GetWidth and (bar:GetWidth() + 8) or 28)
    scrollChild:SetWidth(math.max(inner, 80))
end

---------------------------------------------------------------------------
-- CREATE COMPENDIUM PANEL
---------------------------------------------------------------------------
local function CreatePanel()
    if compendiumPanel then return end
    if not WorldMapFrame then return end

    local p = CreateFrame("Frame", "LetoQOLTeleportPanel", WorldMapFrame, "BackdropTemplate")

    -- Occupy the same area as the quest log panel
    if QuestMapFrame then
        p:SetPoint("TOPLEFT",     QuestMapFrame, "TOPLEFT",     0, 0)
        p:SetPoint("BOTTOMRIGHT", QuestMapFrame, "BOTTOMRIGHT",  0, 0)
    else
        p:SetPoint("TOPRIGHT",    WorldMapFrame, "TOPRIGHT",   -4, -68)
        p:SetPoint("BOTTOMRIGHT", WorldMapFrame, "BOTTOMRIGHT", -4,   4)
        p:SetWidth(350)
    end

    p:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    p:SetBackdropColor(0.06, 0.06, 0.06, 0.95)
    p:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    p:SetFrameStrata("HIGH")

    -- Title
    local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFFFFD100" .. (L["TELEPORT_COMPENDIUM"] or "Teleport Compendium") .. "|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() TogglePanel() end)

    -- Scroll frame
    local sf = CreateFrame("ScrollFrame", "LetoQOLTeleportScroll", p, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -38)
    sf:SetPoint("BOTTOMRIGHT", -28, 8)

    local sc = CreateFrame("Frame", nil, sf)
    sc:SetWidth(sf:GetWidth() > 0 and sf:GetWidth() or 400)
    sc:SetHeight(1) -- resized in Populate
    sf:SetScrollChild(sc)

    sf:SetScript("OnSizeChanged", function()
        ApplyTeleportScrollInnerWidth()
    end)

    compendiumPanel = p
    scrollFrame     = sf
    scrollChild     = sc

    ApplyTeleportScrollInnerWidth()

    p:Hide()
end

---------------------------------------------------------------------------
-- POPULATE PANEL  (create category headers + spell buttons)
---------------------------------------------------------------------------
local function PopulatePanel()
    if not scrollChild then return end
    if InCombatLockdown() then return end -- can't create secure buttons in combat

    -- Clean up old elements
    for _, elem in ipairs(uiElements) do
        if elem.Hide then elem:Hide() end
        local b = elem._spellBtn
        if b and b.SetAttribute then
            b:SetAttribute("type", nil)
            b:SetAttribute("spell", nil)
        elseif elem.SetAttribute then
            elem:SetAttribute("type", nil)
            elem:SetAttribute("spell", nil)
        end
    end
    wipe(uiElements)

    ApplyTeleportScrollInnerWidth()

    local y = 0
    -- scrollChild width is set to exclude the scrollbar (see ApplyTeleportScrollInnerWidth).
    local viewportW = scrollChild:GetWidth()
    if viewportW < 60 then viewportW = 280 end
    local btnW = math.max(viewportW - 8, 200)
    local ROW_PAD     = 6
    local MIN_ROW_H   = 36
    local ICON_SIZE   = 28
    local btnIndex    = 0
    local textWidth   = math.max(btnW - ICON_SIZE - ROW_PAD * 3 - 16, 200)

    for _, cat in ipairs(teleportCategories) do
        -- Category header
        local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", 4, y)
        header:SetText(cat.name)
        header:Show()
        table.insert(uiElements, header)
        y = y - 24

        -- Separator
        local sep = scrollChild:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", 4, y)
        sep:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -4, y)
        sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)
        sep:Show()
        table.insert(uiElements, sep)
        y = y - 8

        -- Spell row: label is NOT a child of SecureActionButton (template clips/truncates text).
        for _, spell in ipairs(cat.spells) do
            btnIndex = btnIndex + 1

            local row = CreateFrame("Frame", nil, scrollChild)
            row:SetWidth(btnW)
            row:SetPoint("TOPLEFT", 4, y)

            local btn = CreateFrame("Button", "LetoQOLTP" .. btnIndex, row,
                                    "SecureActionButtonTemplate")
            btn:SetAllPoints(row)
            btn:RegisterForClicks("AnyUp", "AnyDown")
            btn:SetAttribute("type", "spell")
            btn:SetAttribute("spell", spell.spellID)

            local hlTex = btn:CreateTexture(nil, "HIGHLIGHT")
            hlTex:SetAllPoints()
            hlTex:SetColorTexture(1, 1, 1, 0.08)

            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(ICON_SIZE, ICON_SIZE)
            iconTex:SetTexture(spell.icon)
            iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

            -- FontString on row so it paints above the button and is not clipped by secure template.
            local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameText:SetWidth(textWidth)
            nameText:SetJustifyH("LEFT")
            nameText:SetJustifyV("TOP")
            nameText:SetWordWrap(true)
            nameText:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_PAD + ICON_SIZE + ROW_PAD, -ROW_PAD)
            nameText:SetText(spell.displayName)

            local textH = nameText:GetStringHeight()
            local rowH = math.max(MIN_ROW_H, textH + ROW_PAD * 2, ICON_SIZE + ROW_PAD * 2)
            row:SetHeight(rowH)

            local topPad = ROW_PAD + math.max(0, (rowH - math.max(ICON_SIZE, textH)) / 2)
            iconTex:SetPoint("TOPLEFT", btn, "TOPLEFT", ROW_PAD, -topPad)
            nameText:ClearAllPoints()
            nameText:SetPoint("TOPLEFT", row, "TOPLEFT", ROW_PAD + ICON_SIZE + ROW_PAD, -topPad)

            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(spell.spellID)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", GameTooltip_Hide)

            row._spellBtn = btn
            table.insert(uiElements, row)
            y = y - rowH - 4
        end

        y = y - 12
    end

    scrollChild:SetHeight(math.abs(y) + 20)
    panelDirty = false
end

---------------------------------------------------------------------------
-- TOGGLE PANEL
---------------------------------------------------------------------------
TogglePanel = function()
    if not compendiumPanel then return end
    local db = LetoQOLDB and LetoQOLDB.teleportCompendium
    if not db or not db.enabled then return end

    if compendiumPanel:IsShown() then
        compendiumPanel:Hide()
        if QuestMapFrame then QuestMapFrame:Show() end
    else
        if panelDirty then PopulatePanel() end
        if QuestMapFrame then QuestMapFrame:Hide() end
        compendiumPanel:Show()
        -- First layout pass often runs with width 0; repopulate next frame for correct wrap/row height.
        C_Timer.After(0, function()
            if compendiumPanel and compendiumPanel:IsShown() and not InCombatLockdown() then
                PopulatePanel()
            end
        end)
    end
end

---------------------------------------------------------------------------
-- MODULE LIFECYCLE
---------------------------------------------------------------------------

function module:OnInitialize()
    -- nothing required
end

function module:OnEnable()
    local db = LetoQOLDB and LetoQOLDB.teleportCompendium
    if not db or not db.enabled then return end

    local function SetupUI()
        CreateMapButton()
        CreatePanel()
        ScanTeleports()
    end

    -- World Map may already be loaded
    if WorldMapFrame then
        SetupUI()
    end

    -- Event frame
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("ADDON_LOADED")
    ef:RegisterEvent("SPELLS_CHANGED")
    ef:RegisterEvent("PLAYER_ENTERING_WORLD")

    ef:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" and arg1 == "Blizzard_WorldMap" then
            C_Timer.After(0.2, SetupUI)

        elseif event == "PLAYER_ENTERING_WORLD" then
            C_Timer.After(1, function()
                if WorldMapFrame and not mapButton then SetupUI() end
                ScanTeleports()
            end)

        elseif event == "SPELLS_CHANGED" then
            ScanTeleports()
            if compendiumPanel and compendiumPanel:IsShown() and not InCombatLockdown() then
                PopulatePanel()
            end
        end
    end)
    self.eventFrame = ef

    -- When the World Map closes, restore the quest log and hide our panel
    if WorldMapFrame then
        WorldMapFrame:HookScript("OnHide", function()
            if compendiumPanel and compendiumPanel:IsShown() then
                compendiumPanel:Hide()
                if QuestMapFrame then QuestMapFrame:Show() end
            end
        end)
    end
end

---------------------------------------------------------------------------
-- SETTINGS PANEL  (inside /qol config window)
---------------------------------------------------------------------------

function module:CreateSettingsPanel(parent)
    local db = LetoQOLDB.teleportCompendium
    local UI = addon.UI
    local y  = 0

    -- Title
    UI.CreateSectionHeader(parent, 0, y, L["TELEPORT_COMPENDIUM"] or "Teleport Compendium")
    y = y - 30
    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Enabled
    UI.CreateCheckbox(parent, 0, y, L["ENABLED"] or "Enabled", db.enabled, function(v)
        db.enabled = v
    end)
    y = y - 34

    -- Description
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, y)
    desc:SetText(L["TELEPORT_COMPENDIUM_DESC"]
        or "Adds a Teleport Compendium tab to the World Map showing all Hero's Path teleports.")
    desc:SetTextColor(0.7, 0.7, 0.7)
    desc:SetWidth(480)
    desc:SetWordWrap(true)
    desc:SetJustifyH("LEFT")
end

