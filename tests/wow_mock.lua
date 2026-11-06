-- A small fake WoW client and LibForever, enough to load Core.lua, Notes.lua and Import.lua outside the
-- game (Lua 5.1) and drive them. One client at a time: boot() builds a fresh one over the same globals.
-- Time is ours: GetTime() and time() move only when a test calls advance(), which also runs the timers
-- that fall due, in order.
local M = {}

M.dir = ""                  -- where the addon's files are (the repo root, with a trailing slash)
M.base = 1800000000         -- time() at clock 0

local function copy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = copy(x) end
    return t
end

-- ---------------------------------------------------------------------------
-- Time
-- ---------------------------------------------------------------------------
--- Move the clock on by `seconds`, running every timer that falls due on the way, earliest first.
function M.advance(seconds)
    local target = M.clock + seconds
    while true do
        local next_, at = nil, nil
        for i, t in ipairs(M.timers) do
            if t.at <= target and (not at or t.at < at) then next_, at = i, t.at end
        end
        if not next_ then break end
        local t = table.remove(M.timers, next_)
        M.clock = math.max(M.clock, t.at)
        t.fn()
    end
    M.clock = target
end

-- ---------------------------------------------------------------------------
-- LibForever, the parts the addon touches
-- ---------------------------------------------------------------------------
local function NewLib()
    local LIB = { roster = {} }
    local handlers, listeners = {}, {}
    function LIB.On(event, fn)
        handlers[event] = handlers[event] or {}
        table.insert(handlers[event], fn)
    end
    function LIB.Listen(name, fn)
        listeners[name] = listeners[name] or {}
        table.insert(listeners[name], fn)
    end
    function LIB.Fire(name, ...)
        for _, fn in ipairs(listeners[name] or {}) do fn(...) end
    end
    function LIB.Debug() end
    function LIB.NormalizeRealm(realm) return (tostring(realm or ""):gsub("[%s%-']", "")) end
    function LIB.FullName(name)
        if not name or name == "" then return nil end
        if not name:find("-", 1, true) then name = name .. "-Realm" end
        return name
    end
    function LIB.Realm() return "Realm" end
    -- Same rule as the real one: on the roster, or heard on the guild's addon channel (M.receive).
    LIB.guildHeard = {}
    function LIB.KnownGuildie(full)
        return full ~= nil and (LIB.roster[full] ~= nil or LIB.guildHeard[full] == true)
    end
    function LIB.Me() return M.me end
    function LIB.UnitKey(unit) return M.units[unit] end
    function LIB.IsMyStoredName(key) return key == M.me end
    function LIB.ShortName(full) return (full or "?"):gsub("%-[^%-]*$", "") end
    -- M.guildKey: what the client says the guild is (nil: it has not said yet, though IsInGuild is true)
    function LIB.GuildKey()
        if not M.inGuild then return nil end
        if M.guildKey == false then return nil end
        return M.guildKey or "Guild-Realm"
    end
    function LIB.CommStats() return 0, 0, 0 end
    -- Same rule as the real one (LibForever-1.0.lua): no control characters, "|" becomes "/", capped.
    function LIB.Sanitize(s, maxLen)
        s = tostring(s or "")
        s = s:gsub("%c", " "):gsub("|", "/")
        s = strtrim(s)
        maxLen = tonumber(maxLen) or 128
        if #s > maxLen then s = s:sub(1, maxLen) end
        return s
    end
    function LIB.RegisterComm(prefix, fn)
        M.comm[prefix] = fn
        return true
    end
    function LIB.Send(prefix, text, dist)
        if not M.inGuild then return false end
        table.insert(M.sent, { prefix = prefix, text = text, dist = dist, at = M.clock })
        return true
    end
    function LIB.PrepareDB(db, defaults)
        db = db or {}
        for k, v in pairs(defaults) do
            if db[k] == nil then db[k] = copy(v) end
        end
        return db
    end
    LIB.fire = function(event, ...)
        for _, fn in ipairs(handlers[event] or {}) do fn(...) end
    end
    return LIB
