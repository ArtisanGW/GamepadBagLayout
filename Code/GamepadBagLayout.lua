-- GamepadBagLayout: in the controller's Combined Backpack, puts the bag buttons
-- together at the bottom of the window instead of scattered among the items, and
-- the Hearthstone at the top, where the cursor starts.
-- Settings sit in the game's Options > AddOns > Gamepad Bag Layout, or /gpbl.
--
-- Files, one job each:
--   GamepadBagLayout.lua   saved settings, the settings page, events, /gpbl
--   BagButtons.lua         where the bag buttons go in the window
--   Hearthstone.lua        finds the Hearthstone's slot; the cursor starts on it
--   BagTint.lua            a tint behind the bag buttons
--   TintPicker.lua         its color swatch, with the picker's opacity bar
--   PickerSticks.lua       the color picker on a controller: sticks, D-pad, opacity bar
--                          (a copy of DevTools/luaSnippets/PickerSticks.lua: change it there)
--   Popup.lua              a popup in the game's style
--   RelatedAddons.lua      hints for our other controller addons
--   Debug.lua              development builds only: /gpbl debug
local ADDON_NAME = ...

local BagLayout = {
    -- enabled: the bag buttons first in the window's grid (its bottom row).
    -- hearthstone: the Hearthstone at the top left; the cursor starts on it.
    -- tintColor ("aarrggbb", as the game's color swatch writes it, alpha ff) and
    -- tintStrength (0 to 100 %, the picker's opacity): the tint behind the bags.
    DEFAULTS = { enabled = true, hearthstone = true, tintColor = "ff409cff", tintStrength = 35 },
}
_G.GamepadBagLayout = BagLayout

function BagLayout.GetSettings()
    if type(GamepadBagLayoutDB) ~= "table" then GamepadBagLayoutDB = {} end
    local settings = GamepadBagLayoutDB
    for key in pairs(settings) do
        if BagLayout.DEFAULTS[key] == nil then settings[key] = nil end
    end
    for key, defaultValue in pairs(BagLayout.DEFAULTS) do
        if settings[key] == nil then settings[key] = defaultValue end
    end
    return settings
end

-- Settings: Options > AddOns > Gamepad Bag Layout

function BagLayout.RegisterSettings()
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then return end
    local settings = BagLayout.GetSettings()
    local category, layout = Settings.RegisterVerticalLayoutCategory("Gamepad Bag Layout")
    BagLayout.category = category

    local function addCheckbox(key, label, tooltip)
        local variableName = "GamepadBagLayout_" .. key
        local setting = Settings.RegisterAddOnSetting(category, variableName, key, settings,
            Settings.VarType.Boolean, label, BagLayout.DEFAULTS[key])
        Settings.SetOnValueChangedCallback(variableName, function() BagLayout.BagButtons.Refresh() end)
        return Settings.CreateCheckbox(category, setting, tooltip)
    end

    addCheckbox("enabled", "Bags at the bottom",
        "Puts your bags' buttons together at the bottom of the controller's bag window.\n\n"
        .. "• Left to right: the backpack, bag 1 and on, the reagent bag\n"
        .. "• Your items keep the game's order above them\n"
        .. "• Slots locked until you add an authenticator: next to your bags\n"
        .. "• A tint sets your bags apart (its color below)\n\n"
        .. "Turned off, each sits after its bag's items again.")
    local hearthstoneRow = addCheckbox("hearthstone", "Hearthstone at the top",
        "Puts your Hearthstone at the top of your bags, ready to use when they open.\n\n"
        .. "The cursor starts on it, outside a fight. Turned off, it stays among your items.")
    if type(hearthstoneRow) == "table" and type(hearthstoneRow.Indent) == "function" then hearthstoneRow:Indent() end

    BagLayout.TintPicker.AddSwatch(category, "Bag tint color",
        "The color behind your bags' buttons, and how strong it is.\n\n"
        .. "On a controller, in the color picker:\n"
        .. "• Left stick: the color\n"
        .. "• Right stick: the brightness\n"
        .. "• D-pad up and down: the opacity (0: no tint)")

    if BagLayout.AddRelatedAddonButtons then BagLayout.AddRelatedAddonButtons(layout) end   -- RelatedAddons.lua
    Settings.RegisterAddOnCategory(category)
end

function BagLayout.Open()
    if BagLayout.category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(BagLayout.category:GetID())
    end
end

-- Events

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, name)
    if event ~= "ADDON_LOADED" or name ~= ADDON_NAME then return end
    eventFrame:UnregisterEvent("ADDON_LOADED")
    BagLayout.GetSettings()
    pcall(BagLayout.RegisterSettings)
    BagLayout.BagButtons.Watch()
    BagLayout.Hearthstone.Watch()
end)

-- /gpbl (or /gamepadbaglayout) opens the settings.
SLASH_GAMEPADBAGLAYOUT1 = "/gpbl"
SLASH_GAMEPADBAGLAYOUT2 = "/gamepadbaglayout"
SlashCmdList.GAMEPADBAGLAYOUT = function()
    BagLayout.Open()
end
