-- panel.luau — Mawaqit prayer times panel

local prayers       = {}
local tomorrowFajr  = nil
local hijriDate     = ""
local gregorianDate = ""
local errorMsg      = ""
local hasData       = false
local hijriMonth    = 0

local PRAYER_ICONS = {
    Fajr    = "moon-stars",
    Sunrise = "sunrise",
    Dhuhr   = "sun-high",
    Asr     = "sun-low",
    Maghrib = "sunset",
    Isha    = "moon",
    Imsak   = "moon-off",
}

local function nowSeconds()
    local t = os.date("*t")
    return t.hour * 3600 + t.min * 60 + t.sec
end

local function formatTime(secs)
    local h = math.floor(secs / 3600) % 24
    local m = math.floor((secs % 3600) / 60)
    return string.format("%02d:%02d", h, m)
end

local function formatCountdown(secs)
    if secs < 0 then secs = 0 end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    local s = secs % 60
    if h > 0 then
        return string.format("%dh %02dm %02ds", h, m, s)
    elseif m > 0 then
        return string.format("%dm %02ds", m, s)
    else
        return string.format("%ds", s)
    end
end

local function findNext()
    if #prayers == 0 then return nil, nil end
    local now = nowSeconds()
    for _, p in ipairs(prayers) do
        if p.seconds > now then return p, p.seconds - now end
    end
    if tomorrowFajr and tomorrowFajr > 0 then
        return { name = "Fajr", time = formatTime(tomorrowFajr), seconds = tomorrowFajr },
               (86400 - now) + tomorrowFajr
    end
    return prayers[1], nil
end

local function accentFor(name)
    if hijriMonth == 9 then
        if name == "Imsak"   then return "secondary" end
        if name == "Maghrib" then return "tertiary"  end
    end
    return "primary"
end

