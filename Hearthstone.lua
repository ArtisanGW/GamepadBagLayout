-- Finds the Hearthstone among the bag window's items, so it can sit at the
-- right end of the bag row (BagButtons.lua). It's the game's own item button
-- for the slot the Hearthstone is in: moved, not copied, so using it, its
-- tooltip and the controller's navigation stay the game's.
local BagLayout = _G.GamepadBagLayout

local Hearthstone = {
    ITEM_ID = 6948,   -- Hearthstone
}
BagLayout.Hearthstone = Hearthstone

local function itemIDOf(itemButton)
    local bagID = itemButton.bagID or itemButton:GetBagID()
    local slotID = itemButton:GetID()
    local container = rawget(_G, "C_Container")
    if not (bagID and slotID and type(container) == "table" and type(container.GetContainerItemID) == "function") then
        return nil
    end
    local succeeded, itemID = pcall(container.GetContainerItemID, bagID, slotID)
    return succeeded and itemID or nil
end

-- The item button holding the Hearthstone, or nil (the first one found).
function Hearthstone.Find(itemButtons)
    for _, itemButton in ipairs(itemButtons) do
        if itemIDOf(itemButton) == Hearthstone.ITEM_ID then return itemButton end
    end
    return nil
end
