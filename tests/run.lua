-- GamepadBagLayout against a small fake game: the Combined Backpack laid out by
-- AnchorUtil.GridLayout, the controller's bag buttons and the settings.
-- From GamepadBagLayout:  luajit tests/run.lua
-- GBL_TEST="part of a name" runs only the tests whose name holds it.
local failed, passed = 0, 0
local only = os.getenv("GBL_TEST")
local function test(name, fn)
    if only and not name:find(only, 1, true) then return end
    local ok, err = xpcall(fn, debug.traceback)
    if ok then passed = passed + 1 else failed = failed + 1; print("FAIL " .. name .. "\n" .. err) end
end
local function eq(actual, expected, message)
    if actual ~= expected then error((message or "") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2) end
end

local ADDON_FILES = { "GamepadBagLayout.lua", "Hearthstone.lua", "BagButtons.lua", "Popup.lua", "RelatedAddons.lua" }

local function newFrame(name)
    local frame = { name = name, shown = true, protected = false, forbidden = false, scripts = {} }
    local noOps = { "SetSize", "SetWidth", "SetHeight", "SetFrameStrata", "SetToplevel",
        "EnableMouse", "SetMovable", "RegisterForDrag", "SetClampedToScreen", "SetFrameLevel", "SetText", "SetJustifyH",
        "SetFontObject", "SetAutoFocus", "SetMultiLine", "SetAllPoints", "SetTexture", "SetAtlas", "RegisterForClicks",
        "SetAttribute", "SetEnabled", "Enable", "Disable", "HighlightText", "SetFocus", "ClearFocus", "SetTextInsets",
        "SetWordWrap", "SetSpacing", "SetNormalFontObject", "SetHighlightFontObject", "SetShown", "EnableKeyboard",
        "SetPropagateKeyboardInput", "SetScale", "SetAlpha", "SetIgnoreParentScale", "SetFixedFrameStrata",
        "SetFixedFrameLevel", "SetDrawLayer", "SetVertexColor", "SetTexCoord", "SetSnapToPixelGrid", "SetTexelSnappingBias" }
    for _, methodName in ipairs(noOps) do frame[methodName] = function() end end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:ClearAllPoints() self.point = nil end
    function frame:GetPoint() if self.point then return unpack(self.point) end end
    function frame:RegisterEvent(event) self.events = self.events or {}; self.events[event] = true end
    function frame:UnregisterEvent(event) if self.events then self.events[event] = nil end end
    function frame:SetScript(script, handler) self.scripts[script] = handler end
    function frame:HookScript() end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    function frame:IsShown() return self.shown end
    function frame:IsForbidden() return self.forbidden end
    function frame:IsProtected() return self.protected end
    function frame:GetWidth() return 37 end
    function frame:GetHeight() return 37 end
    function frame:GetStringHeight() return 14 end
    function frame:GetText() return "" end
    function frame:CreateFontString() return newFrame() end
    function frame:CreateTexture() return newFrame() end
    return frame
end

local game

-- One bag's items (count), as the game names them: "bag2 item 3".
local function items(bagName, count)
    local list = {}
    for i = 1, count do
        list[i] = newFrame(bagName .. " item " .. i)
        list[i].bagID = tonumber(bagName:match("%-?%d+"))
        list[i].slotID = i
        list[i].GetID = function(self) return self.slotID end
    end
    return list
end

