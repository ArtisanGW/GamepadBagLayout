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

local ADDON_FILES = { "GamepadBagLayout.lua", "Hearthstone.lua", "BagTint.lua", "BagButtons.lua", "Popup.lua", "RelatedAddons.lua" }

local function newFrame(name)
    local frame = { name = name, shown = true, protected = false, forbidden = false, scripts = {} }
    local noOps = { "SetSize", "SetWidth", "SetHeight", "SetFrameStrata", "SetToplevel",
        "EnableMouse", "SetMovable", "RegisterForDrag", "SetClampedToScreen", "SetFrameLevel", "SetText", "SetJustifyH",
        "SetFontObject", "SetAutoFocus", "SetMultiLine", "SetAllPoints", "SetTexture", "SetAtlas", "RegisterForClicks",
        "SetAttribute", "SetEnabled", "Enable", "Disable", "HighlightText", "SetFocus", "ClearFocus", "SetTextInsets",
        "SetWordWrap", "SetSpacing", "SetNormalFontObject", "SetHighlightFontObject", "SetShown", "EnableKeyboard",
        "SetPropagateKeyboardInput", "SetScale", "SetAlpha", "SetIgnoreParentScale", "SetFixedFrameStrata",
        "SetFixedFrameLevel", "SetDrawLayer", "SetColorTexture", "SetVertexColor", "SetTexCoord", "SetSnapToPixelGrid", "SetTexelSnappingBias" }
    for _, methodName in ipairs(noOps) do frame[methodName] = function() end end
    function frame:SetPoint(...)
        self.point = { ... }
        self.points = self.points or {}
        self.points[#self.points + 1] = { ... }
    end
    function frame:ClearAllPoints() self.point, self.points = nil, nil end
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
    function frame:CreateTexture()
        local texture = newFrame("texture")
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = texture
        return texture
    end
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
    -- The game's controller navigation: the button the cursor starts on.
    _G.SmartNavigation = {
        SetTargetButtonForFrame = function(_, frame, button) game.target = { frame = frame, button = button } end,
    }
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
    addon.Hearthstone.Watch()
end

-- The game picks the backpack's button to start on as the bags open
-- (ContainerFrame.lua:3564).
local function gamePicksStart()
    SmartNavigation:SetTargetButtonForFrame(ContainerFrameCombinedBags, game.buttons[0])
    return game.target.button
end

local function itemButton(bagID, slotID)
    for _, frame in ipairs(game.lastList) do
        if frame.bagID == bagID and frame.slotID == slotID and frame.name:find("item", 1, true) then return frame end
    end
end

-- Every button the window shows (items of collapsed bags aside).
local function shownFrames()
    local shown = {}
    for _, frame in ipairs(game.lastList) do
        local bagButton = frame.name:find("item", 1, true) and game.buttons[frame.bagID]
        if not (bagButton and bagButton.isCollapsed) then shown[#shown + 1] = frame end
    end
    return shown
end

-- The game's own cells, no more: positions 1 to the count shown, each used once.
local function checkSameCells(label)
    local shown = shownFrames()
    local used = {}
    for _, frame in ipairs(shown) do
        local at = position(frame)
        eq(used[at], nil, label .. ": cell " .. at .. " used once")
        used[at] = true
        eq(at >= 1 and at <= #shown, true, label .. ": " .. frame.name .. " in one of the game's cells")
    end
end

test("the bag buttons first: bottom right, left to right: backpack, bag 1 to 4, keyring", function()
    local addon = start()
    startWatching(addon)
    local list = layOut(true)   -- 40 items and 6 bag buttons: 46 cells
    local order = { 0, 1, 2, 3, 4, -2 }
    for i, bagID in ipairs(order) do eq(position(game.buttons[bagID]), 7 - i, "bag " .. bagID) end
    checkSameCells("with the keyring")
    eq(#list, 46, "every cell of the game's")
end)

test("the Hearthstone last: the top row's first slot from the left", function()
    local addon = start()
    startWatching(addon)
    game.hearthstoneAt = { 2, 3 }
    layOut(true, 17)   -- 41 items and 6 bag buttons: 47 cells, 7 on the top row
    eq(position(itemButton(2, 3)), 47, "the last cell")
    eq(cell(itemButton(2, 3)), 4, "on the top row")
    eq(position(game.buttons[0]), 6, "the backpack's still in the bottom row")
    checkSameCells("with the Hearthstone")
end)

test("Hearthstone setting off: it stays among the items, in the game's order", function()
    local addon = start({ saved = { enabled = true, hearthstone = false } })
    startWatching(addon)
    game.hearthstoneAt = { 4, 1 }   -- the game's first item
    layOut(true)
    eq(position(itemButton(4, 1)), 7, "where the game's order puts it, after the bags")
    eq(position(itemButton(4, 2)), 8, "the next one after it")
    game.hearthstoneAt = { 2, 3 }
    ContainerFrameCombinedBags:UpdateItemLayout()
    eq(position(itemButton(2, 3)) < 46, true, "not moved to the last cell")
end)

test("the cursor starts on the Hearthstone when the bags open", function()
    local addon = start()
    startWatching(addon)
    game.hearthstoneAt = { 2, 3 }
    layOut(true)
    eq(gamePicksStart(), itemButton(2, 3), "the Hearthstone")
end)

test("the cursor stays on the game's pick: in a fight, setting off, no Hearthstone", function()
    local addon = start()
    startWatching(addon)
    layOut(true)
    eq(gamePicksStart(), game.buttons[0], "no Hearthstone: the backpack's")
    game.hearthstoneAt = { 2, 3 }
    game.combat = true
    eq(gamePicksStart(), game.buttons[0], "in a fight: the backpack's")
    game.combat = false
    GamepadBagLayoutDB.hearthstone = false
    eq(gamePicksStart(), game.buttons[0], "setting off: the backpack's")
    GamepadBagLayoutDB.hearthstone = true
    SmartNavigation:SetTargetButtonForFrame(newFrame("another window"), game.buttons[1])
    eq(game.target.button, game.buttons[1], "another window's pick left alone")
end)

test("a tint behind the bags, from the backpack's to the last; none when off", function()
    local addon = start()
    startWatching(addon)
    layOut(true)
    eq(addon.BagTint.IsShown(), true, "shown")
    local tint = ContainerFrameCombinedBags.textures[1]
    eq(tint.points[1][2], game.buttons[0], "from the backpack's")
    eq(tint.points[2][2], game.buttons[-2], "to the keyring's")
    GamepadBagLayoutDB.enabled = false
    addon.BagButtons.Refresh()
    eq(addon.BagTint.IsShown(), false, "hidden when turned off")
    GamepadBagLayoutDB.enabled = true
    addon.BagButtons.Refresh()
    eq(#ContainerFrameCombinedBags.textures, 1, "one texture, made once")
end)

test("the tint's color and strength come from the settings", function()
    local addon = start()
    startWatching(addon)
    local tint
    layOut(true)
    tint = ContainerFrameCombinedBags.textures[1]
    local colored = {}
    tint.SetColorTexture = function(_, ...) colored = { ... } end
    GamepadBagLayoutDB.tintColor, GamepadBagLayoutDB.tintStrength = "ff00ff80", 50
    addon.BagTint.ApplyColor()
    eq(colored[1], 0, "red")
    eq(colored[2], 1, "green")
    eq(colored[3], 128 / 255, "blue")
    eq(colored[4], 0.5, "strength")
    GamepadBagLayoutDB.tintColor = "not a color"
    addon.BagTint.ApplyColor()
    eq(colored[3], 255 / 255, "a broken color falls back to the default blue")
end)

test("the color picker sets the tint's color and strength; Cancel puts them back", function()
    local addon = start()
    startWatching(addon)
    layOut(true)
    local picker = { rgb = { 0, 0, 0 }, alpha = 0 }
    function picker:SetupColorPickerAndShow(info)
        self.info = info
        self.rgb, self.alpha = { info.r, info.g, info.b }, info.opacity
        self.previous = { info.r, info.g, info.b, info.opacity }
    end
    function picker:GetColorRGB() return unpack(self.rgb) end
    function picker:GetColorAlpha() return self.alpha end
    function picker:GetPreviousValues() return unpack(self.previous) end
    _G.ColorPickerFrame = picker
    addon.BagTint.OpenPicker()
    eq(picker.info.hasOpacity, true, "with its opacity bar")
    eq(picker.info.opacity, 0.35, "the strength as opacity")
    picker.rgb, picker.alpha = { 1, 0, 0 }, 0.6
    picker.info.swatchFunc()
    picker.info.opacityFunc()
    eq(GamepadBagLayoutDB.tintColor, "ffff0000", "the color picked")
    eq(GamepadBagLayoutDB.tintStrength, 60, "the strength picked")
    picker.info.cancelFunc()
    eq(GamepadBagLayoutDB.tintColor, "ff409cff", "Cancel: the color back")
    eq(GamepadBagLayoutDB.tintStrength, 35, "Cancel: the strength back")
end)

test("items keep the game's order, closed up", function()
    local addon = start()
    startWatching(addon)
    local list = layOut(false)
    local previous = 5   -- after the 5 bag buttons
    for _, frame in ipairs(list) do
        if not frame.name:find("button", 1, true) then
            eq(position(frame), previous + 1, frame.name .. " right after the one before")
            previous = position(frame)
        end
    end
    eq(previous, 5 + 4 * 6 + 16, "every item")
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
    ContainerFrameCombinedBags:UpdateItemLayout()   -- now left out, at their old places
    local shownItems = 4 * 6 + 16 - 6
    eq(position(game.buttons[0]), 5, "the backpack's fifth from the right")
    eq(position(game.buttons[4]), 1, "bag 4's in the bottom right")
    eq(shownItems + 5, #shownFrames(), "every shown item counted")
    checkSameCells("bag 3 collapsed")
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
