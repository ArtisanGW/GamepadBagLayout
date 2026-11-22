-- Puts the bag buttons of the controller's Combined Backpack on their own row at
-- the top of the window. With the controller UI on, the game puts one button per
-- bag (its free slots, its menu) into the window's grid, each right after that
-- bag's items (ContainerFrameMixin:UpdateItemLayout, forever branch
-- Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:1080-1105), so they end up
-- scattered among the items. Here the items keep the game's order, closed up,
-- and the bag buttons get the top row, read left to right: the backpack's, bag
-- 1, bag 2 and on (the reagent bag's, if any), then the keyring's. The
-- Hearthstone's slot (Hearthstone.lua), when it's in the bags, goes at the
-- right end of that row.
--
-- Post-hooks on the window's own UpdateFrameSize and UpdateItemLayout run once
-- the game has sized it and laid the grid out (it always does both, in that
-- order: ContainerFrame.lua:1310-1311, 2858-2859). The grid's anchor and spacing
-- are read from where the game put each button: on the Combined Backpack they
-- are anchored to its money bar (ContainerFrameCombinedBagsMixin:
-- GetInitialItemAnchor, ContainerFrame.lua:3032), from the bottom right, right to
-- left, then up a row. Items go back on the same grid in the game's order, with
-- no holes in a column, as the controller's navigation needs (see Plan); the
-- bag buttons go on the top row. The window's height follows the rows that
-- takes. Nothing of the game's is replaced: the buttons, their clicks and the
-- controller's navigation stay the game's, and turned off, the game sizes and
-- lays it out again on its own. Neither the window nor its buttons are
-- protected, so this works in a fight too.
local BagLayout = _G.GamepadBagLayout

local BagButtons = {
    FALLBACK_STEP = 42,   -- a 37 px button and 5 px between (ContainerFrame.lua:25-26)
}
BagLayout.BagButtons = BagButtons

BagButtons.regroupedCount = 0   -- times the window was laid out again (to check in game)

local gameHeight              -- the window's height as the game last set it

local function bagButton(bagBar, bagID)
    local succeeded, button = pcall(bagBar.GetBagButton, bagBar, bagID)
    return succeeded and button or nil
end

-- The bag buttons in their row's order, left to right: the backpack's, bag 1,
-- bag 2 and on (the reagent bag's, if any), then the keyring's.
function BagButtons.Ordered(bagBar)
    local ordered = {}
    for bagID = 0, tonumber(rawget(_G, "NUM_TOTAL_BAG_FRAMES")) or 4 do
        ordered[#ordered + 1] = bagButton(bagBar, bagID)
    end
    local keyringID = rawget(_G, "KEYRING_CONTAINER")
    if keyringID then ordered[#ordered + 1] = bagButton(bagBar, keyringID) end
    return ordered
end

-- Splits the game's grid into its items (in the game's order) and its bag
-- buttons (in their row's order).
function BagButtons.Split(frames, bagBar)
    local present = {}
    for _, frame in ipairs(frames) do present[frame] = true end
    local bagButtons, isBagButton = {}, {}
    for _, button in ipairs(BagButtons.Ordered(bagBar)) do
        if present[button] and not isBagButton[button] then
            bagButtons[#bagButtons + 1] = button
            isBagButton[button] = true
        end
    end
    local items = {}
    for _, frame in ipairs(frames) do
        if not isBagButton[frame] then items[#items + 1] = frame end
    end
    return items, bagButtons
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

-- The grid's shape from the game's layout: its first cell's anchor (bottom
-- right), the step to the next column (leftwards) and row (upwards), its columns
-- and rows.
function BagButtons.Grid(window, placed)
    local first = placed[1].anchor
    local columnStep, rowStep
    for i = 2, #placed do
        local anchor = placed[i].anchor
        if not rowStep and math.abs(anchor[5] - first[5]) > 0.5 then rowStep = anchor[5] - first[5] end
        if not columnStep and math.abs(anchor[5] - first[5]) <= 0.5 then columnStep = anchor[4] - first[4] end
    end
    columnStep = columnStep or -BagButtons.FALLBACK_STEP
    rowStep = rowStep or math.abs(columnStep)
    local columns = type(window.GetColumns) == "function" and tonumber(window:GetColumns()) or nil
    if not columns then
        columns = 0
        for _, entry in ipairs(placed) do
            if math.abs(entry.anchor[5] - first[5]) <= 0.5 then columns = columns + 1 end
        end
    end
    local rows = type(window.GetRows) == "function" and tonumber(window:GetRows()) or nil
    if not rows then rows = math.floor((placed[#placed].anchor[5] - first[5]) / rowStep + 0.5) + 1 end
    return { first = first, columnStep = columnStep, rowStep = rowStep, columns = math.max(1, columns), rows = rows }
end

-- Where each button goes, and how many rows that takes. The controller moves
-- through the window as a grid of columns, counting each column's buttons from
-- the bottom (SmartNavigationMixin:GetButtonInDirectionGrid, forever branch
-- Blizzard_GamepadSmartNavigation/SmartNavigation.lua:1399-1470, with the
-- window's height compensation on: ContainerFrame.lua:3562). That only lands on
-- the button beside you when no column has a hole: each fills from the bottom up,
-- with any gap at its top. So:
--   bag row (the top one): the bag buttons from the left, the Hearthstone
--     (rightEnd, optional) at the right end, free cells between them;
--   items: full rows under the bag and Hearthstone columns; the columns under the
--     free cells take what's left, row by row (up into the bag row if need be),
--     so their gaps sit at their tops.
-- Items keep the game's order: bottom row first, each row from the right.
-- Returns nil when that can't be done (no free column), to leave the game's layout.
function BagButtons.Plan(items, bagButtons, grid, rightEnd)
    local columns = grid.columns
    local function anchorAt(row, column)   -- column 0 at the right
        local first = grid.first
        return { first[1], first[2], first[3], first[4] + column * grid.columnStep, first[5] + row * grid.rowStep }
    end
    local function freeColumns(withRightEnd)
        local free = {}
        for column = withRightEnd and 1 or 0, columns - 1 - #bagButtons do free[#free + 1] = column end
        return free
    end
    local free = freeColumns(rightEnd ~= nil)
    if rightEnd and #free == 0 then
        -- No cell to spare on the bag row: it stays among the items.
        local withIt = {}
        for _, frame in ipairs(items) do withIt[#withIt + 1] = frame end
        withIt[#withIt + 1] = rightEnd
        items, rightEnd = withIt, nil
        free = freeColumns(false)
    end
    if #free == 0 then return nil end
    local isFree = {}
    for _, column in ipairs(free) do isFree[column] = true end
    local itemRows = math.max(0, math.ceil((#items - #free) / columns))
    local leftOver = #items - (columns - #free) * itemRows   -- for the free columns
    if leftOver < 0 then return nil end
    local cells = {}
    for row = 0, itemRows - 1 do
        for column = 0, columns - 1 do
            if not isFree[column] then cells[#cells + 1] = { row = row, column = column } end
        end
    end
    for row = 0, itemRows do
        for _, column in ipairs(free) do
            if leftOver > 0 then
                cells[#cells + 1] = { row = row, column = column }
                leftOver = leftOver - 1
            end
        end
    end
    table.sort(cells, function(first, second)
        if first.row ~= second.row then return first.row < second.row end
        return first.column < second.column
    end)
    local plan = {}
    for i, frame in ipairs(items) do
        plan[#plan + 1] = { frame = frame, anchor = anchorAt(cells[i].row, cells[i].column) }
    end
    for i, button in ipairs(bagButtons) do
        plan[#plan + 1] = { frame = button, anchor = anchorAt(itemRows, columns - i) }
    end
    if rightEnd then plan[#plan + 1] = { frame = rightEnd, anchor = anchorAt(itemRows, 0) } end
    return plan, itemRows + 1
end

local function canMove(frame)
    if frame:IsForbidden() then return false end
    return not (InCombatLockdown() and frame:IsProtected())
end

-- The window's height for that many rows: the game's, plus or minus the rows
-- that differ from what it made.
local function fitHeight(window, rows, grid)
    if not gameHeight then return end
    local height = gameHeight + (rows - grid.rows) * math.abs(grid.rowStep)
    if math.abs(window:GetHeight() - height) < 0.5 then return end
    window:SetHeight(height)
    local nineSlice = rawget(_G, "NineSliceUtil")
    if type(nineSlice) == "table" and type(nineSlice.UpdateCornerCropping) == "function" then
        pcall(nineSlice.UpdateCornerCropping, window, height)
    end
end

-- After the game sized the window: its height, kept to add our rows to.
local function afterFrameSize(window)
    gameHeight = window:GetHeight()
end

-- After the game laid the window out: items closed up, bag buttons on the top row.
local function afterLayout(window)
    if not BagLayout.GetSettings().enabled then return end
    local bagBar = rawget(_G, "GamepadBagBar")
    if not bagBar or window:IsForbidden() then return end
    local placed = BagButtons.GameOrder(window, bagBar)
    if #placed == 0 then return end
    local frames = {}
    for i, entry in ipairs(placed) do frames[i] = entry.frame end
    local items, bagButtons = BagButtons.Split(frames, bagBar)
    if #bagButtons == 0 then return end
    local grid = BagButtons.Grid(window, placed)
    local hearthstone = BagLayout.GetSettings().hearthstone and BagLayout.Hearthstone.Find(items) or nil
    if hearthstone then
        local others = {}
        for _, frame in ipairs(items) do
            if frame ~= hearthstone then others[#others + 1] = frame end
        end
        items = others
    end
    local plan, rows = BagButtons.Plan(items, bagButtons, grid, hearthstone)
    if not plan then return end
    if InCombatLockdown() and window:IsProtected() then return end
    for _, entry in ipairs(plan) do
        if not canMove(entry.frame) then return end
    end
    for _, entry in ipairs(plan) do
        entry.frame:ClearAllPoints()
        entry.frame:SetPoint(unpack(entry.anchor))
    end
    fitHeight(window, rows, grid)
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
    if type(window.UpdateFrameSize) == "function" then hooksecurefunc(window, "UpdateFrameSize", afterFrameSize) end
    hooksecurefunc(window, "UpdateItemLayout", afterLayout)
end