-- The game's own list, in its order (ContainerFrame.lua:1080): each bag from the
-- highest, its items then its button; the keyring (collapsed) first.
-- backpackSize: the backpack's slots (16 by default); bags 1 to 4 have 6.
local function gameList(withKeyring, backpackSize)
    local list = {}
    local function add(frames) for _, frame in ipairs(frames) do list[#list + 1] = frame end end
    if withKeyring then add({ game.buttons[-2] }) end
    for bagID = 4, 0, -1 do
        add(items("bag" .. bagID, bagID == 0 and (backpackSize or 16) or 6))
        add({ game.buttons[bagID] })
    end
    return list
end

local function boot(options)
    options = options or {}
    game = { combat = false }
    _G.GamepadBagLayoutDB = options.saved
    _G.InCombatLockdown = function() return game.combat end
    _G.CreateFrame = function(_, name) local frame = newFrame(name); if name then _G[name] = frame end return frame end
    _G.UIParent = newFrame("UIParent")
    _G.SlashCmdList = {}
    _G.Settings = nil
    _G.C_AddOns = nil
    _G.geterrorhandler = function() return function(problem) error(problem) end end
    _G.hooksecurefunc = function(owner, name, hook)
        local original = owner[name]
        owner[name] = function(...) local results = { original(...) }; hook(...); return unpack(results) end
    end
    -- game.hearthstoneAt = { bagID, slotID }: where the Hearthstone is.
    _G.C_Container = {
        GetContainerItemID = function(bagID, slotID)
            local at = game.hearthstoneAt
            if at and at[1] == bagID and at[2] == slotID then return 6948 end
            return 1000 + slotID
        end,
    }
    _G.NUM_TOTAL_BAG_FRAMES = 4
    _G.KEYRING_CONTAINER = -2
    -- The game's grid (AnchorUtil.lua:122): 10 a row from the bottom right, 42 apart,
    -- anchored as on the forever client: to the top right of a frame along the
    -- window's bottom (its money bar), not to the window.
    _G.AnchorUtil = {
        GridLayout = function(frames, anchor, layout)
            game.layouts = (game.layouts or 0) + 1
            for i, frame in ipairs(frames) do
                local row, column = math.floor((i - 1) / layout.stride), (i - 1) % layout.stride
                frame:ClearAllPoints()
                frame:SetPoint("BOTTOMRIGHT", anchor.relativeTo, "TOPRIGHT", -column * 42, 4 + row * 42)
            end
        end,
    }
    local window = newFrame("ContainerFrameCombinedBags")
    _G.ContainerFrameCombinedBags = window
    game.buttons = {}
    for _, bagID in ipairs({ -2, 0, 1, 2, 3, 4 }) do
        game.buttons[bagID] = newFrame("bag button " .. bagID)
        game.buttons[bagID].bagID = bagID
    end
    game.buttons[-2].isCollapsed = true
    _G.STARTING_BAG_INDEX, _G.ENDING_BAG_INDEX = -2, 4
    _G.GamepadBagBar = { GetBagButton = function(_, bagID) return game.buttons[bagID] end }
    game.moneyBar = newFrame("money bar")
    function window:GetInitialItemAnchor() return { relativeTo = game.moneyBar } end
    function window:GetAnchorLayout() return { stride = 10 } end
    function window:GetColumns() return 10 end
    -- As the game counts them on the controller UI (ContainerFrame.lua:908): the
    -- items shown plus a cell for each bag (7 here).
    function window:GetRows()
        local shownItems = 0
        for _, itemButton in self:EnumerateValidItems() do
            local bagButton = game.buttons[itemButton.bagID]
            if not (bagButton and bagButton.isCollapsed) then shownItems = shownItems + 1 end
        end
        return math.ceil((shownItems + 7) / 10)
    end
    function window:UpdateFrameSize() self.height = self:GetRows() * 42 + 100 end
    function window:GetHeight() return self.height end
    function window:SetHeight(height) self.height = height end
    function window:EnumerateValidItems()
        local itemButtons = {}
        for _, frame in ipairs(game.lastList or {}) do
            if frame.name:find("item", 1, true) then itemButtons[#itemButtons + 1] = frame end
        end
        return ipairs(itemButtons)
    end
    -- The game's layout: its list, in its order, on the grid; a collapsed bag's
    -- items left out (and left where they were).
    function window:UpdateItemLayout()
        local shown = {}
        for _, frame in ipairs(game.lastList) do
            local bagButton = frame.name:find("item", 1, true) and game.buttons[frame.bagID]
            if not (bagButton and bagButton.isCollapsed) then shown[#shown + 1] = frame end
        end
        AnchorUtil.GridLayout(shown, self:GetInitialItemAnchor(), self:GetAnchorLayout())
    end
    for _, fileName in ipairs(ADDON_FILES) do
        local chunk = assert(loadfile(fileName))
        chunk("GamepadBagLayout")
    end
    return _G.GamepadBagLayout
end

-- The game lays the window out (its list in its order).
local function layOut(withKeyring, backpackSize)
    game.lastList = gameList(withKeyring, backpackSize)
    ContainerFrameCombinedBags:UpdateFrameSize()
    ContainerFrameCombinedBags:UpdateItemLayout()
    return game.lastList
end

-- A frame's place in the grid, 1 at the bottom right.
local function position(frame)
    local _, _, _, x, y = frame:GetPoint()
    return math.floor((y - 4) / 42 + 0.5) * 10 + math.floor(-x / 42 + 0.5) + 1
end

-- Its row (0 at the bottom) and column (0 at the right).
local function cell(frame)
    local index = position(frame) - 1
    return math.floor(index / 10), index % 10
end

local function start(options)
    return boot(options)
end

-- The addon's ADDON_LOADED handler runs from its event frame; the tests call
-- its watch directly, as that handler does.
local function startWatching(addon)
    addon.GetSettings()
    addon.BagButtons.Watch()
end

test("the bag buttons get the top row, left to right: backpack, bag 1 to 4, keyring", function()
    local addon = start()
    startWatching(addon)
    layOut(true)   -- 40 items: 4 rows; the game made 5
    local order = { 0, 1, 2, 3, 4, -2 }
    for i, bagID in ipairs(order) do
        local row, column = cell(game.buttons[bagID])
        eq(row, 4, "bag " .. bagID .. " on the top row")
        eq(column, 10 - i, "bag " .. bagID .. " at its place from the left")
    end
    eq(ContainerFrameCombinedBags:GetHeight(), 5 * 42 + 100, "the game's height: the row was there")
end)

-- Every button the window shows (items of collapsed bags aside), by column
-- (0 at the right): its rows from the bottom.
local function columnsOfRows()
    local shown = {}
    for _, frame in ipairs(game.lastList) do
        local bagButton = frame.name:find("item", 1, true) and game.buttons[frame.bagID]
        if not (bagButton and bagButton.isCollapsed) then shown[#shown + 1] = frame end
    end
    local columns = {}
    for _, frame in ipairs(shown) do
        local row, column = cell(frame)
        columns[column] = columns[column] or {}
        table.insert(columns[column], row)
    end
    return columns
end

-- What the controller needs (SmartNavigation.lua:1399): no hole in a column.
local function checkNoHoles(label)
    for column, rows in pairs(columnsOfRows()) do
        table.sort(rows)
        for i, row in ipairs(rows) do eq(row, i - 1, label .. ": column " .. column .. " has no hole") end
    end
end

-- The game's grid move to the right (SmartNavigation.lua:1399-1428, height
-- compensation on, the wrap left out): next column, same place from the bottom.
local function rightOf(frame)
    local byColumn = {}
    for _, other in ipairs(game.lastList) do
        local bagButton = other.name:find("item", 1, true) and game.buttons[other.bagID]
        if not (bagButton and bagButton.isCollapsed) then
            local row, column = cell(other)
            byColumn[column] = byColumn[column] or {}
            table.insert(byColumn[column], { frame = other, row = row })
        end
    end
    for _, entries in pairs(byColumn) do table.sort(entries, function(first, second) return first.row > second.row end) end
    local _, column = cell(frame)
    local current, next = byColumn[column], byColumn[column - 1]
    if not next then return nil end
    for index, entry in ipairs(current) do
        if entry.frame == frame then
            local target = next[index + (#next - #current)]
            return target and target.frame
        end
    end
end

test("no column has a hole, whatever the backpack's size", function()
    for backpackSize = 1, 40 do
        for _, hearthstone in ipairs({ false, true }) do
            local addon = start()
            startWatching(addon)
            game.hearthstoneAt = hearthstone and { 0, 1 } or nil
            layOut(true, backpackSize)
            local label = backpackSize .. " slots" .. (hearthstone and ", Hearthstone" or "")
            checkNoHoles(label)
            local bagRow = cell(game.buttons[0])
            for _, rows in pairs(columnsOfRows()) do
                for _, row in ipairs(rows) do eq(row <= bagRow, true, label .. ": nothing above the bag row") end
            end
        end
    end
end)

test("right along the bag row: bag after bag (the hole seen in game)", function()
    local addon = start()
    startWatching(addon)
    game.hearthstoneAt = { 2, 3 }
    layOut(true, 23)   -- 47 items, 46 without the Hearthstone: the last row not full
    local order = { 0, 1, 2, 3, 4, -2 }
    for i = 1, #order - 1 do
        eq(rightOf(game.buttons[order[i]]), game.buttons[order[i + 1]], "right of bag " .. order[i])
    end
end)

test("the window's height follows the rows taken", function()
    local addon = start()
    startWatching(addon)
    layOut(true, 20)   -- 44 items: the game makes 6 rows (44 + 7 cells), 5 are enough
    eq(cell(game.buttons[0]), 4, "the bag row is the fifth")
    eq(ContainerFrameCombinedBags:GetHeight(), 6 * 42 + 100 - 42, "one row shorter")
    ContainerFrameCombinedBags:UpdateFrameSize()
    ContainerFrameCombinedBags:UpdateItemLayout()
    eq(ContainerFrameCombinedBags:GetHeight(), 6 * 42 + 100 - 42, "laid out again: the same")
end)

local function itemButton(bagID, slotID)
    for _, frame in ipairs(game.lastList) do
        if frame.bagID == bagID and frame.slotID == slotID and frame.name:find("item", 1, true) then return frame end
    end
end

test("the Hearthstone goes at the right end of the bag row", function()
    local addon = start()
    startWatching(addon)
    game.hearthstoneAt = { 2, 3 }
    layOut(true)   -- 40 items, 39 without it: 4 rows; the game made 5
    local row, column = cell(itemButton(2, 3))
    eq(row, 4, "on the bag row")
    eq(column, 0, "at its right end")
    eq(cell(game.buttons[0]), 4, "the bags still on that row")
    checkNoHoles("with the Hearthstone")
end)

test("Hearthstone setting off: it stays among the items", function()
    local addon = start({ saved = { enabled = true, hearthstone = false } })
    startWatching(addon)
    game.hearthstoneAt = { 2, 3 }
    layOut(true)
    eq(position(itemButton(2, 3)) <= 40, true, "among the items")
end)

test("no Hearthstone in the bags: the bag row as before", function()
    local addon = start()
    startWatching(addon)
    layOut(true)
    local _, column = cell(game.buttons[-2])
    eq(column, 4, "the keyring sixth from the left")
end)

test("items keep the game's order, closed up", function()
    local addon = start()
    startWatching(addon)
    local list = layOut(false)
    local previous = 0
    for _, frame in ipairs(list) do
        if not frame.name:find("button", 1, true) then
            eq(position(frame) > previous, true, frame.name .. " after the one before")
            previous = position(frame)
        end
    end
end)

test("turned off: the game's own layout stays", function()
    local addon = start({ saved = { enabled = false } })
    startWatching(addon)
    local list = layOut(true)
    for i, frame in ipairs(list) do eq(position(frame), i, frame.name) end
end)

test("turning it off lays the window out again as the game does", function()
    local addon = start()
    startWatching(addon)
    local list = layOut(true, 17)
    GamepadBagLayoutDB.enabled = false
    addon.BagButtons.Refresh()
    for i, frame in ipairs(list) do eq(position(frame), i, frame.name) end
    eq(ContainerFrameCombinedBags:GetHeight(), 5 * 42 + 100, "the game's height again")
end)

test("items of a collapsed bag, which the game leaves out, aren't counted", function()
    local addon = start()
    startWatching(addon)
    layOut(false)   -- bag 3's items placed once
    game.buttons[3].isCollapsed = true
    ContainerFrameCombinedBags:UpdateFrameSize()
    ContainerFrameCombinedBags:UpdateItemLayout()   -- now left out, at their old places
    local shownItems = 4 * 6 + 16 - 6   -- 34: 4 rows; the game made 5 (34 + 7)
    for i = 1, #game.lastList do
        local frame = game.lastList[i]
        if frame.name:find("item", 1, true) and frame.bagID ~= 3 then
            eq(position(frame) <= shownItems, true, frame.name .. " among the shown items")
        end
    end
    checkNoHoles("bag 3 collapsed")
    eq(cell(game.buttons[0]), 3, "the bag row on top: 34 items take 3 rows and the free columns")
end)

test("a protected button in a fight: nothing moves", function()
    local addon = start()
    startWatching(addon)
    game.combat = true
    game.buttons[1].protected = true
    local list = layOut(true)
    for i, frame in ipairs(list) do eq(position(frame), i, frame.name) end
end)

test("watching twice hooks once", function()
    local addon = start()
    startWatching(addon)
    addon.BagButtons.Watch()
    layOut(true)
    eq(addon.BagButtons.regroupedCount, 1, "laid out again once")
end)

test("saved keys the addon doesn't use are dropped", function()
    local addon = start({ saved = { enabled = false, old = 1 } })
    local settings = addon.GetSettings()
    eq(settings.old, nil, "dropped")
    eq(settings.enabled, false, "kept")
end)

print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
