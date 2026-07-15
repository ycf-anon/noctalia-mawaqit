-- service.luau — Mawaqit background fetcher
-- Runs as a singleton service, fetches prayer times from Aladhan API,
-- publishes to the plugin state store for the bar widget and panel to read.
--
-- State keys published:
--   prayers      JSON array of { name, time, seconds, azanPrayer }
--   tomorrowFajr seconds-since-midnight for tomorrow's Fajr (or "")
--   hijriDate    "DD MonthName YYYY AH" string
--   gregorianDate "DD Mon YYYY" string
--   hijriDay     number
--   hijriMonth   number
--   hijriYear    number
--   loadedDate   "YYYY-MM-DD" of loaded data
--   error        error message or ""

noctalia.setUpdateInterval(5000)

-- ── Config ────────────────────────────────────────────────────────────────────

local city           = noctalia.getConfig("city")           or "London"
local country        = noctalia.getConfig("country")        or "UK"
local method         = noctalia.getConfig("method")         or "3"
local methodCustomId = noctalia.getConfig("methodCustomId") or 19
local school         = noctalia.getConfig("school")         or "0"
local hijriDayOffset = noctalia.getConfig("hijriDayOffset") or 0
local tune           = noctalia.getConfig("tune")           or false
local tuneFajr       = noctalia.getConfig("tuneFajr")       or 0
local tuneDhuhr      = noctalia.getConfig("tuneDhuhr")      or 0
local tuneAsr        = noctalia.getConfig("tuneAsr")        or 0
local tuneMaghrib    = noctalia.getConfig("tuneMaghrib")    or 0
local tuneIsha       = noctalia.getConfig("tuneIsha")       or 0
local twelveHourFormat = noctalia.getConfig("twelveHourFormat") or false
local showNotifications = noctalia.getConfig("showNotifications") or true
local playAzan       = noctalia.getConfig("playAzan")       or false
local azanFile       = noctalia.getConfig("azanFile")       or "azan1.mp3"

-- ── State ─────────────────────────────────────────────────────────────────────

local PRAYER_NAMES = { "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha" }
local AZAN_PRAYERS = { true, false, true, true, true, true }

local loadedDate     = ""
local fetchPending   = false
local retryCount     = 0
local MAX_RETRIES    = 5
local retryTicks     = 0
local tomorrowFetched = false
local lastNotified   = ""
local lastAzanPlayed = ""

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function parseTime(str)
    if not str then return nil end
    local h, m = str:match("^(%d+):(%d+)")
    if not h then return nil end
    return tonumber(h) * 3600 + tonumber(m) * 60
end

local function parseTwelveHours(str)
    if not twelveHourFormat then return str end
    local h, m = str:match("^(%d+):(%d+)")
    if tonumber(h) < 12 then
        return string.format("%s:%s AM", h - 0, m)
    else
        return string.format("%s:%s PM", h - 12, m)
    end
end

local function todayStr()
    return os.date("%Y-%m-%d")
end

local function nowSeconds()
    local t = os.date("*t")
    return t.hour * 3600 + t.min * 60 + t.sec
end

local function applyTune(name, secs)
    if not tune then return secs end
    local offset = 0
    if     name == "Fajr"    then offset = tuneFajr
    elseif name == "Dhuhr"   then offset = tuneDhuhr
    elseif name == "Asr"     then offset = tuneAsr
    elseif name == "Maghrib" then offset = tuneMaghrib
    elseif name == "Isha"    then offset = tuneIsha
    end
    return secs + offset * 60
end

local function buildUrl(offsetDays)
    local m = method == "custom" and tostring(methodCustomId) or method
    local t = os.time() + (offsetDays or 0) * 86400
    local d = os.date("*t", t)
    local dateStr = string.format("%02d-%02d-%04d", d.day, d.month, d.year)
    return string.format(
        "https://api.aladhan.com/v1/timingsByCity/%s?city=%s&country=%s&method=%s&school=%s",
        dateStr,
        noctalia.string.urlEncode(city),
        noctalia.string.urlEncode(country),
        m, school
    )
end

-- ── JSON encode helpers (minimal, for state store) ────────────────────────────

local function jsonStr(s)
    s = tostring(s)
    s = s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
    return '"' .. s .. '"'
end

local function encodePrayers(list)
    local parts = {}
    for _, p in ipairs(list) do
        parts[#parts+1] = string.format(
            '{"name":%s,"time":%s,"seconds":%d,"azanPrayer":%s}',
            jsonStr(p.name), jsonStr(p.time), p.seconds,
            p.azanPrayer and "true" or "false"
        )
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

-- ── Fetch ─────────────────────────────────────────────────────────────────────

local function publishError(msg)
    noctalia.state.set("error", jsonStr(msg))
end

