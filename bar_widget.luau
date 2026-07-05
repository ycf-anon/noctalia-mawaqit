-- bar_widget.luau — Mawaqit bar widget
-- Reads prayer data from the service via state store.
-- onClick cycles display mode: countdown → static time → prayer name only
-- Right click → toggle panel

-- ── Config ────────────────────────────────────────────────────────────────────

local showCountdown  = noctalia.getConfig("showCountdown")  or true
local showElapsed    = noctalia.getConfig("showElapsed")    or false
local hidePrayerName = noctalia.getConfig("hidePrayerName") or false
local widgetIcon     = noctalia.getConfig("widgetIcon")     or "building-mosque"
local dynamicIcon    = noctalia.getConfig("dynamicIcon")    or false
local textColor      = noctalia.getConfig("textColor")      or "on_surface"
local iconColor      = noctalia.getConfig("iconColor")      or "on_surface"
local activeColor    = noctalia.getConfig("activeColor")    or "primary"

-- ── Constants ─────────────────────────────────────────────────────────────────

local PRAYER_ICONS = {
    Fajr    = "moon-stars",
    Sunrise = "sunrise",
    Dhuhr   = "sun",
    Asr     = "sun-low",
    Maghrib = "sunset",
    Isha    = "moon",
}

local MODE_COUNTDOWN = 1
local MODE_STATIC    = 2
local MODE_NAME_ONLY = 3

-- ── State ─────────────────────────────────────────────────────────────────────

local prayers      = {}
local tomorrowFajr = nil
local displayMode  = MODE_COUNTDOWN
local hasData      = false
local errorMsg     = ""

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function nowSeconds()
    local t = os.date("*t")
    return t.hour * 3600 + t.min * 60 + t.sec
end

local function formatCountdown(secs)
    if secs < 0 then secs = 0 end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    local s = secs % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    else
        return string.format("%d:%02d", m, s)
    end
end

local function formatTime(secs)
    local h = math.floor(secs / 3600) % 24
    local m = math.floor((secs % 3600) / 60)
    return string.format("%02d:%02d", h, m)
end

local function getIcon(prayerName)
    if dynamicIcon and prayerName and PRAYER_ICONS[prayerName] then
        return PRAYER_ICONS[prayerName]
    end
    return widgetIcon ~= "" and widgetIcon or "building-mosque"
end

local function setColors(isActive)
    if isActive then
        local ac = activeColor ~= "" and activeColor or "primary"
        barWidget.setColor(ac)
        barWidget.setGlyphColor(ac)
    else
        barWidget.setColor(textColor ~= "" and textColor or "on_surface")
        barWidget.setGlyphColor(iconColor ~= "" and iconColor or "on_surface")
    end
end

-- ── Prayer logic ──────────────────────────────────────────────────────────────

local function findCurrentPrayer()
    if #prayers == 0 then return nil, nil, nil, nil end
    local now = nowSeconds()
    local currentIdx = nil
    for i, p in ipairs(prayers) do
        if now >= p.seconds then currentIdx = i end
    end

    local nextIdx, secondsToNext, secondsElapsed

    if currentIdx == nil then
        nextIdx        = 1
        secondsToNext  = prayers[1].seconds - now
        secondsElapsed = nil
    elseif currentIdx == #prayers then
        nextIdx        = nil
        secondsElapsed = now - prayers[currentIdx].seconds
        if tomorrowFajr and tomorrowFajr > 0 then
            secondsToNext = (86400 - now) + tomorrowFajr
        else
            secondsToNext = nil
        end
    else
        nextIdx        = currentIdx + 1
        secondsToNext  = prayers[nextIdx].seconds - now
        secondsElapsed = now - prayers[currentIdx].seconds
    end

    return currentIdx, nextIdx, secondsToNext, secondsElapsed
end

-- ── Display ───────────────────────────────────────────────────────────────────

