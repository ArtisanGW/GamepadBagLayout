-- Finds the Hearthstone among the bag window's items, so it can sit at the top
-- next to the bag buttons (BagButtons.lua), and starts the cursor on it when the bags
-- open, to use it at once. It's the game's own item button for the slot the
-- Hearthstone is in: moved, not copied, so using it, its tooltip and the
-- controller's navigation stay the game's.
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

-- Where the cursor starts when the bags open: the game picks the backpack's
-- button (ContainerFrameCombinedBagsMixin:SmartNavPanelInfoAdded, forever branch
-- Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:3558-3567). Right after it
-- does, the Hearthstone is picked instead, through the same call, which the game
-- lets addons make outside a fight (SmartNavigation.lua:1004-1015, wrapped by
-- SecureHelper:WrapFunction). In a fight, the game's pick stays.
local pickingTarget = false

local function afterTargetPicked(navigation, frame, button)
    local window = rawget(_G, "ContainerFrameCombinedBags")
    if pickingTarget or frame ~= window or InCombatLockdown() then return end
    local settings = BagLayout.GetSettings()
    if not (settings.enabled and settings.hearthstone) then return end
    local items = {}
    for _, itemButton in window:EnumerateValidItems() do items[#items + 1] = itemButton end
    local hearthstone = Hearthstone.Find(items)
    if not hearthstone or hearthstone == button then return end
    pickingTarget = true
    local succeeded, problem = pcall(navigation.SetTargetButtonForFrame, navigation, window, hearthstone)
    pickingTarget = false
    if not succeeded then geterrorhandler()(problem) end
end

function Hearthstone.Watch()
    local navigation = rawget(_G, "SmartNavigation")
    if Hearthstone.watching or type(navigation) ~= "table" or type(navigation.SetTargetButtonForFrame) ~= "function" then
        return
    end
    Hearthstone.watching = true
    hooksecurefunc(navigation, "SetTargetButtonForFrame", afterTargetPicked)
end
