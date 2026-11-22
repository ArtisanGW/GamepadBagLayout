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
-- the grid out. It reads where the game put each button (its anchor: on this
-- client all are anchored to one frame along the window's bottom, not to the
-- window as the source shows), orders them as the grid runs (from the bottom
-- right, right to left, then up a row), and hands the same anchors back in a new
-- order: only the bag buttons moved. So the game's spacing and anchor frame stay
-- as they are. Nothing of the game's is replaced: the buttons, their clicks and
-- the controller's navigation stay the game's, and the window keeps its size
-- (the game already leaves a cell for each bag's button). The buttons aren't
-- protected, so this works in a fight too. (A hook on AnchorUtil.GridLayout
-- never ran in game: the game's code doesn't reach an addon's hook on it.)
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

-- A button's anchor as the game set it: { point, relativeTo, relativePoint, x, y }.
local function anchorOf(frame)
    local succeeded, point, relativeTo, relativePoint, x, y = pcall(frame.GetPoint, frame, 1)
    if not (succeeded and point and tonumber(x) and tonumber(y)) then return nil end
    return { point, relativeTo, relativePoint, tonumber(x), tonumber(y) }
end

local function sameGrid(anchor, gridAnchor)
    return anchor[1] == gridAnchor[1] and anchor[2] == gridAnchor[2] and anchor[3] == gridAnchor[3]
end

-- The window's grid as the game laid it out, in its order: { frame, anchor }
-- for its items (not those of a collapsed bag, which the game leaves out) and
-- the bags' buttons; the grid is the one the backpack's button is anchored in.
function BagButtons.GameOrder(window, bagBar)
    local backpackButton = bagButton(bagBar, 0)
    local gridAnchor = backpackButton and anchorOf(backpackButton)
    if not gridAnchor then return {} end
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
        local anchor = anchorOf(frame)
        if anchor and sameGrid(anchor, gridAnchor) then placed[#placed + 1] = { frame = frame, anchor = anchor } end
    end
    -- Bottom row first (lowest y), each row from the right (highest x).
    table.sort(placed, function(first, second)
        if math.abs(first.anchor[5] - second.anchor[5]) > 0.5 then return first.anchor[5] < second.anchor[5] end
        return first.anchor[4] > second.anchor[4]
    end)
    return placed
end

local function canMove(frame)
    if frame:IsForbidden() then return false end
    return not (InCombatLockdown() and frame:IsProtected())
end

-- After the game laid the window out: the same places, bag buttons grouped.
local function afterLayout(window)
    if not BagLayout.GetSettings().enabled then return end
    local bagBar = rawget(_G, "GamepadBagBar")
    if not bagBar or window:IsForbidden() then return end
    local placed = BagButtons.GameOrder(window, bagBar)
    local frames = {}
    for i, entry in ipairs(placed) do frames[i] = entry.frame end
    local regrouped = BagButtons.Regroup(frames, bagBar)
    if not regrouped then return end
    for _, frame in ipairs(regrouped) do
        if not canMove(frame) then return end
    end
    for i, frame in ipairs(regrouped) do
        frame:ClearAllPoints()
        frame:SetPoint(unpack(placed[i].anchor))
    end
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