local function updateDisplay()
    if not hasData then
        barWidget.setGlyph(widgetIcon ~= "" and widgetIcon or "building-mosque")
        barWidget.setText(errorMsg ~= "" and "Error" or "Loading")
        barWidget.setColor("on_surface")
        barWidget.setGlyphColor("on_surface")
        barWidget.setTooltip(errorMsg ~= "" and errorMsg or "Fetching prayer times…")
        return
    end

    local currentIdx, nextIdx, secondsToNext, secondsElapsed = findCurrentPrayer()

    local displayPrayer, isActive, timeStr = nil, false, ""

    -- Elapsed mode
    local showingElapsed = false
    if showElapsed and currentIdx ~= nil and secondsElapsed ~= nil then
        local cap = secondsToNext or 3600
        if secondsElapsed <= 3600 and secondsElapsed <= cap then
            showingElapsed = true
        end
    end

    if nextIdx ~= nil then
        displayPrayer = prayers[nextIdx].name
        local nextSecs = prayers[nextIdx].seconds

        if showingElapsed and currentIdx ~= nil then
            displayPrayer = prayers[currentIdx].name
            isActive = true
            if displayMode == MODE_COUNTDOWN then
                timeStr = "+" .. formatCountdown(secondsElapsed)
            elseif displayMode == MODE_STATIC then
                timeStr = formatTime(prayers[currentIdx].seconds)
            end
        elseif secondsToNext ~= nil and secondsToNext <= 60 then
            isActive = true
            if displayMode ~= MODE_NAME_ONLY then timeStr = "now" end
        else
            if displayMode == MODE_COUNTDOWN and secondsToNext then
                timeStr = formatCountdown(secondsToNext)
            elseif displayMode == MODE_STATIC then
                timeStr = formatTime(nextSecs)
            end
        end
    else
        displayPrayer = "Fajr"
        if showingElapsed and currentIdx ~= nil then
            isActive = true
            displayPrayer = prayers[currentIdx].name
            if displayMode == MODE_COUNTDOWN then
                timeStr = "+" .. formatCountdown(secondsElapsed)
            elseif displayMode == MODE_STATIC then
                timeStr = formatTime(prayers[currentIdx].seconds)
            end
        elseif secondsToNext ~= nil then
            if displayMode == MODE_COUNTDOWN then
                timeStr = formatCountdown(secondsToNext)
            elseif displayMode == MODE_STATIC then
                timeStr = tomorrowFajr and formatTime(tomorrowFajr) or "?"
            end
        end
    end

    -- Build label
    local label
    if displayMode == MODE_NAME_ONLY then
        label = displayPrayer or ""
    elseif hidePrayerName then
        label = timeStr
    else
        label = timeStr ~= "" and ((displayPrayer or "") .. "  " .. timeStr) or (displayPrayer or "")
    end

    barWidget.setGlyph(getIcon(displayPrayer))
    barWidget.setText(label)
    setColors(isActive)

    -- Tooltip
    if nextIdx ~= nil and secondsToNext ~= nil then
        barWidget.setTooltip({
            { key = "Next",  value = prayers[nextIdx].name },
            { key = "Time",  value = formatTime(prayers[nextIdx].seconds) },
            { key = "In",    value = formatCountdown(secondsToNext) },
        })
    elseif secondsToNext ~= nil and tomorrowFajr ~= nil then
        barWidget.setTooltip({
            { key = "Next",  value = "Fajr (tomorrow)" },
            { key = "Time",  value = formatTime(tomorrowFajr) },
            { key = "In",    value = formatCountdown(secondsToNext) },
        })
    end
end

-- ── State store watchers ──────────────────────────────────────────────────────

noctalia.state.watch("prayers", function(json)
    local ok, list = pcall(function() return noctalia.json.decode(json) end)
    if ok and list and #list > 0 then
        prayers = list
        hasData = true
        errorMsg = ""
    end
    updateDisplay()
end)

noctalia.state.watch("tomorrowFajr", function(val)
    tomorrowFajr = tonumber(val)
end)

noctalia.state.watch("error", function(json)
    local ok, msg = pcall(function() return noctalia.json.decode(json) end)
    if ok and msg and msg ~= "" then
        errorMsg = msg
        if not hasData then updateDisplay() end
    end
end)

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

noctalia.setUpdateInterval(1000)

function update()
    updateDisplay()
end

function onClick()
    if displayMode == MODE_COUNTDOWN then
        displayMode = MODE_STATIC
    elseif displayMode == MODE_STATIC then
        displayMode = MODE_NAME_ONLY
    else
        displayMode = MODE_COUNTDOWN
    end
    updateDisplay()
end

function onRightClick()
    noctalia.runAsync("noctalia msg panel-toggle ycf/mawaqit:panel")
end

function onIpc(event, payload)
    if event == "refresh" then
        noctalia.runAsync("noctalia msg plugin ycf/mawaqit:fetcher all refresh")
    elseif event == "mode" then
        if payload == "countdown"  then displayMode = MODE_COUNTDOWN
        elseif payload == "static" then displayMode = MODE_STATIC
        elseif payload == "name"   then displayMode = MODE_NAME_ONLY
        end
        updateDisplay()
    end
end

-- ── Init ──────────────────────────────────────────────────────────────────────

barWidget.setGlyph(widgetIcon ~= "" and widgetIcon or "building-mosque")
barWidget.setText("Loading")
barWidget.setColor("on_surface")
barWidget.setGlyphColor("on_surface")

-- Load any already-published state from service
local existing = noctalia.state.get("prayers")
if existing then
    local ok, list = pcall(function() return noctalia.json.decode(existing) end)
    if ok and list and #list > 0 then
        prayers = list
        hasData = true
    end
end

local existingTomorrow = noctalia.state.get("tomorrowFajr")
if existingTomorrow then tomorrowFajr = tonumber(existingTomorrow) end

updateDisplay()
