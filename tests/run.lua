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

local ADDON_FILES = { "GamepadBagLayout.lua", "BagButtons.lua", "Popup.lua", "RelatedAddons.lua" }

local function newFrame(name)
    local frame = { name = name, shown = true, protected = false, forbidden = false, scripts = {} }
    local noOps = { "SetPoint", "ClearAllPoints", "SetSize", "SetWidth", "SetHeight", "SetFrameStrata", "SetToplevel",
        "EnableMouse", "SetMovable", "RegisterForDrag", "SetClampedToScreen", "SetFrameLevel", "SetText", "SetJustifyH",
        "SetFontObject", "SetAutoFocus", "SetMultiLine", "SetAllPoints", "SetTexture", "SetAtlas", "RegisterForClicks",
        "SetAttribute", "SetEnabled", "Enable", "Disable", "HighlightText", "SetFocus", "ClearFocus", "SetTextInsets",
        "SetWordWrap", "SetSpacing", "SetNormalFontObject", "SetHighlightFontObject", "SetShown", "EnableKeyboard",
        "SetPropagateKeyboardInput", "SetScale", "SetAlpha", "SetIgnoreParentScale", "SetFixedFrameStrata",
        "SetFixedFrameLevel", "SetDrawLayer", "SetVertexColor", "SetTexCoord", "SetSnapToPixelGrid", "SetTexelSnappingBias" }
    for _, methodName in ipairs(noOps) do frame[methodName] = function() end end
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
    for i = 1, count do list[i] = newFrame(bagName .. " item " .. i) end
    return list
end

-- The game's own list, in its order (ContainerFrame.lua:1080): each bag from the
-- highest, its items then its button; the keyring (collapsed) first.
local function gameList(withKeyring)
    local list = {}
    local function add(frames) for _, frame in ipairs(frames) do list[#list + 1] = frame end end
    if withKeyring then add({ game.buttons[-2] }) end
    for bagID = 4, 0, -1 do
        add(items("bag" .. bagID, bagID == 0 and 16 or 6))
        add({ game.buttons[bagID] })
    end
    return list
end

local function boot(options)
    options = options or {}
    game = { positions = {}, combat = false }
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
    _G.NUM_TOTAL_BAG_FRAMES = 4
    _G.KEYRING_CONTAINER = -2
    -- Where each frame sits: its index in the last GridLayout that placed it.
    _G.AnchorUtil = {
        GridLayout = function(frames)
            game.layouts = (game.layouts or 0) + 1
            for i, frame in ipairs(frames) do game.positions[frame] = i end
        end,
    }
    _G.ContainerFrameCombinedBags = newFrame("ContainerFrameCombinedBags")
    game.anchor = { GetRelativeTo = function() return ContainerFrameCombinedBags end }
    game.buttons = {}
    for _, bagID in ipairs({ -2, 0, 1, 2, 3, 4 }) do game.buttons[bagID] = newFrame("bag button " .. bagID) end
    _G.GamepadBagBar = { GetBagButton = function(_, bagID) return game.buttons[bagID] end }
    function ContainerFrameCombinedBags:UpdateItemLayout()
        AnchorUtil.GridLayout(game.lastList, game.anchor, {})
    end
    for _, fileName in ipairs(ADDON_FILES) do
        local chunk = assert(loadfile(fileName))
        chunk("GamepadBagLayout")
    end
    return _G.GamepadBagLayout
end

-- The game lays the window out (its list in its order).
local function layOut(withKeyring)
    game.lastList = gameList(withKeyring)
    ContainerFrameCombinedBags:UpdateItemLayout()
    return game.lastList
end

local function position(frame) return game.positions[frame] end

local function start(options)
    return boot(options)
end

-- The addon's ADDON_LOADED handler runs from its event frame; the tests call
-- its watch directly, as that handler does.
local function startWatching(addon)
    addon.GetSettings()
    addon.BagButtons.Watch()
end

test("the bag buttons follow the backpack's, bag 1 first, then the keyring's", function()
    local addon = start()
    startWatching(addon)
    local list = layOut(true)
    local itemCount = #list - 6
    eq(position(game.buttons[0]), itemCount + 1, "the backpack's right after the last item")
    eq(position(game.buttons[1]), itemCount + 2, "bag 1 next")
    eq(position(game.buttons[2]), itemCount + 3, "bag 2")
    eq(position(game.buttons[3]), itemCount + 4, "bag 3")
    eq(position(game.buttons[4]), itemCount + 5, "bag 4")
    eq(position(game.buttons[-2]), itemCount + 6, "the keyring's last")
    eq(position(list[2]), 1, "the first item now first")
end)

test("items keep the game's order, closed up", function()
    local addon = start()
    startWatching(addon)
    local list = layOut(false)
    local previous = 0
    for _, frame in ipairs(list) do
        if not frame.name:find("button", 1, true) then
            eq(position(frame), previous + 1, frame.name .. " right after the one before")
            previous = position(frame)
        end
    end
    eq(previous, 4 * 6 + 16, "every item")
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
    local list = layOut(true)
    GamepadBagLayoutDB.enabled = false
    addon.BagButtons.Refresh()
    for i, frame in ipairs(list) do eq(position(frame), i, frame.name) end
end)

test("other windows' grids are left alone", function()
    local addon = start()
    startWatching(addon)
    local list = gameList(true)
    AnchorUtil.GridLayout(list, { GetRelativeTo = function() return newFrame("another window") end }, {})
    for i, frame in ipairs(list) do eq(position(frame), i, frame.name) end
end)

test("without the controller's bag buttons in the list, nothing moves", function()
    local addon = start()
    startWatching(addon)
    local list = items("bag0", 16)
    AnchorUtil.GridLayout(list, game.anchor, {})
    eq(game.layouts, 1, "laid out once, by the game")
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
    eq(game.layouts, 2, "the game's layout and ours, once")
end)

test("saved keys the addon doesn't use are dropped", function()
    local addon = start({ saved = { enabled = false, old = 1 } })
    local settings = addon.GetSettings()
    eq(settings.old, nil, "dropped")
    eq(settings.enabled, false, "kept")
end)

print(passed .. " passed, " .. failed .. " failed")
os.exit(failed == 0 and 0 or 1)
