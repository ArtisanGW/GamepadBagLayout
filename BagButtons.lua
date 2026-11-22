-- Moves the bag buttons of the controller's Combined Backpack to the end of its
-- grid (the top row) and the Hearthstone to its start (the bottom right cell). With the controller UI on, the game
-- puts one button per bag (its free slots, its menu) into the window's grid,
-- each right after that bag's items (ContainerFrameMixin:UpdateItemLayout,
-- forever branch Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:1080-1105),
-- so they end up scattered among the items.
--
-- A post-hook on the window's own UpdateItemLayout runs once the game has laid
-- the grid out. The game's cells stay as they are, in its order (from the bottom
-- right, right to left, then up a row: ContainerFrameCombinedBagsMixin:
-- GetInitialItemAnchor, ContainerFrame.lua:3032); only who sits in them changes:
-- the Hearthstone first (Hearthstone.lua), then the items in the game's order,
-- then the bag buttons, so they read left to right on the top row: the
-- backpack's, bag 1 and on, the reagent bag's, the keyring's. No cell is added
-- or left empty, so the window keeps the game's size and the controller's grid
-- navigation (which needs columns without holes: SmartNavigation.lua:1399) works
-- as on the game's own layout. Nothing of the game's is replaced, and turned
-- off, the game lays it out again on its own. Neither the window nor its
-- buttons are protected, so this works in a fight too.
local BagLayout = _G.GamepadBagLayout

local BagButtons = {}
BagLayout.BagButtons = BagButtons

BagButtons.regroupedCount = 0   -- times the window was laid out again (to check in game)

local function bagButton(bagBar, bagID)
    local succeeded, button = pcall(bagBar.GetBagButton, bagBar, bagID)
    return succeeded and button or nil
end

-- The bag buttons as they read, left to right: the backpack's, bag 1, bag 2
-- and on (the reagent bag's, if any), then the keyring's.
function BagButtons.Ordered(bagBar)
    local ordered = {}
    for bagID = 0, tonumber(rawget(_G, "NUM_TOTAL_BAG_FRAMES")) or 4 do
        ordered[#ordered + 1] = bagButton(bagBar, bagID)
    end
    local keyringID = rawget(_G, "KEYRING_CONTAINER")
    if keyringID then ordered[#ordered + 1] = bagButton(bagBar, keyringID) end
    return ordered
end

-- The game's grid in its new order: the Hearthstone (optional), the items (in
-- the game's order), then the bag buttons, right to left, so they read left to
-- right in the window.
function BagButtons.Reorder(frames, bagBar, hearthstone)
    local present = {}
    for _, frame in ipairs(frames) do present[frame] = true end
    local bagButtons, isBagButton = {}, {}
    for _, button in ipairs(BagButtons.Ordered(bagBar)) do
        if present[button] and not isBagButton[button] then
            bagButtons[#bagButtons + 1] = button
            isBagButton[button] = true
        end
    end
    if #bagButtons == 0 then return nil end
    local ordered = {}
    if hearthstone and present[hearthstone] then ordered[1] = hearthstone end
    for _, frame in ipairs(frames) do
        if not isBagButton[frame] and frame ~= hearthstone then ordered[#ordered + 1] = frame end
    end
    for i = #bagButtons, 1, -1 do ordered[#ordered + 1] = bagButtons[i] end
    return ordered
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

-- After the game laid the window out: the same cells, the Hearthstone first,
-- the bag buttons last.
local function afterLayout(window)
    if not BagLayout.GetSettings().enabled then return end
    local bagBar = rawget(_G, "GamepadBagBar")
    if not bagBar or window:IsForbidden() then return end
    local placed = BagButtons.GameOrder(window, bagBar)
    if #placed == 0 then return end
    local frames = {}
    for i, entry in ipairs(placed) do frames[i] = entry.frame end
    local hearthstone = nil
    if BagLayout.GetSettings().hearthstone then
        local isBagButton, items = {}, {}
        for _, button in ipairs(BagButtons.Ordered(bagBar)) do isBagButton[button] = true end
        for _, frame in ipairs(frames) do
            if not isBagButton[frame] then items[#items + 1] = frame end
        end
        hearthstone = BagLayout.Hearthstone.Find(items)
    end
    local ordered = BagButtons.Reorder(frames, bagBar, hearthstone)
    if not ordered then return end
    if InCombatLockdown() and window:IsProtected() then return end
    for _, frame in ipairs(ordered) do
        if not canMove(frame) then return end
    end
    for i, frame in ipairs(ordered) do
        frame:ClearAllPoints()
        frame:SetPoint(unpack(placed[i].anchor))
    end
    BagButtons.regroupedCount = BagButtons.regroupedCount + 1
end

-- The game sizes and lays the window out again (with or without us, as the
-- setting says), as it does itself (ContainerFrame.lua:2858-2860).
function BagButtons.Refresh()
    local window = rawget(_G, "ContainerFrameCombinedBags")
    if not (window and window:IsShown() and type(window.UpdateItemLayout) == "function") then return end
    local succeeded, problem = pcall(function()
        if type(window.UpdateFrameSize) == "function" then window:UpdateFrameSize() end
        window:UpdateItemLayout()
        local updateAnchors = rawget(_G, "UpdateContainerFrameAnchors")
        if type(updateAnchors) == "function" then updateAnchors() end
    end)
    if not succeeded then geterrorhandler()(problem) end
end

function BagButtons.Watch()
    local window = rawget(_G, "ContainerFrameCombinedBags")
    if BagButtons.watching or not window or type(window.UpdateItemLayout) ~= "function" then return end
    BagButtons.watching = true
    hooksecurefunc(window, "UpdateItemLayout", afterLayout)
end
