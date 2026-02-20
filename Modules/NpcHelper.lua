local addonName, addon = ...
local L = addon.L or {}

---------------------------------------------------------------------------
-- Module registration
---------------------------------------------------------------------------
local module = {}
module.displayName = L["NPC_HELPER"] or "NPC Helper"
module.dbKey       = "npcHelper"
addon:RegisterModule("NpcHelper", module)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

--- Format a copper value as a readable gold string (e.g. "12g 34s 56c")
local function FormatMoney(copper)
    if not copper or copper <= 0 then return "0c" end
    local gold   = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop    = copper % 100
    local parts = {}
    if gold   > 0 then table.insert(parts, gold   .. "|cFFFFD100g|r") end
    if silver > 0 then table.insert(parts, silver .. "|cFFC7C7CFg|r") end
    if cop    > 0 then table.insert(parts, cop    .. "|cFFB87333c|r") end
    return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Auto Repair
---------------------------------------------------------------------------
local function DoAutoRepair()
    local db = LetoQOLDB and LetoQOLDB.npcHelper
    if not db or not db.enabled or not db.autoRepair then return end
    if not CanMerchantRepair() then return end

    local cost, canRepair = GetRepairAllCost()
    if not canRepair or cost <= 0 then return end

    -- Try guild repair first
    if db.useGuildRepair and IsInGuild() then
        local guildOk = pcall(RepairAllItems, true)
        if guildOk then
            print("|cFF00CCFF[LetoQOL]|r " ..
                string.format(L["REPAIRED_GUILD"] or "Repaired all items using guild funds (%s)", FormatMoney(cost)))
            return
        end
    end

    -- Personal repair
    RepairAllItems(false)
    print("|cFF00CCFF[LetoQOL]|r " ..
        string.format(L["REPAIRED_FOR"] or "Repaired all items for %s", FormatMoney(cost)))
end

---------------------------------------------------------------------------
-- Auto Sell Junk
---------------------------------------------------------------------------
local function DoSellJunk()
    local db = LetoQOLDB and LetoQOLDB.npcHelper
    if not db or not db.enabled or not db.autoSellJunk then return end

    local totalCopper = 0
    local itemCount   = 0

    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == Enum.ItemQuality.Poor and not info.hasNoValue then
                totalCopper = totalCopper + (info.sellPrice or 0) * (info.stackCount or 1)
                itemCount   = itemCount + 1
                C_Container.UseContainerItem(bag, slot)
            end
        end
    end

    if itemCount > 0 then
        print("|cFF00CCFF[LetoQOL]|r " ..
            string.format(L["SOLD_JUNK"] or "Sold %d junk item(s)", itemCount))
    end
end

---------------------------------------------------------------------------
-- MODULE LIFECYCLE
---------------------------------------------------------------------------

function module:OnInitialize()
    -- nothing required
end

function module:OnEnable()
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("MERCHANT_SHOW")
    ef:SetScript("OnEvent", function(_, event)
        if event == "MERCHANT_SHOW" then
            -- Small delay so the merchant window is fully ready
            C_Timer.After(0.1, function()
                DoAutoRepair()
                DoSellJunk()
            end)
        end
    end)
    self.eventFrame = ef
end

function module:OnDisable()
    if self.eventFrame then self.eventFrame:UnregisterAllEvents() end
end

---------------------------------------------------------------------------
-- SETTINGS PANEL
---------------------------------------------------------------------------

function module:CreateSettingsPanel(parent)
    local db = LetoQOLDB.npcHelper
    local UI = addon.UI
    local y  = 0

    -- Title
    UI.CreateSectionHeader(parent, 0, y, L["NPC_HELPER"] or "NPC Helper")
    y = y - 30
    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Enabled (master toggle)
    UI.CreateCheckbox(parent, 0, y, L["ENABLED"] or "Enabled", db.enabled, function(v)
        db.enabled = v
    end)
    y = y - 34

    -- Description
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    desc:SetPoint("TOPLEFT", 0, y)
    desc:SetText(L["NPC_HELPER_DESC"] or "Automatically repairs gear and sells junk when visiting a merchant.")
    desc:SetTextColor(0.7, 0.7, 0.7)
    desc:SetWidth(480)
    desc:SetWordWrap(true)
    desc:SetJustifyH("LEFT")
    y = y - 34

    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Auto Repair
    UI.CreateCheckbox(parent, 0, y, L["AUTO_REPAIR"] or "Auto Repair", db.autoRepair, function(v)
        db.autoRepair = v
    end)
    y = y - 30

    -- Use Guild Repair (indented)
    UI.CreateCheckbox(parent, 26, y, L["USE_GUILD_REPAIR"] or "Use Guild Funds for Repair", db.useGuildRepair, function(v)
        db.useGuildRepair = v
    end)
    y = y - 34

    UI.CreateSeparator(parent, 0, y)
    y = y - 20

    -- Auto Sell Junk
    UI.CreateCheckbox(parent, 0, y, L["AUTO_SELL_JUNK"] or "Auto Sell Junk", db.autoSellJunk, function(v)
        db.autoSellJunk = v
    end)
end