end

-- ---------------------------------------------------------------------------
-- A client
-- ---------------------------------------------------------------------------
-- opts: me (default "Meyer-Realm"), inGuild (default true), guildGrudge (a GuildGrudgeDB to have), loaded
-- (is the GuildGrudge addon on; default: whether a GuildGrudgeDB was given), ui (also load NotesUI.lua, with
-- the stand-ins in tests/ui_mock.lua).
-- Returns GK and the LibForever stand-in. M.sent collects what the addon sent, M.printed what it printed.
function M.boot(opts)
    opts = opts or {}
    M.clock, M.timers, M.sent, M.printed, M.comm = 0, {}, {}, {}, {}
    M.me = opts.me or "Meyer-Realm"
    M.inGuild = opts.inGuild ~= false
    M.guildKey = nil                -- tests set a name here, or false for "not known yet"
    M.units = { player = M.me }
    M.LIB = NewLib()

    local env = _G
    env.LibStub = setmetatable({}, { __call = function(_, name)
        if name == "LibForever-1.0" then return M.LIB end
    end })
    env.time = function() return M.base + math.floor(M.clock) end
    env.GetTime = function() return M.clock end
    env.strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.IsInGuild = function() return M.inGuild end
    env.UnitFactionGroup = function() return "Alliance" end
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        table.insert(M.printed, table.concat(parts, " "))
    end
    env.C_Timer = {
        After = function(d, fn) table.insert(M.timers, { at = M.clock + d, fn = fn }) end,
    }
    env.C_AddOns = {
        GetAddOnMetadata = function() return "0.0.0-test" end,
        IsAddOnLoaded = function(name)
            if name == "GuildGrudge" then
                if opts.loaded ~= nil then return opts.loaded end
                return opts.guildGrudge ~= nil
            end
            return false
        end,
    }
    env.C_GuildInfo = { GuildControlGetRankFlags = function(rank)
        -- ranks are 1-based here; M.rankFlags[rankIndex + 1] is the flags of that rank
        local flags = M.rankFlags and M.rankFlags[rank]
        if not flags then return nil end
        return unpack(flags)
    end }
    env.RAID_CLASS_COLORS = { WARRIOR = {}, ROGUE = {}, MAGE = {}, PRIEST = {}, DRUID = {} }
    env.SlashCmdList = {}
    env.issecretvalue = nil
    env.GuildGrudgeDB = opts.guildGrudge
    env.GrudgekeeperDB, env.GrudgekeeperCharDB = nil, nil
    M.rankFlags = nil

    local GK = {}
    for _, file in ipairs({ "Core.lua", "Notes.lua", "Import.lua" }) do
        local chunk = assert(loadfile(M.dir .. file))
        chunk("Grudgekeeper", GK)
    end
    -- opts.ui: the ledger's side of the notes (NotesUI.lua), with stand-ins for the files it builds on
    if opts.ui then require("ui_mock").load(M, GK) end
    -- The login handler in Core.lua starts every other part of the addon; none of them is loaded here.
    for _, name in ipairs({ "StartGuild", "StartSightings", "StartKills", "StartLetters", "StartMail",
            "StartSocial", "StartProfiles", "StartInspect", "StartMapPins", "RegisterOptions" }) do
        GK[name] = function() end
    end
    M.changes = 0
    local changed = GK.Changed
    GK.Changed = function() M.changes = M.changes + 1 return changed() end
    M.LIB.fire("PLAYER_LOGIN")
    return GK, M.LIB
end

--- Feed a message to the addon as if `sender` had sent it to the guild.
function M.receive(GK, sender, text, dist)
    if (dist or "GUILD") == "GUILD" then M.LIB.guildHeard[sender] = true end
    GK.NotesReceive("GrudgeNotes", text, dist or "GUILD", sender)
end

--- What was sent so far, and forget it.
function M.takeSent()
    local out = M.sent
    M.sent = {}
    return out
end

return M
