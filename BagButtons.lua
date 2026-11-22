-- Groups the bag buttons in the controller's Combined Backpack. With the
-- controller UI on, the game puts one button per bag (its free slots, its menu)
-- into the window's grid, each right after that bag's items
-- (ContainerFrameMixin:UpdateItemLayout, forever branch
-- Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:1080-1105), so they end up
-- scattered among the items. This keeps the backpack's button where the game put
-- it and moves the others right after it: bag 1, bag 2 and so on (then the
-- keyring's), right to left along the top of the window.
--
-- The game lays the grid out with AnchorUtil.GridLayout (Blizzard_SharedXMLBase/
-- AnchorUtil.lua:122). A post-hook on it sees the game's own list, in the
-- game's own order, and lays the same buttons out again with only the bag
-- buttons moved. Nothing of the game's is replaced: the buttons, their clicks
-- and the controller's navigation stay the game's, and the window keeps its size
-- (the game already leaves a cell for each bag's button). The buttons aren't
-- protected, so this works in a fight too.
local BagLayout = _G.GamepadBagLayout

local BagButtons = {}
BagLayout.BagButtons = BagButtons

local layingOut = false   -- our own GridLayout call, not the game's

-- The bag buttons that move, in their order after the backpack's: bag 1, bag 2
-- and on (the reagent bag's, if any), then the keyring's.
function BagButtons.Ordered(bagBar)
    local ordered = {}
    local function add(bagID)
        local succeeded, button = pcall(bagBar.GetBagButton, bagBar, bagID)
        if succeeded and button then ordered[#ordered + 1] = button end
    end
    for bagID = 1, tonumber(rawget(_G, "NUM_TOTAL_BAG_FRAMES")) or 4 do add(bagID) end
    local keyringID = rawget(_G, "KEYRING_CONTAINER")
    if keyringID then add(keyringID) end
    return ordered
end

-- The game's list with those bag buttons taken out and put after everything
-- else, in their order; nil when none of them is in it.
function BagButtons.Regroup(frames, bagBar)
    local present = {}
    for _, frame in ipairs(frames) do present[frame] = true end
    local moving, isMoving = {}, {}
    for _, button in ipairs(BagButtons.Ordered(bagBar)) do
        if present[button] then
            moving[#moving + 1] = button
            isMoving[button] = true
        end
    end
    if #moving == 0 then return nil end
    local regrouped = {}
    for _, frame in ipairs(frames) do
        if not isMoving[frame] then regrouped[#regrouped + 1] = frame end
    end
    for _, button in ipairs(moving) do regrouped[#regrouped + 1] = button end
    return regrouped
end

local function canMove(frame)
    if frame:IsForbidden() then return false end
    return not (InCombatLockdown() and frame:IsProtected())
end

-- After any GridLayout: only the Combined Backpack's, with the controller's bag buttons in it.
local function afterGridLayout(frames, initialAnchor, layout)
    if layingOut or not BagLayout.GetSettings().enabled then return end
    local combinedBags = rawget(_G, "ContainerFrameCombinedBags")
    local bagBar = rawget(_G, "GamepadBagBar")
    if not (combinedBags and bagBar and type(frames) == "table") then return end
    if type(initialAnchor) ~= "table" or type(initialAnchor.GetRelativeTo) ~= "function" then return end
    if initialAnchor:GetRelativeTo() ~= combinedBags or combinedBags:IsForbidden() then return end
    local regrouped = BagButtons.Regroup(frames, bagBar)
    if not regrouped then return end
    for _, frame in ipairs(regrouped) do
        if not canMove(frame) then return end
    end
    layingOut = true
    local succeeded, problem = pcall(AnchorUtil.GridLayout, regrouped, initialAnchor, layout)
    layingOut = false
    if not succeeded then geterrorhandler()(problem) end
end

-- The game lays the window out again (with or without us, as the setting says).
function BagButtons.Refresh()
    local combinedBags = rawget(_G, "ContainerFrameCombinedBags")
    if not (combinedBags and combinedBags:IsShown() and type(combinedBags.UpdateItemLayout) == "function") then return end
    local succeeded, problem = pcall(combinedBags.UpdateItemLayout, combinedBags)
    if not succeeded then geterrorhandler()(problem) end
end

function BagButtons.Watch()
    if BagButtons.watching or type(AnchorUtil) ~= "table" or type(AnchorUtil.GridLayout) ~= "function" then return end
    BagButtons.watching = true
    hooksecurefunc(AnchorUtil, "GridLayout", afterGridLayout)
end
