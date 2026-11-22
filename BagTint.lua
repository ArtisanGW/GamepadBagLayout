-- A tint behind the bag buttons (its color and strength picked in the game's
-- color picker, from the settings' swatch: TintPicker.lua), so they read as their own group at
-- the bottom of the controller's bag window without leaving a slot of the grid
-- empty (BagButtons.lua says why none can be). It's one texture of ours on the
-- window, under its buttons, anchored to the first and last bag button: nothing
-- of the game's moves or changes, and the controller's navigation doesn't see it.
local BagLayout = _G.GamepadBagLayout

local BagTint = {
    MARGIN = 3,   -- around the buttons, inside the 5 px between slots
}
BagLayout.BagTint = BagTint

local tint   -- the texture, made the first time it's shown

-- Red, green and blue (0 to 1) from the settings' "aarrggbb".
function BagTint.ParseColor(hex)
    hex = type(hex) == "string" and hex:match("^%x%x(%x%x)(%x%x)(%x%x)$") and hex or BagLayout.DEFAULTS.tintColor
    local red, green, blue = hex:match("^%x%x(%x%x)(%x%x)(%x%x)$")
    return tonumber(red, 16) / 255, tonumber(green, 16) / 255, tonumber(blue, 16) / 255
end

-- The settings' color and strength, on the tint (now, if it's made).
function BagTint.ApplyColor()
    if not tint then return end
    local settings = BagLayout.GetSettings()
    local red, green, blue = BagTint.ParseColor(settings.tintColor)
    local strength = math.max(0, math.min(100, tonumber(settings.tintStrength) or BagLayout.DEFAULTS.tintStrength))
    tint:SetColorTexture(red, green, blue, strength / 100)
end

-- Behind the bag buttons from first (left) to last (right), on one row.
function BagTint.Show(window, first, last)
    if not tint then
        tint = window:CreateTexture(nil, "ARTWORK", nil, -8)
        BagTint.ApplyColor()
    end
    tint:ClearAllPoints()
    tint:SetPoint("TOPLEFT", first, "TOPLEFT", -BagTint.MARGIN, BagTint.MARGIN)
    tint:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", BagTint.MARGIN, -BagTint.MARGIN)
    tint:Show()
end

function BagTint.Hide()
    if tint then tint:Hide() end
end

function BagTint.IsShown()
    return tint ~= nil and tint:IsShown()
end

-- Saves a color ("aarrggbb", alpha ignored: the strength is apart) and shows it.
function BagTint.SetColor(hex)
    if type(hex) ~= "string" or not hex:match("^%x%x%x%x%x%x%x%x$") then return end
    BagLayout.GetSettings().tintColor = "ff" .. hex:sub(3, 8):lower()
    BagTint.ApplyColor()
end

-- The strength as an opacity, 0 to 1, and back.
function BagTint.Opacity()
    return (tonumber(BagLayout.GetSettings().tintStrength) or BagLayout.DEFAULTS.tintStrength) / 100
end

function BagTint.SetOpacity(alpha)
    BagLayout.GetSettings().tintStrength = math.floor(math.max(0, math.min(1, tonumber(alpha) or 1)) * 100 + 0.5)
    BagTint.ApplyColor()
end