local function processPrayerData(data)
    if not data or data.code ~= 200 then
        publishError("API error")
        return false
    end
    local timings = data.data and data.data.timings
    if not timings then
        publishError("Parse error")
        return false
    end

    -- Build prayer list
    local prayers = {}
    for i, name in ipairs(PRAYER_NAMES) do
        local raw = timings[name]
        if raw then
            -- Strip DST annotation e.g. "05:23 (BST)"
            local clean = raw:match("^(%d+:%d+)") or raw
            local parsedTwelveHours = parseTwelveHours(clean)
            local secs = parseTime(clean)
            if secs then
                secs = applyTune(name, secs)
                prayers[#prayers+1] = {
                    name = name,
                    time = parsedTwelveHours,
                    seconds = secs,
                    azanPrayer = AZAN_PRAYERS[i],
                }
            end
        end
    end

    -- Hijri date
    local hijri = data.data.date and data.data.date.hijri
    local greg  = data.data.date and data.data.date.readable or ""
    local hijriDay   = 0
    local hijriMonth = 0
    local hijriYear  = 0
    local hijriDateStr = ""

    if hijri then
        hijriDay   = math.max(1, math.min(30, (tonumber(hijri.day) or 0) + hijriDayOffset))
        hijriMonth = hijri.month and hijri.month.number or 0
        hijriYear  = tonumber(hijri.year) or 0
        local monthEn = hijri.month and hijri.month.en or ""
        hijriDateStr = string.format("%d %s %d AH", hijriDay, monthEn, hijriYear)
    end

    -- Publish to state store
    noctalia.state.set("prayers",       encodePrayers(prayers))
    noctalia.state.set("hijriDate",     jsonStr(hijriDateStr))
    noctalia.state.set("gregorianDate", jsonStr(greg))
    noctalia.state.set("hijriDay",      tostring(hijriDay))
    noctalia.state.set("hijriMonth",    tostring(hijriMonth))
    noctalia.state.set("hijriYear",     tostring(hijriYear))
    noctalia.state.set("loadedDate",    jsonStr(todayStr()))
    noctalia.state.set("error",         '""')

    loadedDate = todayStr()
    lastNotified   = ""
    lastAzanPlayed = ""
    retryCount = 0

    return true
end

local function fetchTimes()
    if fetchPending then return end
    fetchPending = true
    local url = buildUrl()
    noctalia.http({ url = url }, function(res)
        fetchPending = false
        if not res.ok or res.body == "" then
            retryCount = retryCount + 1
            publishError("Network error")
            return
        end
        local ok, data = pcall(function()
            return noctalia.json.decode(res.body)
        end)
        if not ok or not data then
            retryCount = retryCount + 1
            publishError("Parse error")
            return
        end
        processPrayerData(data)
    end)
end

local function fetchTomorrowFajr()
    local url = buildUrl() .. "&date_or_timestamp=tomorrow"
    noctalia.http({ url = url }, function(res)
        if not res.ok or res.body == "" then return end
        local ok, data = pcall(function()
            return noctalia.json.decode(res.body)
        end)
        if not ok or not data or data.code ~= 200 then return end
        local timings = data.data and data.data.timings
        if not timings then return end
        local raw = timings["Fajr"]
        if raw then
            local clean = raw:match("^(%d+:%d+)") or raw
            local secs = parseTime(clean)
            if secs then
                secs = applyTune("Fajr", secs)
                noctalia.state.set("tomorrowFajr", tostring(secs))
            end
        end
    end)
end

-- ── Prayer events (notifications + azan) ──────────────────────────────────────

local function checkPrayerEvents(prayers)
    if not prayers or #prayers == 0 then return end
    local now = nowSeconds()
    for _, p in ipairs(prayers) do
        if now >= p.seconds and now < p.seconds + 30 and p.azanPrayer then
            local key = loadedDate .. "_" .. p.name
            if showNotifications and lastNotified ~= key then
                lastNotified = key
                noctalia.notify(p.name .. " prayer time", "It is time for " .. p.name)
            end
            if playAzan and lastAzanPlayed ~= key then
                lastAzanPlayed = key
                -- Try paplay then mpv then aplay
                local home = noctalia.getenv("HOME") or ""
                local file = azanFile
                noctalia.runAsync(
                    'FILE="' .. file .. '"; ' ..
                    'P1="' .. home .. '/.local/share/noctalia/plugins/sources/ycf/mawaqit/assets/$FILE"; ' ..
                    'P2="/usr/share/noctalia/assets/azan/$FILE"; ' ..
                    'AZAN=""; [ -f "$P1" ] && AZAN="$P1" || { [ -f "$P2" ] && AZAN="$P2"; }; ' ..
                    '[ -z "$AZAN" ] && exit 0; ' ..
                    'paplay "$AZAN" 2>/dev/null || mpv --no-video "$AZAN" 2>/dev/null || aplay "$AZAN" 2>/dev/null'
                )
            end
        end
    end
end

-- ── Cached prayer list for event checking ─────────────────────────────────────

local cachedPrayers = {}

noctalia.state.watch("prayers", function(json)
    local ok, list = pcall(function()
        return noctalia.json.decode(json)
    end)
    if ok and list then
        cachedPrayers = list
    end
end)

-- ── Main tick ─────────────────────────────────────────────────────────────────

function update()
    local today = todayStr()

    -- Fetch if date changed or no data yet
    if loadedDate ~= today then
        tomorrowFetched = false
        fetchTimes()
    end

    -- Fetch tomorrow's Fajr once we have today's data
    if loadedDate == today and not tomorrowFetched then
        tomorrowFetched = true
        fetchTomorrowFajr()
    end

    -- Retry on failure (every ~30s = 6 ticks at 5s interval)
    if retryCount > 0 and retryCount <= MAX_RETRIES then
        retryTicks = retryTicks + 1
        if retryTicks >= 6 then
            retryTicks = 0
            fetchTimes()
        end
    end

    -- Check prayer events
    checkPrayerEvents(cachedPrayers)
end

function onIpc(event, payload)
    if event == "refresh" then
        loadedDate = ""
        retryCount = 0
        cachedPrayers = {}
        noctalia.state.set("prayers", "[]")
        fetchTimes()
    end
end
