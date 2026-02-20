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
local teleportCategories = {}   -- { { name = "...", spells = { {spellID, name, icon}, ... } }, ... }
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
                    spellID = spellID,
                    name    = info.name,
                    icon    = info.iconID,
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
                                spellID = useID,
                                name    = sInfo.name,
                                icon    = sInfo.iconID,
                            })
                        end
                    end
                end
                table.sort(spells, function(a, b) return a.name < b.name end)
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
                                spellID = itemInfo.spellID,
                                name    = sInfo.name,
                                icon    = sInfo.iconID,
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

    -- Store a ref so we can update width after layout
    sf:SetScript("OnSizeChanged", function(self, w, h)
        sc:SetWidth(w)
    end)

    compendiumPanel = p
    scrollFrame     = sf
    scrollChild     = sc

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
        if elem.SetAttribute then
            elem:SetAttribute("type", nil)
            elem:SetAttribute("spell", nil)
        end
    end
    wipe(uiElements)

    local y = 0
    local contentWidth = scrollChild:GetWidth()
    if contentWidth < 100 then contentWidth = 400 end
    local COL_WIDTH   = math.floor(contentWidth / 2)
    local ROW_HEIGHT  = 36
    local ICON_SIZE   = 28
    local btnIndex    = 0

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

        -- Spell entries (two columns)
        for i, spell in ipairs(cat.spells) do
            btnIndex = btnIndex + 1
            local col = (i - 1) % 2
            local row = math.floor((i - 1) / 2)

            local btn = CreateFrame("Button", "LetoQOLTP" .. btnIndex,
                                    scrollChild, "SecureActionButtonTemplate")
            btn:SetSize(COL_WIDTH - 4, ROW_HEIGHT)
            btn:SetPoint("TOPLEFT", 2 + col * COL_WIDTH, y - row * ROW_HEIGHT)
            btn:RegisterForClicks("AnyUp", "AnyDown")
            btn:SetAttribute("type", "spell")
            btn:SetAttribute("spell", spell.name)

            -- Highlight
            local hlTex = btn:CreateTexture(nil, "HIGHLIGHT")
            hlTex:SetAllPoints()
            hlTex:SetColorTexture(1, 1, 1, 0.08)

            -- Icon
            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(ICON_SIZE, ICON_SIZE)
            iconTex:SetPoint("LEFT", 4, 0)
            iconTex:SetTexture(spell.icon)
            iconTex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

            -- Name
            local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            nameText:SetPoint("LEFT", iconTex, "RIGHT", 6, 0)
            nameText:SetPoint("RIGHT", -4, 0)
            nameText:SetText(spell.name)
            nameText:SetJustifyH("LEFT")
            nameText:SetWordWrap(false)

            -- Tooltip
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellByID(spell.spellID)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", GameTooltip_Hide)

            table.insert(uiElements, btn)
        end

        local numRows = math.ceil(#cat.spells / 2)
        y = y - numRows * ROW_HEIGHT - 16
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

