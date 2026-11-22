-- Groups the bag buttons in the controller's Combined Backpack. With the
-- controller UI on, the game puts one button per bag (its free slots, its menu)
-- into the window's grid, each right after that bag's items
-- (ContainerFrameMixin:UpdateItemLayout, forever branch
-- Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:1080-1105), so they end up
-- scattered among the items. This keeps the backpack's button where the game put
-- it and moves the others right after it: bag 1, bag 2 and so on (then the
-- keyring's), right to left along the top of the window.
--
-- A post-hook on the window's own UpdateItemLayout runs once the game has laid
-- the grid out. It reads the game's order from where the game just put each
-- button (the grid runs from the bottom right, right to left, then up a row),
-- and lays the same buttons out again with the window's own anchor and grid
-- (GetInitialItemAnchor, GetAnchorLayout), only the bag buttons moved. Nothing of
-- the game's is replaced: the buttons, their clicks and the controller's
-- navigation stay the game's, and the window keeps its size (the game already
-- leaves a cell for each bag's button). The buttons aren't protected, so this
-- works in a fight too. (A hook on AnchorUtil.GridLayout never ran: the game's
-- code doesn't reach an addon's hook on it.)
local BagLayout = _G.GamepadBagLayout

local BagButtons = {}
BagLayout.BagButtons = BagButtons

BagButtons.regroupedCount = 0   -- times the window was laid out again (to check in game)

local function bagButton(bagBar, bagID)
    local succeeded, button = pcall(bagBar.GetBagButton, bagBar, bagID)
    return succeeded and button or nil
end

-- The bag buttons that move, in their order after the backpack's: bag 1, bag 2
-- and on (the reagent bag's, if any), then the keyring's.
function BagButtons.Ordered(bagBar)
    local ordered = {}
    for bagID = 1, tonumber(rawget(_G, "NUM_TOTAL_BAG_FRAMES")) or 4 do
        ordered[#ordered + 1] = bagButton(bagBar, bagID)
    end
    local keyringID = rawget(_G, "KEYRING_CONTAINER")
    if keyringID then ordered[#ordered + 1] = bagButton(bagBar, keyringID) end
    return ordered
end

-- The list with those bag buttons taken out and put after everything else, in
-- their order; nil when none of them is in it.
function BagButtons.Regroup(frames, bagBar)
    local present = {}
    for _, frame in ipairs(frames) do present[frame] = true end
    local moving, isMoving = {}, {}
    for _, button in ipairs(BagButtons.Ordered(bagBar)) do
        if present[button] and not isMoving[button] then
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

-- Where the game put a button in the window's grid: its offsets from the
-- window's bottom right, or nil when it isn't in the grid.
local function gridOffsets(frame, window)
    local succeeded, point, relativeTo, _, x, y = pcall(frame.GetPoint, frame, 1)
    if not (succeeded and point == "BOTTOMRIGHT" and relativeTo == window) then return nil end
    return tonumber(x), tonumber(y)
end

-- The window's buttons as the game laid them out, in its order: its items (not
-- those of a collapsed bag, which the game leaves out) and the bags' buttons.
function BagButtons.GameOrder(window, bagBar)
    local candidates = {}
    for _, itemButton in window:EnumerateValidItems() do
        local bagID = itemButton.bagID or itemButton:GetBagID()
        local itsBagButton = bagButton(bagBar, bagID)
        if not (itsBagButton and itsBagButton.isCollapsed == true) then candidates[#candidates + 1] = itemButton end
    end
    local firstBag = tonumber(rawget(_G, "STARTING_BAG_INDEX")) or rawget(_G, "KEYRING_CONTAINER") or 0
    local lastBag = tonumber(rawget(_G, "ENDING_BAG_INDEX")) or tonumber(rawget(_G, "NUM_TOTAL_BAG_FRAMES")) or 4
    local seen = {}
    for bagID = firstBag, lastBag do
        local button = bagButton(bagBar, bagID)
        if button and not seen[button] then
            seen[button] = true
            candidates[#candidates + 1] = button
        end
    end
    local placed = {}
    for _, frame in ipairs(candidates) do
        local x, y = gridOffsets(frame, window)
        if x then placed[#placed + 1] = { frame = frame, x = x, y = y } end
    end
    -- Bottom row first (lowest y), each row from the right (highest x).
    table.sort(placed, function(first, second)
        if math.abs(first.y - second.y) > 0.5 then return first.y < second.y end
        return first.x > second.x
    end)
    local ordered = {}
    for i, entry in ipairs(placed) do ordered[i] = entry.frame end
    return ordered
end

local function canMove(frame)
    if frame:IsForbidden() then return false end
    return not (InCombatLockdown() and frame:IsProtected())
end

-- After the game laid the window out.
local function afterLayout(window)
    if not BagLayout.GetSettings().enabled then return end
    local bagBar = rawget(_G, "GamepadBagBar")
    if not bagBar or window:IsForbidden() then return end
    local regrouped = BagButtons.Regroup(BagButtons.GameOrder(window, bagBar), bagBar)
    if not regrouped then return end
    for _, frame in ipairs(regrouped) do
        if not canMove(frame) then return end
    end
    local succeeded, problem = pcall(AnchorUtil.GridLayout, regrouped, window:GetInitialItemAnchor(), window:GetAnchorLayout())
    if not succeeded then return geterrorhandler()(problem) end
    BagButtons.regroupedCount = BagButtons.regroupedCount + 1
end

-- The game lays the window out again (with or without us, as the setting says).
function BagButtons.Refresh()
    local window = rawget(_G, "ContainerFrameCombinedBags")
    if not (window and window:IsShown() and type(window.UpdateItemLayout) == "function") then return end
    local succeeded, problem = pcall(window.UpdateItemLayout, window)
    if not succeeded then geterrorhandler()(problem) end
end

function BagButtons.Watch()
    local window = rawget(_G, "ContainerFrameCombinedBags")
    if BagButtons.watching or not window or type(window.UpdateItemLayout) ~= "function" then return end
    BagButtons.watching = true
    hooksecurefunc(window, "UpdateItemLayout", afterLayout)
end
