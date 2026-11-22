-- GamepadBagLayout: in the controller's Combined Backpack, groups the bag
-- buttons along the top of the window instead of scattered among the items.
-- Settings sit in the game's Options > AddOns > Gamepad Bag Layout, or /gbl.
--
-- Files, one job each:
--   GamepadBagLayout.lua   saved settings, the settings page, events, /gbl
--   BagButtons.lua         where the bag buttons go in the window
--   Popup.lua              a popup in the game's style
--   RelatedAddons.lua      hints for our other controller addons
local ADDON_NAME = ...

local BagLayout = {
    -- enabled: the bag buttons are grouped at the top of the window.
    DEFAULTS = { enabled = true },
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

    local variableName = "GamepadBagLayout_enabled"
    local setting = Settings.RegisterAddOnSetting(category, variableName, "enabled", settings,
        Settings.VarType.Boolean, "Bag buttons at the top", BagLayout.DEFAULTS.enabled)
    Settings.SetOnValueChangedCallback(variableName, function() BagLayout.BagButtons.Refresh() end)
    Settings.CreateCheckbox(category, setting,
        "Groups your bags' buttons at the top of the controller's bag window.\n\n"
        .. "• The backpack's stays where the game puts it\n"
        .. "• Bag 1, bag 2 and the others follow it, right to left\n\n"
        .. "Turned off, each sits after its bag's items again.")

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
end)

-- /gbl (or /gamepadbaglayout) opens the settings.
SLASH_GAMEPADBAGLAYOUT1 = "/gbl"
SLASH_GAMEPADBAGLAYOUT2 = "/gamepadbaglayout"
SlashCmdList.GAMEPADBAGLAYOUT = function()
    BagLayout.Open()
end
