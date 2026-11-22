-- The bag tint's color swatch on the settings page, with the picker's opacity
-- bar for its strength. The swatch is the game's own (Settings.CreateColorSwatch,
-- SettingsColorSwatchMixin, forever branch Blizzard_SettingControls.lua:1067-1097):
-- it opens the color picker from the game's code. (Opened from addon code
-- instead, the picker's controller bindings go on the game's binding stack
-- tainted: its sticks do nothing.) That swatch sets the color only, so
-- PickerSticks.lua adds the opacity bar, and the controller's sticks and D-pad,
-- when the picker shows for this swatch.
local _, addonTable = ...   -- PickerSticks.lua (devAddons/luaSnippets) puts itself there
local BagLayout = _G.GamepadBagLayout

local TintPicker = {
    OPENED_WITHIN = 0.5,   -- seconds between the swatch reading its color and the picker showing
}
BagLayout.TintPicker = TintPicker

local pickerAskedAt   -- when the swatch last read its color: it's about to open the picker

local function now() return type(GetTime) == "function" and GetTime() or nil end

-- What the swatch shows and saves: "aarrggbb", alpha always ff.
function TintPicker.SwatchColor()
    pickerAskedAt = now()
    return BagLayout.GetSettings().tintColor
end

function TintPicker.SetSwatchColor(value)
    BagLayout.BagTint.SetColor(tostring(value or ""):gsub("^#", ""))
end

-- PickerSticks' owner: whether the picker showing is ours, and the tint's strength.
TintPicker.owner = {
    OpenedThePicker = function()
        local time = now()
        return pickerAskedAt ~= nil and time ~= nil and time - pickerAskedAt <= TintPicker.OPENED_WITHIN
    end,
    Opacity = function() return BagLayout.BagTint.Opacity() end,
    SetOpacity = function(alpha) BagLayout.BagTint.SetOpacity(alpha) end,
}

-- The swatch, on the settings page being built. Nothing if the game lacks it.
function TintPicker.AddSwatch(category, label, tooltip)
    if not (type(Settings.RegisterProxySetting) == "function" and type(Settings.CreateColorSwatch) == "function") then
        return
    end
    addonTable.PickerSticks.Watch(TintPicker.owner)
    local setting = Settings.RegisterProxySetting(category, "GamepadBagLayout_tintColorSwatch",
        Settings.VarType.String, label, BagLayout.DEFAULTS.tintColor, TintPicker.SwatchColor, TintPicker.SetSwatchColor)
    Settings.CreateColorSwatch(category, setting, tooltip)
end
