-- Grudgekeeper - pictures for the store page: /grudge shots. A made-up guild fills the ledger, the
-- letters and the cards, in English, and your own name and your guild's are replaced wherever
-- Grudgekeeper shows them ("trenger screenshots også men vil ikke bruke våre egne navn osv.. og ikke
-- norske", the owner, 2026-11-08). Each button opens one view, takes the game's own Screenshot() and
-- writes down where on the screen the view's frames were, as fractions of the screen, in
-- GrudgekeeperDB.shots. After a /reload has saved that, tools/crop_shots.py cuts each screenshot to it.
--
-- Like the test panel (Debug.lua), nothing leaves this client while the panel is open. Closing it, or a
-- reload or logout with it open, puts everything back as it was: your record, the guild's store, the
-- faces kept, the skin, the ledger's fold and sorting, and the screenshot quality. A real kill or death
-- while it is open is put back too, so it is not kept.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local ME, GUILD, RIVALS = "Aldric Thorne", "The Iron Oath", "Crimson Fang"
local MAX_SHOTS = 60      -- the list kept in GrudgekeeperDB.shots, the oldest dropped first
local GAP = 1.5           -- seconds from clearing the screen to the next view: the scroll rolls up in 0.2
local SETTLE = 1.2        -- and from a view opening to its picture: art loaded, animations done
local H, DAY = 3600, 24 * 3600

local panel, saved, running
local cast = {}           -- who and what Fill made, for the shots to open: keys and indexes

-- ---------------------------------------------------------------------------
-- The made-up guild
-- ---------------------------------------------------------------------------
-- Each: name; class, race and race file on the Horde side, then the same on the Alliance side; sex (2
-- male, 3 female); level against yours. Guildies and the friendly strangers are of your side, enemies
-- of the other.
local GUILDIES = {
    brannoc = { "Brannoc Ashford", "SHAMAN", "Tauren", "Tauren", "PALADIN", "Dwarf", "Dwarf", 2, 1 },
    merrin = { "Merrin Vale", "DRUID", "Tauren", "Tauren", "DRUID", "Night Elf", "NightElf", 3, 0 },
    tobias = { "Tobias Greaves", "ROGUE", "Undead", "Scourge", "ROGUE", "Human", "Human", 2, 1 },
    elowen = { "Elowen Marsh", "PRIEST", "Troll", "Troll", "PRIEST", "Human", "Human", 3, -1 },
    corwin = { "Corwin Hale", "WARLOCK", "Orc", "Orc", "WARLOCK", "Gnome", "Gnome", 2, 0 },
    isolde = { "Isolde Wren", "HUNTER", "Troll", "Troll", "HUNTER", "Night Elf", "NightElf", 3, -2 },
    gareth = { "Gareth Pike", "WARRIOR", "Orc", "Orc", "WARRIOR", "Dwarf", "Dwarf", 2, -3 },
    fenna = { "Fenna Bright", "MAGE", "Undead", "Scourge", "MAGE", "Gnome", "Gnome", 3, -4 },
}
local STRANGERS = {
    pellam = { "Pellam Crane", "ROGUE", "Undead", "Scourge", "ROGUE", "Human", "Human", 2, 0 },
    odo = { "Odo Fairweather", "WARRIOR", "Orc", "Orc", "WARRIOR", "Human", "Human", 2, -1 },
    tamsin = { "Tamsin Holt", "PRIEST", "Troll", "Troll", "PRIEST", "Dwarf", "Dwarf", 3, 0 },
    wystan = { "Wystan Reed", "DRUID", "Tauren", "Tauren", "DRUID", "Night Elf", "NightElf", 2, 1 },
}
local ENEMIES = {
    mordrek = { "Mordrek Ironhide", "ROGUE", "Orc", "Orc", "ROGUE", "Human", "Human", 2, 2 },
    vexmora = { "Vexmora", "WARLOCK", "Undead", "Scourge", "WARLOCK", "Gnome", "Gnome", 3, 1 },
    sable = { "Sable Rook", "HUNTER", "Troll", "Troll", "HUNTER", "Night Elf", "NightElf", 3, 0 },
    thazrak = { "Thazrak", "WARRIOR", "Orc", "Orc", "WARRIOR", "Dwarf", "Dwarf", 2, 3 },
    kethra = { "Kethra Duskwhisper", "PRIEST", "Troll", "Troll", "PRIEST", "Night Elf", "NightElf", 3, -1 },
    bramm = { "Bramm Stonefist", "SHAMAN", "Tauren", "Tauren", "PALADIN", "Dwarf", "Dwarf", 2, 1 },
    nyx = { "Nyx Hollow", "MAGE", "Undead", "Scourge", "MAGE", "Gnome", "Gnome", 3, -2 },
    grimbold = { "Grimbold", "ROGUE", "Orc", "Orc", "ROGUE", "Dwarf", "Dwarf", 2, 4 },
}
local SPELL = { ROGUE = "Ambush", HUNTER = "Aimed Shot", WARLOCK = "Shadow Bolt", WARRIOR = "Mortal Strike",
    MAGE = "Frostbolt", PRIEST = "Mind Blast", SHAMAN = "Lightning Bolt", PALADIN = "Hammer of Justice" }
-- contested zones for your level, so a level 25 and a level 58 both see places they know
local ZONES = {
    { 0, { "Hillsbrad Foothills", "Ashenvale", "Stonetalon Mountains", "Wetlands" } },
    { 30, { "Stranglethorn Vale", "Arathi Highlands", "Desolace", "Dustwallow Marsh" } },
    { 48, { "Felwood", "Eastern Plaguelands", "Winterspring", "Burning Steppes" } },
}

local function Cast(list, horde, base)
    local out = {}
    for id, s in pairs(list) do
        local i = horde and 2 or 5
        out[id] = { name = s[1], key = GK.KeyOf(s[1]), c = s[i], r = s[i + 1], rf = s[i + 2], sx = s[8],
            l = math.max(10, math.min(60, base + s[9])) }
    end
    return out
end

local function Line(...)
    local parts = {}
    for i = 1, select("#", ...) do
        local v = select(i, ...)
        parts[i] = v == nil and "" or tostring(v)
    end
    return table.concat(parts, ";")
end

local function Fill()
    local horde = UnitFactionGroup("player") == "Horde"
    local base = math.max(10, math.min(60, UnitLevel("player") or 60))
    local zones = ZONES[1][2]
    for _, z in ipairs(ZONES) do
        if base >= z[1] then zones = z[2] end
    end
    local g, x, e = Cast(GUILDIES, horde, base), Cast(STRANGERS, horde, base), Cast(ENEMIES, not horde, base)
    local me, now, c, s = LIB.Me(), time(), GK.char, GK.Store()
    for k in pairs(s) do
        if k ~= "nextId" then s[k] = nil end
    end
    s.board, s.orders, s.wanted, s.slain, s.feed, s.people = {}, {}, {}, {}, {}, {}
    GK.InvalidateOrders()
    c.log, c.foes, c.letters = {}, {}, {}
    -- faces: the board carries the guildies' own; everyone else's is a look kept, as after meeting them
    for _, list in ipairs({ x, e }) do
        for _, p in pairs(list) do GK.db.looks[p.key] = p.rf .. p.sx end
    end

    local function Hear(who, ...) GK.ReceiveForTest(nil, Line(...), "GUILD", who.key) end
    local function Note(who, ...) GK.NotesReceive(nil, Line(...), "GUILD", who.key) end
    --- the news line just made happened this long ago
    local function Back(ago)
        local top = s.feed[1]
        if top then top.t = now - ago end
    end
    local function Order(by, id) return s.orders[by.key .. "#" .. id] end

    -- The board: points, kills, deaths; this week's; streak, best; orders done, bounties won; nemesis.
    local week = GK.WeekId()
    local BOARD = {
        { g.brannoc, 412, 118, 40, 61, 14, 4, 6, 19, 7, 420000, e.mordrek, 9 },
        { g.merrin, 305, 88, 51, 22, 6, 5, 0, 12, 2, 60000, e.vexmora, 7 },
        { g.tobias, 268, 80, 33, 47, 12, 2, 9, 14, 4, 250000, e.thazrak, 5 },
        { g.elowen, 160, 41, 39, 12, 3, 6, 1, 7, 0, 0, e.mordrek, 11 },
        { g.corwin, 133, 39, 30, 18, 5, 2, 3, 8, 1, 20000, e.sable, 6 },
        { g.isolde, 97, 30, 18, 0, 0, 0, 2, 6, 0, 0, e.thazrak, 2, true },
        { g.gareth, 71, 22, 25, 9, 2, 3, 0, 5, 0, 0, e.thazrak, 3 },
        { g.fenna, 40, 12, 14, 5, 1, 2, 1, 3, 0, 0, e.vexmora, 1 },
    }
    for _, b in ipairs(BOARD) do
        local p = b[1]
        Hear(p, "B", 1, b[2], b[3], b[4], p.l, p.c, b[5], b[6], b[7], b[14] and 0 or week, b[8], b[9], b[10], b[11],
            b[12].key, b[13], p.rf, p.sx)
    end
    c.points, c.kills, c.deaths, c.streak, c.bestStreak, c.done, c.won = 214, 61, 23, 4, 11, 3, 135000
    c.week = { id = week, p = 38, k = 9, d = 3 }

    -- What happened, oldest first: every news line is put back to when it happened.
    local function Died(who, foe, times, ago)
        Hear(who, "D", 1, foe.key, foe.c, foe.r, foe.l, zones[math.floor(ago / H) % 4 + 1], times)
        Back(ago)
    end
    Died(g.elowen, e.mordrek, 11, 52 * H)
    Hear(g.tobias, "C", 1, 101, e.kethra.key, e.kethra.c, e.kethra.r, e.kethra.l, nil, 150000, now - 2 * DAY,
        now + 5 * DAY, "o", nil, "Heals every ganker in the zone.")
    Back(2 * DAY)
    Died(g.brannoc, e.thazrak, 4, 44 * H)
    Died(g.corwin, e.sable, 6, 30 * H)
    Died(g.brannoc, e.mordrek, 9, 29 * H)
    Hear(g.corwin, "F", 1, g.tobias.key, 101, zones[2])
    Back(27 * H)
    Order(g.tobias, 101).doneAt = now - 27 * H
    GK.SendDeath(e.mordrek, zones[1], 5)
    Back(26 * H)
    local mine = GK.PostOrder(e.sable, 200000, "Picks us off at the flight master.")
    mine.t, mine.exp = now - DAY, now + 6 * DAY
    Back(DAY)
    GK.SendDeath(e.sable, zones[2], 4)
    Back(23 * H)
    Hear(g.gareth, "T", 1, me, mine.id, 50000)
    Back(22 * H)
    Died(g.gareth, e.thazrak, 3, 20 * H)
    Died(g.fenna, e.kethra, 2, 12 * H)
    Died(g.tobias, e.bramm, 3, 9 * H)
    Died(g.elowen, e.thazrak, 6, 6 * H)
    Hear(g.brannoc, "C", 1, 102, e.mordrek.key, e.mordrek.c, e.mordrek.r, e.mordrek.l, nil, 500000, now - 5 * H,
        now + 7 * DAY - 5 * H, "o", nil, "Camps the flight master. Bring friends.")
    Back(5 * H)
    local bounty = Order(g.brannoc, 102)
    Hear(g.tobias, "T", 1, g.brannoc.key, 102, 200000)
    Back(4.5 * H)
    Hear(g.elowen, "T", 1, g.brannoc.key, 102, 100000)
    Back(4.2 * H)
    GK.Contribute(bounty, 50000)
    Back(3.9 * H)
    GK.SendKill(e.bramm, zones[1], GK.Points(base, e.bramm.l, 0, false), nil, 6)
    Back(3 * H)
    Hear(g.isolde, "K", 1, e.nyx.key, e.nyx.c, e.nyx.r, e.nyx.l, zones[3], GK.Points(g.isolde.l, e.nyx.l, 0, false),
        nil, 3)
    Back(2 * H)
    -- a rampage: three of us in a few minutes, and the third death posts an order by itself
    Died(g.gareth, e.vexmora, 1, 58 * 60)
    Died(g.fenna, e.vexmora, 1, 56 * 60)
    Died(g.merrin, e.vexmora, 3, 55 * 60)
    Hear(g.merrin, "C", 1, 103, e.vexmora.key, e.vexmora.c, e.vexmora.r, e.vexmora.l, nil, 0, now - 54 * 60,
        now + 3 * DAY - 54 * 60, "o", nil, nil, "r")
    Back(54 * 60)
    Hear(g.brannoc, "K", 1, e.thazrak.key, e.thazrak.c, e.thazrak.r, e.thazrak.l, zones[1],
        GK.Points(g.brannoc.l, e.thazrak.l, 0, false) + GK.AVENGE_BONUS, g.elowen.key, 4)
    Back(20 * 60)
    Hear(g.isolde, "S", 1, g.brannoc.key, 102, zones[1], e.mordrek.l)
    if bounty.seen then bounty.seen.t = now - 12 * 60 end

    -- Your own grudges and what happened lately, newest first.
    local FOES = { { e.mordrek, 2, 5, 26 * H }, { e.bramm, 6, 2, 3 * H }, { e.vexmora, 1, 3, 51 * H },
        { e.sable, 3, 4, 23 * H }, { e.thazrak, 4, 1, 25 * H }, { e.nyx, 3, 0, 30 * H }, { e.kethra, 2, 2, 2 * DAY } }
    for _, f in ipairs(FOES) do
        local p, at = f[1], now - f[4]
        c.foes[p.key] = { n = p.name, c = p.c, r = p.r, l = p.l, k = f[2], d = f[3], last = at,
            lastKill = f[2] > 0 and at or nil, lastDeath = f[3] > 0 and at - 600 or nil, hits = {} }
    end
    local LOG = { { "K", e.bramm, 3 * H, 1 }, { "D", e.sable, 23 * H, 2 }, { "K", e.thazrak, 25 * H, 2 },
        { "D", e.mordrek, 26 * H, 1 }, { "K", e.nyx, 30 * H, 3 }, { "K", e.kethra, 2 * DAY, 4 },
        { "D", e.vexmora, 51 * H, 3 }, { "K", e.mordrek, 3 * DAY, 1 } }
    for i, l in ipairs(LOG) do
        local p = l[2]
        c.log[i] = { k = l[1], t = now - l[3], n = p.key, c = p.c, r = p.r, l = p.l, z = zones[l[4]],
            p = l[1] == "K" and GK.Points(base, p.l, 0, false) or nil, s = l[1] == "D" and SPELL[p.c] or nil }
    end

    -- Notes: the guild's Shame, Kudos and Marked lists, with votes, and an enemy guild on watch.
    local function Info(p) return { c = p.c, r = p.r, rf = p.rf, sx = p.sx, l = p.l } end
    local function Wrote(by, p, ago, tag, list, text)
        Note(by, "N", 1, p.key, now - ago, now - ago, nil, tag, p.c, p.r, p.l, text)
        Note(by, "L", 1, p.key, list, now - ago, nil, p.c, p.r, p.l)
        return now - ago
    end
    local function Votes(p, author, id, ...)
        for i = 1, select("#", ...) do Note(select(i, ...), "V", 1, p.key, author.key, id, 1, id + i * 600) end
    end
    local id = Wrote(g.gareth, x.pellam, 3 * DAY, "Ninja looter", "watch",
        "Rolled need on every cloth drop, then left the group.")
    Votes(x.pellam, g.gareth, id, g.brannoc, g.fenna, g.corwin)
    GK.AddNote(x.pellam.key, "Took the boots off the last boss and left before anyone could roll.", "Ninja looter",
        "watch", Info(x.pellam))
    Wrote(g.merrin, x.odo, 2 * DAY, "Leaver", "watch", "Leaves the moment the last boss is down.")
    id = Wrote(g.elowen, x.tamsin, 2 * DAY, "Great healer", "kudos",
        "Kept six of us alive through a raid on our flight master.")
    Votes(x.tamsin, g.elowen, id, g.corwin, g.tobias, g.isolde, g.brannoc)
    GK.AddNote(x.wystan.key, "Ran back to my corpse with me, twice.", "Helpful", "kudos", Info(x.wystan))
    Wrote(g.brannoc, e.grimbold, DAY, nil, "kos", "Ganks anyone under 40 at the flight master.")
    Note(g.brannoc, "W", 1, RIVALS, now - DAY, nil, g.brannoc.key)

    -- Letters: a kill order from the guild, and the title your last kill earned - only these two, not the
    -- ones the orders above brought on their way in.
    c.letters, c.letterId = {}, 0
    local function Letter(kind, data, ago)
        c.letterId = (c.letterId or 0) + 1
        data.id, data.kind, data.t, data.read = c.letterId, kind, now - ago, false
        c.letters[#c.letters + 1] = data
        return #c.letters
    end
    local m, rank, of = e.mordrek, GK.MyRank()
    cast.orderLetter = Letter("order", { n = m.key, c = m.c, r = m.r, l = m.l, rf = m.rf, sx = m.sx,
        by = g.brannoc.key, reward = bounty.reward, note = bounty.note, o = bounty.key, times = 9 }, 5 * H)
    local b = e.bramm
    cast.titleLetter = Letter("kill", { n = b.key, c = b.c, r = b.r, l = b.l, rf = b.rf, sx = b.sx, z = zones[1],
        title = GK.Title(c.points), rank = rank, of = of, total = c.points }, 3 * H)

    cast.bounty, cast.top, cast.wanted = bounty.key, g.brannoc.key, e.mordrek.key
    cast.shame, cast.kudos = x.pellam.key, x.tamsin.key
    cast.poster = { key = m.key, c = m.c, r = m.r, l = m.l }
end

-- ---------------------------------------------------------------------------
-- On loan: everything the panel changes, kept to put back
-- ---------------------------------------------------------------------------
local function PutBack(into, from)
    wipe(into)
    for k, v in pairs(from) do into[k] = v end
end

local function Quality(v)
    if not (C_CVar and C_CVar.SetCVar) then return nil end
    local old = C_CVar.GetCVar and C_CVar.GetCVar("screenshotQuality")
    pcall(C_CVar.SetCVar, "screenshotQuality", v)
    return old
end

local function Begin()
    if GK.testMode or not (GK.char and GK.db and LIB.Me()) then return false end
    local db, store = GK.db, GK.Store()
    saved = { char = CopyTable(GK.char), store = CopyTable(store), storeTable = store,
        looks = CopyTable(db.looks or {}), sortBy = CopyTable(db.sortBy or {}), mineOnly = db.mineOnly,
        look = db.look, folded = db.ledgerFolded }
    GK.testMode, GK.shotMode = true, true
    GK.shotNames, GK.shotGuild = { [LIB.Me()] = ME }, GUILD
    db.looks = db.looks or {}
    db.sortBy, db.mineOnly = {}, false
    -- the best the game's JPEG does, for text that stays sharp when the page shrinks it
    saved.quality = Quality("10")
    local warn, sound = GK.Warn, GK.Sound
    GK.Warn, GK.Sound = function() end, function() end
    local ok, err = pcall(Fill)
    GK.Warn, GK.Sound = warn, sound
    GK.NoticeUpdate(false)
    GK.Changed()
    if not ok then return false, err end
    return true
end

local function Restore()
    if not GK.shotMode then return end
    running = nil
    GK.shotMode, GK.testMode = false, false
    GK.shotNames, GK.shotGuild = nil, nil
    local s = saved
    saved = nil
    if s then
        PutBack(GK.char, s.char)
        PutBack(s.storeTable, s.store)
        PutBack(GK.db.looks, s.looks)
        GK.db.sortBy, GK.db.mineOnly = s.sortBy, s.mineOnly
        if GK.db.look ~= s.look then GK.SetLook(s.look) end
        GK.FoldLedger(s.folded)
        if s.quality then Quality(s.quality) end
    end
    GK.InvalidateOrders()
    GK.CloseLetters()
    local card = _G.GrudgekeeperProfile
    if card and card:IsShown() then card:Hide() end
    local win = _G.GrudgekeeperFrame
    if win and win:IsShown() then win:Hide() end
    GK.NoticeUpdate(false)
    GK.Changed()
end

-- ---------------------------------------------------------------------------
-- Taking a picture
-- ---------------------------------------------------------------------------
--- Where the frames are on the screen together, as fractions of it: left, right, top, bottom, from the
--- screen's bottom left. nil when none of them is on the screen.
function GK.ShotRect(frames)
    local ui = UIParent:GetEffectiveScale()
    local sw, sh = (UIParent:GetWidth() or 0) * ui, (UIParent:GetHeight() or 0) * ui
    if sw <= 0 or sh <= 0 then return nil end
    local l, r, t, b
    for _, f in ipairs(frames or {}) do
        if f and f:IsVisible() then
            local k = f:GetEffectiveScale()
            local fl, fr, ft, fb = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
            if fl and fr and ft and fb then
                l, r = math.min(l or fl * k, fl * k), math.max(r or fr * k, fr * k)
                t, b = math.max(t or ft * k, ft * k), math.min(b or fb * k, fb * k)
            end
        end
    end
    if not l then return nil end
    return l / sw, r / sw, t / sh, b / sh
end

local function Record(name, l, r, t, b)
    local list = GK.db.shots
    if type(list) ~= "table" then
        list = {}
        GK.db.shots = list
    end
    local function R(v) return math.floor(v * 10000 + 0.5) / 10000 end
    -- the time as the game names its screenshots, WoWScrnShot_MMDDYY_HHMMSS, which the crop script matches
    list[#list + 1] = { n = name, at = date("%m%d%y_%H%M%S"), l = R(l), r = R(r), t = R(t), b = R(b) }
    while #list > MAX_SHOTS do table.remove(list, 1) end
end

local function ClearScreen()
    local win = _G.GrudgekeeperFrame
    if win and win:IsShown() then win:Hide() end
    GK.CloseLetters()
    local card = _G.GrudgekeeperProfile
    if card and card:IsShown() then card:Hide() end
    if GameTooltip then GameTooltip:Hide() end
end

local function Ledger(page, row, folded, weekly)
    return function()
        GK.ShowLedgerPage(page, row and ("%s:%s"):format(row[1], cast[row[2]]) or nil, folded, weekly)
        return GK.LedgerFrames()
    end
end

-- { file name, button, open the view and return the frames the picture takes in, seconds to settle }
local SHOTS = {
    { "orders", "Kill orders", Ledger("Kill orders", { "o", "bounty" }, false) },
    { "leaderboard", "Leaderboard", Ledger("Leaderboard", { "b", "top" }, false, true) },
    { "most-wanted", "Most wanted", Ledger("Most wanted", { "w", "wanted" }, false) },
    { "grudges", "Grudges", Ledger("Grudges", nil, false) },
    { "news", "News", Ledger("News", nil, false) },
    { "shame", "Shame", Ledger("Shame", { "p", "shame" }, false) },
    { "kudos", "Kudos", Ledger("Kudos", { "p", "kudos" }, false) },
    { "folded", "Folded ledger", Ledger("Kill orders", { "o", "bounty" }, true) },
    { "order-letter", "Kill order letter", function()
        GK.ShowLetter(cast.orderLetter)
        return { _G.GrudgekeeperLetter }
    end, 1.8 },
    { "title-letter", "Title letter", function()
        GK.ShowLetter(cast.titleLetter)
        return { _G.GrudgekeeperNote }
    end },
    { "poster", "Wanted poster", function()
        GK.ShowPoster(cast.poster)
        return { _G.GrudgekeeperProfile }
    end },
}
GK.shotList = SHOTS          -- for tools/smoke_grudgekeeper.py

local Status

--- Take the shots in the list, one after another, then call done(taken). The panel is see-through while
--- they are taken, so it is in none of them.
local function Run(list, done)
    local run = {}
    running = run
    panel:SetAlpha(0)
    local taken, i = 0, 0
    local function Finish()
        if running ~= run then return end
        running = nil
        panel:SetAlpha(1)
        ClearScreen()
        if done then done(taken) end
    end
    local function Next()
        if running ~= run then return end
        i = i + 1
        local shot = list[i]
        if not shot then return Finish() end
        ClearScreen()
        C_Timer.After(GAP, function()
            if running ~= run then return end
            local ok, frames = pcall(shot[3])
            if not ok then
                Status("|cffff5050" .. shot[2] .. ": " .. tostring(frames) .. "|r")
                return Finish()
            end
            C_Timer.After(shot[4] or SETTLE, function()
                if running ~= run then return end
                if GameTooltip then GameTooltip:Hide() end
                local l, r, t, b = GK.ShotRect(frames)
                if l then
                    Record(shot[1] .. (GK.Classic() and "-classic" or ""), l, r, t, b)
                    pcall(Screenshot)
                    taken = taken + 1
                end
                C_Timer.After(0.3, Next)
            end)
        end)
    end
    Next()
end

-- ---------------------------------------------------------------------------
-- The panel
-- ---------------------------------------------------------------------------
local W, BUTTON_W, ROW = 400, 182, 26

local function Taken(n)
    if n == 0 then
        Status("|cffff5050No picture: the view was not on the screen.|r")
    else
        Status(("%d %s taken. /reload to save where they are, then run tools/crop_shots.py."):format(n,
            n == 1 and "picture" or "pictures"))
    end
end

--- Take these shots (GK.shotList's entries; nil: all of them), unless a run is going already.
function GK.TakeShots(list)
    if running or not (panel and GK.shotMode) then return end
    Run(list or SHOTS, Taken)
end

local function Build()
    panel = CreateFrame("Frame", "GrudgekeeperShots", UIParent)
    panel:SetPoint("LEFT", 20, 0)
    panel:EnableMouse(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.06, 0.03, 0.02, 0.94)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 14, -12)
    title:SetText("Grudgekeeper screenshots")
    local note = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    note:SetPoint("TOPLEFT", 14, -36)
    note:SetWidth(W - 28)
    note:SetJustifyH("LEFT")
    note:SetText(("A made-up guild, %s, fills the book, and you are %s. Nothing goes to your guild, and "
        .. "closing this puts everything back - a kill made meanwhile too. Keep the mouse off the windows "
        .. "while a picture is taken.")
        :format(GUILD, ME))
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() GK.CloseShots() end)

    local y, col = -84, 0
    local function AddButton(text, width, fn)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(width, 22)
        b:SetPoint("TOPLEFT", 14 + col * (BUTTON_W + 8), y)
        b:SetText(text)
        b:SetScript("OnClick", function()
            if running then return end
            fn(b)
        end)
        return b
    end
    for _, shot in ipairs(SHOTS) do
        AddButton(shot[2], BUTTON_W, function() GK.TakeShots({ shot }) end)
        col = col + 1
        if col == 2 then
            col = 0
            y = y - ROW
        end
    end
    if col == 1 then y = y - ROW end
    col = 0
    y = y - 6
    AddButton("Take them all", W - 28, function() GK.TakeShots() end)
    y = y - ROW
    local skin = AddButton("", W - 28, function(b)
        GK.SetLook(GK.Classic() and "parchment" or "classic")
        b:SetText(GK.Classic() and "Skin: classic (click for parchment)" or "Skin: parchment (click for classic)")
    end)
    skin:SetScript("OnShow", function(b)
        b:SetText(GK.Classic() and "Skin: classic (click for parchment)" or "Skin: parchment (click for classic)")
    end)
    y = y - ROW
    local status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    status:SetPoint("TOPLEFT", 14, y - 6)
    status:SetWidth(W - 28)
    status:SetJustifyH("LEFT")
    function Status(text) status:SetText(text or "") end
    y = y - 34
    local done = AddButton("Close and put everything back", W - 28, function() GK.CloseShots() end)
    done:SetHeight(24)
    panel:SetSize(W, -y + 40)
    panel:Hide()
    if LIB.RegisterWindow then LIB.RegisterWindow(panel, GK.db, "shotsPanel") end
    -- Closing it any way at all - the X, Escape, the big button - puts everything back.
    panel:HookScript("OnHide", Restore)
end

--- /grudge shots: open the panel, and fill the book with the made-up guild.
function GK.OpenShots()
    if not GK.char then return end
    if GK.testMode then
        print(GK.TAG .. ": close the test panel first.")
        return
    end
    if not panel then Build() end
    local ok, err = Begin()
    if not ok then
        Restore()
        print(GK.TAG .. ": the screenshot mode could not start" .. (err and (": " .. tostring(err)) or "."))
        return
    end
    Status("")
    panel:SetAlpha(1)            -- closed halfway through a run, it was left see-through
    panel:Show()
    panel:Raise()
end

--- Close the panel and put everything back. (Escape hides it without this call: OnHide restores too.)
function GK.CloseShots()
    if panel then panel:Hide() end
    Restore()
end

-- A reload or logout with the panel open: put everything back before the game saves it.
LIB.On("PLAYER_LOGOUT", Restore)