local function render()
    local nextPrayer, secondsToNext = findNext()

    -- ── Header ────────────────────────────────────────────────────────────────
    local header = ui.row({ align = "center", justify = "space_between" }, {
        ui.row({ align = "center", gap = 8 }, {
            ui.glyph({ name = "building-mosque", size = 18, color = "primary" }),
            ui.label({ text = "Prayer Times", fontSize = 16, fontWeight = "semibold", color = "on_surface" }),
        }),
        ui.row({ align = "center", gap = 4 }, {
            ui.button({ glyph = "refresh", onClick = "onRefresh" }),
            ui.button({ glyph = "x",       onClick = "onClose"   }),
        }),
    })

    -- ── Date row ──────────────────────────────────────────────────────────────
    local dateRow = nil
    if gregorianDate ~= "" or hijriDate ~= "" then
        dateRow = ui.row({ align = "center", justify = "space_between" }, {
            ui.label({ text = gregorianDate, fontSize = 11, color = "on_surface_variant" }),
            ui.label({
                text     = hijriDate,
                fontSize = 11,
                color    = hijriMonth == 9 and "primary" or "on_surface_variant",
            }),
        })
    end

    -- ── Countdown banner ──────────────────────────────────────────────────────
    local banner = nil
    if nextPrayer and secondsToNext then
        local isNow  = secondsToNext <= 60
        local aColor = accentFor(nextPrayer.name)
        if isNow then
            banner = ui.column({
                align = "center", gap = 2,
                fill = aColor, radius = 10,
                paddingH = 16, paddingV = 14,
            }, {
                ui.label({
                    text = nextPrayer.name .. " — Now",
                    fontSize = 17, fontWeight = "bold", color = "on_primary",
                }),
            })
        else
            banner = ui.column({
                align = "center", gap = 4,
                fill = "surface_variant", radius = 10, opacity = 0.6,
                paddingH = 16, paddingV = 14,
            }, {
                ui.label({
                    text = nextPrayer.name .. " in",
                    fontSize = 12, color = "on_surface_variant",
                }),
                ui.label({
                    text = formatCountdown(secondsToNext),
                    fontSize = 28, fontWeight = "bold", color = aColor,
                }),
            })
        end
    elseif not hasData then
        banner = ui.column({
            align = "center", gap = 4,
            fill = "surface_variant", radius = 10,
            paddingH = 16, paddingV = 14,
        }, {
            ui.label({
                text  = errorMsg ~= "" and errorMsg or "Loading prayer times…",
                fontSize = 14,
                color = errorMsg ~= "" and "error" or "on_surface_variant",
            }),
        })
    end

    -- ── Prayer rows — plain column, no scroll ─────────────────────────────────
    local rows = {}
    for _, p in ipairs(prayers) do
        local isNext   = nextPrayer and p.name == nextPrayer.name
        local aColor   = accentFor(p.name)
        local nameClr  = isNext and aColor or "on_surface"
        local timeClr  = isNext and aColor or "on_surface_variant"
        local weight   = isNext and "semibold" or "normal"
        local icon     = PRAYER_ICONS[p.name] or "sun"

        rows[#rows+1] = ui.row({
            key     = p.name,
            align   = "center",
            justify = "space_between",
            paddingH = 10,
            paddingV = isNext and 10 or 7,
            fill    = isNext and "surface_variant" or nil,
            opacity = isNext and 0.6 or nil,
            radius  = isNext and 8 or nil,
        }, {
            ui.row({ align = "center", gap = 10 }, {
                ui.glyph({ name = icon, size = 15, color = nameClr }),
                ui.label({ text = p.name, fontSize = 14, fontWeight = weight, color = nameClr }),
            }),
            ui.label({ text = p.time, fontSize = 14, fontWeight = weight, color = timeClr }),
        })
    end

    -- ── Assemble ──────────────────────────────────────────────────────────────
    local children = { header }
    if dateRow then
        children[#children+1] = dateRow
    end
    children[#children+1] = ui.separator({ spacing = 2, color = "outline", opacity = 0.2 })
    if banner then
        children[#children+1] = banner
    end
    if #rows > 0 then
        children[#children+1] = ui.column({ gap = 2 }, rows)
    end
    children[#children+1] = ui.spacer({ height = 4 })

    panel.render(ui.column({ flexGrow = 1, gap = 10 }, children))
end

-- ── State watchers ────────────────────────────────────────────────────────────

noctalia.state.watch("prayers", function(json)
    local ok, list = pcall(function() return noctalia.json.decode(json) end)
    if ok and list then prayers = list; hasData = #list > 0 end
    render()
end)

noctalia.state.watch("tomorrowFajr", function(val)
    tomorrowFajr = tonumber(val); render()
end)

noctalia.state.watch("hijriDate", function(json)
    local ok, val = pcall(function() return noctalia.json.decode(json) end)
    if ok and type(val) == "string" then hijriDate = val end
    render()
end)

noctalia.state.watch("gregorianDate", function(json)
    local ok, val = pcall(function() return noctalia.json.decode(json) end)
    if ok and type(val) == "string" then gregorianDate = val end
    render()
end)

noctalia.state.watch("hijriMonth", function(val)
    hijriMonth = tonumber(val) or 0; render()
end)

noctalia.state.watch("error", function(json)
    local ok, msg = pcall(function() return noctalia.json.decode(json) end)
    if ok and type(msg) == "string" then errorMsg = msg end
    if not hasData then render() end
end)

-- ── Lifecycle ─────────────────────────────────────────────────────────────────

function onOpen(_context)
    local p = noctalia.state.get("prayers")
    if p then
        local ok, list = pcall(function() return noctalia.json.decode(p) end)
        if ok and list then prayers = list; hasData = #list > 0 end
    end
    local tf = noctalia.state.get("tomorrowFajr")
    if tf then tomorrowFajr = tonumber(tf) end
    local hd = noctalia.state.get("hijriDate")
    if hd then
        local ok, val = pcall(function() return noctalia.json.decode(hd) end)
        if ok and type(val) == "string" then hijriDate = val end
    end
    local gd = noctalia.state.get("gregorianDate")
    if gd then
        local ok, val = pcall(function() return noctalia.json.decode(gd) end)
        if ok and type(val) == "string" then gregorianDate = val end
    end
    local hm = noctalia.state.get("hijriMonth")
    if hm then hijriMonth = tonumber(hm) or 0 end
    render()
end

function onClose()   panel.close() end
function onRefresh() noctalia.runAsync("noctalia msg plugin ycf/mawaqit:fetcher all refresh") end

noctalia.setUpdateInterval(1000)
function update()
    if hasData then render() end
end
