-- Moves the bag buttons of the controller's Combined Backpack to the start of
-- its grid (the bottom row) and the Hearthstone to its end (the top), so the
-- window reads, top to bottom: the Hearthstone, the items, the locked slots, the bags.
-- With the controller UI on, the game puts one button per bag (its free slots,
-- its menu) into the window's grid,
-- each right after that bag's items (ContainerFrameMixin:UpdateItemLayout,
-- forever branch Blizzard_UIPanels_Game/Mainline/ContainerFrame.lua:1080-1105),
-- so they end up scattered among the items.
--
-- A post-hook on the window's own UpdateItemLayout runs once the game has laid
-- the grid out. The game's cells stay as they are, in its order (from the bottom
-- right, right to left, then up a row: ContainerFrameCombinedBagsMixin:
-- GetInitialItemAnchor, ContainerFrame.lua:3032); only who sits in them changes:
-- the bag buttons first, so they read left to right at the right end of the
-- bottom row (the backpack's, bag 1 and on, the reagent bag's, the keyring's),
-- then the backpack's slots locked until the account has an authenticator
-- (left of the bags, out of the way: the game puts them at the top), then the
-- items in the game's order, then the Hearthstone (Hearthstone.lua),
-- in the top row's first slot from the left. No cell is added
-- or left empty (a tint behind the bags sets them apart: BagTint.lua), so the
-- window keeps the game's size and the controller's grid
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

-- A backpack slot locked until the account has an authenticator: the game marks
-- it extended and shows a padlock on it (ContainerFrameItemButtonMixin:
-- UpdateExtended, ContainerFrame.lua:2024-2045).
local function isLockedSlot(frame)
    return type(frame.IsExtended) == "function" and frame:IsExtended() == true
end

-- The game's grid in its new order: the bag buttons, right to left, so they
-- read left to right in the window; the locked slots, next to them; the items
-- (in the game's order); then the Hearthstone (optional), last, so top left.
-- Also returns how many bag buttons lead the list.
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
    local ordered, lockedSlots, items = {}, {}, {}
    for _, frame in ipairs(frames) do
        if not isBagButton[frame] and frame ~= hearthstone then
            if isLockedSlot(frame) then
                lockedSlots[#lockedSlots + 1] = frame
            else
                items[#items + 1] = frame
            end
        end
    end
    for i = #bagButtons, 1, -1 do ordered[#ordered + 1] = bagButtons[i] end
    for _, frame in ipairs(lockedSlots) do ordered[#ordered + 1] = frame end
    for _, frame in ipairs(items) do ordered[#ordered + 1] = frame end
    if hearthstone and present[hearthstone] then ordered[#ordered + 1] = hearthstone end
    return ordered, #bagButtons
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

-- The game's "add an authenticator" button (the + on the locked slots,
-- ContainerFrameExtendedSlotPack, ContainerFrame.lua:2694-2726) sits across
-- the edge between two cells, so the controller's grid takes it for a column
-- of its own, one button tall: moving left or right into that column drops the
-- cursor onto it from any row (SmartNavigation.lua:1430-1461). While the
-- layout is on, the controller skips it, through the game's own mark
-- (SmartNavigation_MarkFrameIgnored, Utility.lua:46, which addons may set
-- outside a fight); the locked slots under it say the same in their tooltip,
-- and the mouse still clicks it. The mark is taken off when the layout is
-- turned off, unless the game had put it there itself.
local markedAddSlotsButton = nil

local function keepAddSlotsButtonOffGrid(window, layoutOn)
    local button = window.AddSlotsButton
    local markIgnored = rawget(_G, "SmartNavigation_MarkFrameIgnored")
    local clearIgnored = rawget(_G, "SmartNavigation_ClearIgnoreStatus")
    if not (button and markIgnored and clearIgnored) or InCombatLockdown() or button:IsForbidden() then return end
    if layoutOn and not markedAddSlotsButton and button.smartNavigationIgnored ~= true then
        markIgnored(button)
        markedAddSlotsButton = button
    elseif not layoutOn and markedAddSlotsButton then
        clearIgnored(markedAddSlotsButton)
        markedAddSlotsButton = nil
    end
end

local function canMove(frame)
    if frame:IsForbidden() then return false end
    return not (InCombatLockdown() and frame:IsProtected())
end

-- After the game laid the window out: the same cells, the bag buttons first
-- (bottom), the Hearthstone last (top).
local function afterLayout(window)
    BagLayout.BagTint.Hide()
    local layoutOn = BagLayout.GetSettings().enabled
    if not window:IsForbidden() then keepAddSlotsButtonOffGrid(window, layoutOn) end
    if not layoutOn then return end
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
    local ordered, bagCount = BagButtons.Reorder(frames, bagBar, hearthstone)
    if not ordered then return end
    if InCombatLockdown() and window:IsProtected() then return end
    for _, frame in ipairs(ordered) do
        if not canMove(frame) then return end
    end
    for i, frame in ipairs(ordered) do
        frame:ClearAllPoints()
        frame:SetPoint(unpack(placed[i].anchor))
    end
    -- The bags' tint, when they fit on the bottom row: from the backpack's (the
    -- last of them in the grid's order, so the leftmost) to the first.
    if math.abs(placed[1].anchor[5] - placed[bagCount].anchor[5]) < 0.5 then
        BagLayout.BagTint.Show(window, ordered[bagCount], ordered[1])
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
