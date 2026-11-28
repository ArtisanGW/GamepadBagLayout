-- Debug only, not in the release zip (.pkgmeta ignore, toc do-not-package).
-- Records where the controller's cursor goes in the bag window, for a D-pad
-- test driven from outside (DevTools/virtual_pad.py): each button it lands on
-- (with its place in the game's navigation grid, SmartNavigation.lua:1332
-- UpdateGrid, forever branch), the grid itself, and the controller button that
-- opens the game's wheel (OPENRADIAL, Blizzard_Gamepad/Bindings.xml:2), and
-- each time the game moves the cursor, who moved it.
-- Kept in GamepadBagLayoutDebugDB, written to disk on /reload.
-- Once per RUN_ID, after login: a box on screen says which button opens the
-- wheel; once the bags open, a timer runs for the test, then the reload box.
local BagLayout = _G.GamepadBagLayout

local Debug = { RUN_ID = 5, TEST_SECONDS = 50, SECONDS_BEFORE_GRID = 0.5 }
BagLayout.Debug = Debug

local HEARTHSTONE_ITEM_ID = 6948

local function store()
    if type(GamepadBagLayoutDebugDB) ~= "table" then GamepadBagLayoutDebugDB = {} end
    return GamepadBagLayoutDebugDB
end

local function bagWindow() return rawget(_G, "ContainerFrameCombinedBags") end

local function navigation() return rawget(_G, "SmartNavigation") end

local function describe(button)
    if not button then return "none" end
    local window = bagWindow()
    if window and button == window.AddSlotsButton then return "AddSlotsButton" end
    local bagBar = rawget(_G, "GamepadBagBar")
    if bagBar then
        for bagID = -2, 6 do
            local succeeded, bagButton = pcall(bagBar.GetBagButton, bagBar, bagID)
            if succeeded and bagButton == button then return "bag button " .. bagID end
        end
    end
    if button.bagID and type(button.GetID) == "function" then
        local slotID = button:GetID()
        local itemID = C_Container.GetContainerItemID(button.bagID, slotID)
        local locked = type(button.IsExtended) == "function" and button:IsExtended()
        local contents = itemID == HEARTHSTONE_ITEM_ID and "Hearthstone" or (itemID and ("item " .. itemID) or "empty")
        return string.format("bag %d slot %d %s%s", button.bagID, slotID, contents, locked and " locked" or "")
    end
    return button:GetName() or button:GetObjectType()
end

local function activeGrid()
    local smartNavigation = navigation()
    local activeInfo = smartNavigation and smartNavigation.activeInfo
    local window = bagWindow()
    if not (activeInfo and window and activeInfo.frame == window) then return nil end
    return activeInfo.grid
end

