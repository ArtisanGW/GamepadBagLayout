-- A slight gold tint behind the bag buttons, so they read as their own group at
-- the bottom of the controller's bag window without leaving a slot of the grid
-- empty (BagButtons.lua says why none can be). It's one texture of ours on the
-- window, under its buttons, anchored to the first and last bag button: nothing
-- of the game's moves or changes, and the controller's navigation doesn't see it.
local BagLayout = _G.GamepadBagLayout

local BagTint = {
    COLOR = { 1, 0.82, 0, 0.12 },   -- the game's gold (NORMAL_FONT_COLOR), faint
    MARGIN = 3,                      -- around the buttons, inside the 5 px between slots
}
BagLayout.BagTint = BagTint

local tint   -- the texture, made the first time it's shown

-- Behind the bag buttons from first (left) to last (right), on one row.
function BagTint.Show(window, first, last)
    if not tint then
        tint = window:CreateTexture(nil, "ARTWORK", nil, -8)
        tint:SetColorTexture(unpack(BagTint.COLOR))
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
