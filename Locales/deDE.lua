local _, addon = ...
if GetLocale() ~= "deDE" then return end

addon.L = addon.L or {}
local L = addon.L

-- General
L["ADDON_LOADED"]               = "LetoQOL geladen. Tippe /qol um die Einstellungen zu öffnen."
L["SETTINGS"]                   = "Einstellungen"

-- Character Pane Enhancement
L["CHARACTER_PANE_ENHANCEMENT"] = "Charakterfenster Verbesserung"
L["ENABLED"]                    = "Aktiviert"
L["SHOW_ITEM_LEVEL"]            = "Itemlevel anzeigen"
L["SHOW_ENCHANTS"]              = "Verzauberungen anzeigen"
L["SHOW_GEMS"]                  = "Edelsteine anzeigen"
L["SHOW_MISSING_ENCHANTS"]      = "Fehlende Verzauberungen hervorheben"
L["ILVL_COLOR"]                 = "Itemlevel Farbe"
L["ILVL_COLOR_QUALITY"]         = "Gegenstandsqualität"
L["ILVL_COLOR_CUSTOM"]          = "Benutzerdefinierte Farbe"
L["NOT_ENCHANTED"]              = "Nicht verzaubert"
L["SHOW_AVG_ITEM_LEVEL"]       = "Durchschnittliches Itemlevel anzeigen (Dezimal)"
L["SHOW_DURABILITY"]            = "Haltbarkeit % anzeigen (pro Item)"
L["SHOW_TOTAL_DURABILITY"]     = "Gesamt-Haltbarkeit % anzeigen"
L["ITEM_LEVEL_LABEL"]           = "Gegenstandsstufe"

-- Gateway Tracker
L["GATEWAY_TRACKER"]            = "Gateway Tracker"
L["SHOW_ONLY_IN_COMBAT"]        = "Nur im Kampf anzeigen"
L["TEXT_SIZE"]                   = "Textgröße"
L["TEXT_COLOR"]                  = "Textfarbe"
L["TEXT_POSITION"]               = "Textposition"
L["DRAG_TO_MOVE"]                = "Ziehe den Text auf dem Bildschirm um ihn zu verschieben."
L["TEST_POSITION"]               = "Test / Vorschau"
L["RESET_POSITION"]              = "Position zurücksetzen"

-- Pet Reminder
L["PET_REMINDER"]                = "Pet Reminder"
L["PET_MISSING"]                 = "**Pet fehlt!**"
L["PET_PASSIVE"]                 = "**Pet passiv!**"
L["SHOW_ONLY_IN_GROUP"]          = "Nur in Gruppe / Schlachtzug"

-- Focus Interrupt
L["FOCUS_INTERRUPT"]             = "Focus Interrupt"
L["FOCUS_INTERRUPT_DESC"]        = "Bei Ready Check wird dein Focus-Interrupt-Marker im Gruppenchat gesendet (nicht in Schlachtzügen)."
L["ICON_PICKER"]                 = "Symbol Auswahl"
L["PREVIEW"]                     = "Vorschau"
L["AUTO_MARK_FOCUS"]             = "Focus markieren Button anzeigen"
L["AUTO_MARK_FOCUS_DESC"]        = "Zeigt einen kleinen Button am Focus-Frame. Klick darauf markiert dein Focus-Ziel mit dem ausgewählten Symbol."
L["MARK_FOCUS_TARGET"]           = "Focus-Ziel markieren"
L["MARK_FOCUS_KEYBIND_HINT"]     = "Binden über ESC → Tastenbelegung → LetoQOL"
L["CURRENT_KEYBIND"]             = "Aktuelle Tastenbelegung"
L["MARK_MODE"]                   = "Markier-Modus"
L["MARK_MODE_FOCUS"]             = "Focus-Ziel"
L["MARK_MODE_MOUSEOVER"]         = "Mouseover"

-- Auto Role Accept
L["AUTO_ROLE_ACCEPT"]            = "Auto Rollenbestätigung"
L["AUTO_ROLE_ACCEPT_DESC"]       = "Bestätigt automatisch deine Rolle, wenn der Gruppenleiter für Inhalte anmeldet."

-- NPC Helper
L["NPC_HELPER"]                  = "NPC Helfer"
L["NPC_HELPER_DESC"]             = "Repariert automatisch Ausrüstung und verkauft Ramsch beim Händler."
L["AUTO_REPAIR"]                 = "Auto Reparatur"
L["USE_GUILD_REPAIR"]            = "Gildenbank für Reparatur nutzen"
L["AUTO_SELL_JUNK"]              = "Ramsch automatisch verkaufen"
L["REPAIRED_FOR"]                = "Alle Gegenstände repariert für %s"
L["REPAIRED_GUILD"]              = "Alle Gegenstände mit Gildenmitteln repariert (%s)"
L["SOLD_JUNK"]                   = "%d Ramsch-Gegenstand/-stände verkauft"
L["NO_JUNK"]                     = "Kein Ramsch zum Verkaufen."

-- Teleport Compendium
L["TELEPORT_COMPENDIUM"]         = "Teleport-Kompendium"
L["TELEPORT_COMPENDIUM_DESC"]    = "Fügt einen Teleport-Kompendium Tab zur Weltkarte hinzu mit allen Hero's Path Teleports."

-- Hide Talking Head
L["HIDE_TALKING_HEAD"]           = "Talking Head ausblenden"
L["HIDE_TALKING_HEAD_DESC"]      = "Blendet das Talking-Head-Popup aus, das bei Quests und Events erscheint."

-- Shared: Lock / Unlock
L["UNLOCK_POSITION"]             = "Entsperren"
L["LOCK_POSITION"]               = "Sperren"