local function gridPlace(grid, button)
    if not (grid and button) then return "" end
    for columnIndex, column in ipairs(grid) do
        for rowIndex, gridButton in ipairs(column) do
            if gridButton == button then
                return string.format(" [column %d/%d, row %d/%d]", columnIndex, #grid, rowIndex, #column)
            end
        end
    end
    return " [not in the grid]"
end

local function recordGrid(run, grid)
    local columns = {}
    for columnIndex, column in ipairs(grid) do
        local names = {}
        for rowIndex, button in ipairs(column) do names[rowIndex] = describe(button) end
        columns[columnIndex] = string.format("column %d (%d): %s", columnIndex, #column, table.concat(names, " | "))
    end
    run.grids[#run.grids + 1] = columns
end

local startTime
local function note(run, text)
    run.events[#run.events + 1] = string.format("%5.2f %s", GetTime() - startTime, text)
end

local box, boxText
local function showBox(text)
    if not box then
        box = CreateFrame("Frame", nil, UIParent, "TooltipBackdropTemplate")
        box:SetFrameStrata("DIALOG")
        box:SetSize(420, 44)
        box:SetPoint("TOP", UIParent, "TOP", 0, -40)
        boxText = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        boxText:SetPoint("CENTER")
    end
    boxText:SetText(text)
    box:Show()
end

local function finish(run)
    run.done = true
    note(run, "test over")
    if box then box:Hide() end
    BagLayout.Popup.Show({
        text = "Bag test done. Reload saves the findings.",
        buttons = { { text = "Reload", reload = true }, { text = "Later" } },
    })
end

local function startTimer(run)
    local secondsLeft = Debug.TEST_SECONDS
    showBox(string.format("Bag test: %d s left", secondsLeft))
    C_Timer.NewTicker(1, function(ticker)
        secondsLeft = secondsLeft - 1
        if secondsLeft <= 0 then
            ticker:Cancel()
            finish(run)
        else
            showBox(string.format("Bag test: %d s left", secondsLeft))
        end
    end)
end

-- Each button the game moves the controller's cursor to, with the calls that
-- led there (file:line, above SmartNavigation:SelectButton) and whether the
-- button it left had a settled place on screen (IsRectValid: without one,
-- SmartNavigation.lua:1489 sends the cursor to the window's top-left button).
local function watchSelections(run)
    local smartNavigation = navigation()
    if not smartNavigation or Debug.watchingSelections then return end
    Debug.watchingSelections = true
    local previous = nil
    hooksecurefunc(smartNavigation, "SelectButton", function(_, button)
        if run.done then return end
        local callers = {}
        for line in debugstack(2, 6, 0):gmatch("[^\n]+") do
            local file, lineNumber = line:match("([%w_]+%.lua)[\"%]]*:(%d+)")
            if file then callers[#callers + 1] = file .. ":" .. lineNumber end
        end
        local settled = previous and tostring(previous:IsRectValid()) or "-"
        note(run, string.format("select %s (left %s, its rect valid: %s) from %s",
            describe(button), describe(previous), settled, table.concat(callers, " < ")))
        previous = button
    end)
end

function Debug.Start()
    local saved = store()
    saved.runId = Debug.RUN_ID
    local context = Enum.BindingContext and Enum.BindingContext.GamepadModeInGameCore
    local radialKey1, radialKey2 = GetBindingKey("OPENRADIAL", nil, context)
    local run = { when = date("%Y-%m-%d %H:%M:%S"), radialKeys = { radialKey1, radialKey2 }, events = {}, grids = {} }
    saved.run = run
    startTime = GetTime()
    showBox("Bag test: open the bags from the wheel (" .. tostring(radialKey1) .. ")")

    watchSelections(run)
    local watcher = CreateFrame("Frame")
    local lastButton, lastGrid, radialShown, bagsShown, timerStarted = nil, nil, false, false, false
    watcher:SetScript("OnUpdate", function(self)
        if run.done then self:SetScript("OnUpdate", nil) return end
        local radial = rawget(_G, "GamepadRadial")
        local radialNow = radial and radial:IsShown() or false
        if radialNow ~= radialShown then
            radialShown = radialNow
            note(run, radialNow and "wheel open" or "wheel closed")
        end
        local window = bagWindow()
        local bagsNow = window and window:IsShown() or false
        if bagsNow ~= bagsShown then
            bagsShown = bagsNow
            note(run, bagsNow and "bags open" or "bags closed")
            if bagsNow and not timerStarted then
                timerStarted = true
                startTimer(run)
            end
        end
        local grid = activeGrid()
        if grid and grid ~= lastGrid and GetTime() - startTime > Debug.SECONDS_BEFORE_GRID then
            lastGrid = grid
            recordGrid(run, grid)
            note(run, "grid " .. #run.grids .. ": " .. #grid .. " columns")
        end
        local smartNavigation = navigation()
        local button = smartNavigation and smartNavigation:GetCurrentButton()
        if button ~= lastButton then
            lastButton = button
            note(run, "cursor: " .. describe(button) .. gridPlace(grid, button))
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", function()
    events:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if store().runId ~= Debug.RUN_ID then C_Timer.After(1, Debug.Start) end
end)
