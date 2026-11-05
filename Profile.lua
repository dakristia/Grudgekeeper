-- Grudgekeeper - profiles: what the guild knows about one player, on a card in the same iron frame as
-- the small letters. Two kinds:
--   a guildie's RECORD   title and points, kills and deaths this week and all time, place on the board,
--                        kill streak, kill orders fulfilled and the bounties on them, nemesis, and the
--                        latest the news has on them
--   a WANTED poster      an enemy player: how often they killed us and whom, how often we got them,
--                        your own score with them, where they were last seen, the order and its pot
-- It opens from the game's right-click menu on a player (the target frame, party and raid frames, a
-- name in chat, the guild roster), from a name in the window and from a pin on the world map. Like
-- every window here, it never opens by itself.
-- Everything on a card is what this client has heard: a guildie who never runs Grudgekeeper has no
-- record, and kills made while you were offline count once the killer's next kill tells their total.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local TITLE_FONT = "Fonts\\MORPHEUS.ttf"
local TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local INK = { 0.22, 0.13, 0.05 }
local FADED = { 0.42, 0.33, 0.22 }
local BLOOD = { 0.47, 0.06, 0.04 }
local LABEL = "Grudgekeeper profile"
local NAMES = 3                  -- names on a line before "and 2 more"
local QUIET_FOR = 7 * GK.DAY     -- a guildie not heard from in this long: the card says when they were

local function Plural(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end

local function Who(key)
    if LIB.IsMyStoredName(key) then return "you" end
    return GK.Show(key)
end

--- The record in t under this player's name: the exact key, else the same name written another way
--- (GK.SameName - another realm spelling, a surname one side left off). Only ever asked from a click,
--- so a walk over a few hundred names is fine; nothing that runs per event comes through here.
local function Find(t, key)
    if not (t and type(key) == "string") then return nil end
    if t[key] then return t[key], key end
    for k, v in pairs(t) do
        if GK.SameName(k, key) then return v, k end
    end
    return nil
end

--- "Vebjørn 5, Kari 4 and 3 more" from { [who] = count }, the most first; and the sum of the counts.
local function Names(map)
    local list, total = {}, 0
    for who, n in pairs(map) do
        list[#list + 1] = { who = who, n = n }
        total = total + n
    end
    table.sort(list, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.who < b.who
    end)
    local parts = {}
    for i = 1, math.min(NAMES, #list) do parts[i] = ("%s %d"):format(Who(list[i].who), list[i].n) end
    local text = table.concat(parts, ", ")
    if #list > NAMES then text = text .. (" and %d more"):format(#list - NAMES) end
    return text, total
end

-- ---------------------------------------------------------------------------
-- What a card says. Plain data, so the smoke test can read it without a frame:
-- { title, name, info, lines, big, caption, seal, blood, buttons = { { text, fn } }, c, unit, key }
-- ---------------------------------------------------------------------------
--- An enemy player. t = { key, guid, c, r, l, unit }: whatever the caller knows. inLedger: drawn on
--- the ledger's own page (Window.lua), where your own order's button withdraws it rather than
--- opening the hitlist you are already looking at.
function GK.PosterCard(t, inLedger)
    local key, guid = t.key, t.guid
    local s = GK.Store()
    local w = Find(s.wanted, key)
    local e = Find(s.slain, key)
    local f, fkey = Find(GK.char.foes, key)
    local o = GK.OrderOn(key, guid)
    local live = GK.Seen(key, guid)
    local function Pick(field)
        return t[field] or (live and live[field]) or (o and o[field]) or (f and f[field]) or (e and e[field])
            or (w and w[field])
    end
    local c, r, l = Pick("c"), Pick("r"), Pick("l")
    -- race and sex only from a look this session: enough for their race's face in the portrait
    local d = { key = key, unit = t.unit, c = c, name = GK.Show(key), info = GK.Describe(l, c, r), lines = {},
        buttons = {}, rf = live and live.rf, sx = live and live.sx }
    local lines = d.lines
    local killedUs = 0
    if w and next(w.victims) then
        local names, total = Names(w.victims)
        killedUs = total
        lines[#lines + 1] = ("Has killed us %s: %s."):format(Plural(total, "time"), names)
    end
    if e and next(e.by) then
        local names, total = Names(e.by)
        lines[#lines + 1] = ("We have killed them %s: %s."):format(Plural(total, "time"), names)
    end
    if f and (f.k or 0) + (f.d or 0) > 0 then
        local nemesis = GK.Nemesis()
        lines[#lines + 1] = ("You: %s, %s%s"):format(Plural(f.k or 0, "kill"), Plural(f.d or 0, "death"),
            nemesis == fkey and " - your nemesis." or ".")
    end
    -- Last seen: anyone in the guild, through the order; else our own look in the last 15 minutes.
    local seen = o and o.seen
    if seen and seen.t then
        lines[#lines + 1] = ("Last seen in %s, %s, by %s."):format(seen.z or "the world", GK.Ago(seen.t), Who(seen.by))
    elseif live then
        lines[#lines + 1] = ("You saw them lately, in %s."):format(live.z or "the world")
    end
    local me = LIB.Me()
    if o then
        local pot, backers = GK.Pot(o)
        local hunting = 0
        for _ in pairs(o.hunters or {}) do hunting = hunting + 1 end
        local extra = {}
        if backers > 0 then extra[#extra + 1] = Plural(backers, "backer") end
        if hunting > 0 then extra[#extra + 1] = hunting .. " hunting them" end
        local tail = #extra > 0 and (" - " .. table.concat(extra, ", ")) or ""
        -- An order their own killing posted (GK.AutoOrder) says why, in the Grudgekeeper's words, and
        -- was posted by a death rather than by a guildie's hand.
        local by = Who(o.by)
        if o.auto then
            by = (by == "you" and "your" or (by .. "'s")) .. " death"
            local why = o.note and (o.note:gsub("^%u", string.lower)) or nil
            lines[#lines + 1] = why and ("The guild wants them dead: %s"):format(why) or "The guild wants them dead."
        end
        if pot > 0 then
            lines[#lines + 1] = ("Bounty %s, posted by %s%s."):format(GK.MoneyText(pot), by, tail)
            d.big = pot >= 10000 and (math.floor(pot / 10000) .. "g") or GK.MoneyText(pot)
            d.caption = "bounty"
        else
            lines[#lines + 1] = ("A kill order for the guild's honour, posted by %s%s."):format(by, tail)
        end
        if o.by ~= me then
            local mine = GK.char.accepted[o.key]
            d.buttons[1] = { mine and "Drop the order" or "Take the order", function() GK.Accept(o, not mine) end }
            d.buttons[2] = { (o.pot and me and o.pot[me]) and "Your share" or "Add to the pot", function()
                GK.OpenPost({ key = o.n, guid = o.guid, c = o.c, r = o.r, l = o.l })
            end }
        elseif inLedger then
            d.buttons[1] = { "Withdraw", function() GK.Withdraw(o) end }
        else
            d.buttons[1] = { "Hitlist", function() GK.OpenWindow(1) end }
        end
    else
        d.buttons[1] = { "Post a kill order", function()
            GK.OpenPost({ key = key, guid = guid, c = c, r = r, l = l })
        end }
    end
    if not d.big and killedUs > 0 then d.big, d.caption = tostring(killedUs), "killed us" end
    local history = killedUs > 0 or (e and next(e.by)) or (f and (f.k or 0) + (f.d or 0) > 0)
    if o then
        d.title, d.seal = "WANTED", "mark"
    elseif history then
        d.title, d.seal = "A GRUDGE", "seal_black"
    else
        d.title = "NO RECORD"
        lines[#lines + 1] = "Nobody in the guild has killed them or died to them - not that the Grudgekeeper heard of."
    end
    d.blood = f ~= nil and (f.d or 0) > 0       -- they have killed you
    return d
end

--- The latest the news says about a guildie: one line, or nil.
local function Latest(key, me)
    for _, e in ipairs(GK.Store().feed) do
        if e.who == key or (me and LIB.IsMyStoredName(e.who)) then
            local target = GK.Show(e.n)
            local when = GK.Ago(e.t)
            if e.kind == "K" then
                return ("Lately: killed %s%s, %s."):format(target, (e.p or 0) > 0 and (" (+%d)"):format(e.p) or "", when)
            elseif e.kind == "D" then
                return ("Lately: fell to %s, %s."):format(target, when)
            elseif e.kind == "F" then
                return ("Lately: fulfilled the kill order on %s, %s."):format(target, when)
            elseif e.kind == "C" then
                return ("Lately: put a price on %s, %s."):format(target, when)
            end
        end
    end
    return nil
end

--- A guildie, or you: their record as they last sent it (B). nil when we have none.
function GK.RecordCard(key, unit)
    local me = LIB.IsMyStoredName(key)
    local r
    if me then
        local c, w = GK.char, GK.Week()
        local nemesis, nf = GK.Nemesis()
        local _, class = UnitClass("player")
        local _, raceFile = UnitRace("player")
        r = { p = c.points, k = c.kills, d = c.deaths, wp = w.p, wk = w.k, wd = w.d, wid = w.id,
            st = c.streak, bs = c.bestStreak, od = c.done, ow = c.won, nm = nemesis, nt = nf and nf.d,
            c = class, l = UnitLevel("player"), t = time(), rf = raceFile, sx = UnitSex("player") }
        key = LIB.Me() or key
    else
        r, key = Find(GK.Store().board, key)
        if not r then return nil end
    end
    local p = r.p or 0
    local d = { key = key, unit = unit, c = r.c, rf = r.rf, sx = r.sx, title = GK.Show(key),
        name = GK.Title(p), lines = {}, buttons = {},   -- the points are the big number, not said twice
        big = tostring(p), caption = p == 1 and "point" or "points" }
    -- place on the board: all time, and this week if they are on this week's
    local function Place(weekly)
        local list = GK.Board(weekly)
        for i, e in ipairs(list) do
            if (me and e.me) or (not me and e.who == key) then return i, #list end
        end
        return nil
    end
    local rank, of = Place(false)
    local weekRank = Place(true)
    local where = GK.Describe(r.l, r.c)
    if rank and of > 1 then
        where = ("#%d of %d in the guild%s"):format(rank, of, weekRank and (", #%d this week"):format(weekRank) or "")
    end
    d.info = where
    local lines = d.lines
    lines[#lines + 1] = ("All time: %s, %s."):format(Plural(r.k or 0, "kill"), Plural(r.d or 0, "death"))
    if r.wid == GK.WeekId() and ((r.wk or 0) + (r.wd or 0) + (r.wp or 0)) > 0 then
        lines[#lines + 1] = ("This week: %s, %s, %s."):format(Plural(r.wk or 0, "kill"), Plural(r.wd or 0, "death"),
            Plural(r.wp or 0, "point"))
    else
        lines[#lines + 1] = "Nothing yet this week."
    end
    if (r.bs or 0) > 0 then
        lines[#lines + 1] = ("Kill streak: %d now, best %d."):format(r.st or 0, r.bs)
    end
    if (r.od or 0) > 0 then
        lines[#lines + 1] = ("Kill orders fulfilled: %d%s."):format(r.od,
            (r.ow or 0) > 0 and (", for %s in bounties"):format(GK.MoneyText(r.ow)) or "")
    end
    if r.nm then
        lines[#lines + 1] = r.nt and ("Nemesis: %s, who has killed %s %s."):format(GK.Show(r.nm), me and "you" or "them",
            Plural(r.nt, "time")) or ("Nemesis: %s."):format(GK.Show(r.nm))
    end
    local latest = Latest(key, me)
    if latest then lines[#lines + 1] = latest end
    if not me and r.t and time() - r.t > QUIET_FOR then
        lines[#lines + 1] = ("Last heard from %s."):format(GK.Ago(r.t))
    end
    d.buttons[1] = { "Leaderboard", function() GK.OpenWindow(2) end }
    return d
end

--- Is there a record to show for this friendly player: you, or a guildie on the board.
function GK.HasRecord(key)
    if type(key) ~= "string" then return false end
    return LIB.IsMyStoredName(key) or Find(GK.Store().board, key) ~= nil
end

-- ---------------------------------------------------------------------------
-- The card
-- ---------------------------------------------------------------------------
local card            -- the frame, made on first use
local showing         -- { poster = t } or { record = key, unit = unit }

local function Ink(fs, colour, font, size)
    fs:SetFont(font, size, "")
    fs:SetTextColor(colour[1], colour[2], colour[3])
    fs:SetShadowOffset(0, 0)
end

local function Build()
    local f = GK.MakeNoteFrame("GrudgekeeperProfile")
    f.title = f:CreateFontString(nil, "ARTWORK")
    Ink(f.title, BLOOD, TITLE_FONT, 22)
    f.title:SetPoint("TOPLEFT", 172, -60)
    f.name = f:CreateFontString(nil, "ARTWORK")
    Ink(f.name, INK, TITLE_FONT, 17)
    f.name:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.info = f:CreateFontString(nil, "ARTWORK")
    Ink(f.info, FADED, TEXT_FONT, 11)
    f.info:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -3)
    f.body = f:CreateFontString(nil, "ARTWORK")
    Ink(f.body, INK, TEXT_FONT, 12)
    f.body:SetPoint("TOPLEFT", f.info, "BOTTOMLEFT", 0, -10)
    f.body:SetWidth(320)
    f.body:SetJustifyH("LEFT")
    f.body:SetSpacing(3)
    -- Under the portrait, the card's one number: points, the bounty, or how often they killed us.
    f.big = f:CreateFontString(nil, "ARTWORK")
    Ink(f.big, BLOOD, TITLE_FONT, 30)
    f.big:SetPoint("TOP", f.disc, "BOTTOM", 0, -12)
    f.caption = f:CreateFontString(nil, "ARTWORK")
    Ink(f.caption, INK, TEXT_FONT, 11)
    f.caption:SetPoint("TOP", f.big, "BOTTOM", 0, -2)
    -- WANTED wears the red seal from their nameplate, top right
    f.seal = f:CreateTexture(nil, "OVERLAY")
    f.seal:SetSize(54, 54)
    f.seal:SetPoint("TOPRIGHT", -46, -54)
    local sign = f:CreateFontString(nil, "ARTWORK")
    Ink(sign, INK, TITLE_FONT, 16)
    sign:SetPoint("BOTTOMRIGHT", -50, 54)
    sign:SetText("- the Grudgekeeper")
    f.buttons = {}
    for i = 1, 2 do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(140, 22)
        if i == 1 then b:SetPoint("BOTTOMLEFT", 46, 50) else b:SetPoint("LEFT", f.buttons[1], "RIGHT", 6, 0) end
        f.buttons[i] = b
    end
    -- Our own Hide, so closing works in combat too.
    local close = GK.MakeCloseButton(f, 20, function() f:Hide() end, 14)
    close:SetFrameLevel(f:GetFrameLevel() + 12)
    close:SetPoint("TOPRIGHT", -12, -12)
    if LIB.RegisterWindow then LIB.RegisterWindow(f, GK.db, "profile") end
    card = f
end

--- The face of whoever the card is about, while the unit it was opened from is still them; else their
--- race's portrait when we know race and sex; else their class crest; else the Grudgekeeper himself.
local function Portrait(f, d)
    local coords = d.c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[d.c]
    local face = false
    local unit = d.unit
    if unit and SetPortraitTexture and UnitExists(unit) then
        local key = LIB.UnitKey(unit)
        if key and GK.SameName(key, d.key) then face = pcall(SetPortraitTexture, f.portrait, unit) end
    end
    if face then
        f.portrait:SetTexCoord(0, 1, 0, 1)
    else
        local kind = GK.SetPortrait(f.portrait, d)
        face = kind == "race"
        if kind == "seal" then
            f.portrait:SetTexture(MEDIA .. "portrait")
            f.portrait:SetTexCoord(0, 1, 0, 1)
        end
    end
    local badge = face and coords
    f.badge:SetShown(badge and true or false)
    f.badgeRing:SetShown(badge and true or false)
    if badge then
        f.badge:SetTexture(CLASS_ICONS)
        f.badge:SetTexCoord(unpack(coords))
    end
end

local Refill

local function Fill(d)
    local f = card
    f.title:SetText(d.title or "")
    f.name:SetText(d.name or "")
    f.info:SetText(d.info or "")
    f.body:SetText(table.concat(d.lines, "\n"))
    f.big:SetText(d.big or "")
    f.caption:SetText(d.caption or "")
    f.seal:SetShown(d.seal ~= nil)
    if d.seal then f.seal:SetTexture(MEDIA .. d.seal) end
    f.blood:SetShown(d.blood == true)
    Portrait(f, d)
    for i, b in ipairs(f.buttons) do
        local spec = d.buttons[i]
        b:SetShown(spec ~= nil)
        if spec then
            b:SetText(spec[1])
            b:SetScript("OnClick", function()
                spec[2]()
                Refill()
            end)
        end
    end
end

Refill = function()
    if not (card and card:IsShown() and showing) then return end
    local d
    if showing.poster then d = GK.PosterCard(showing.poster) else d = GK.RecordCard(showing.record, showing.unit) end
    if d then Fill(d) else card:Hide() end
end

local function Open(d)
    if not card then Build() end
    Fill(d)
    card:Show()
    card:Raise()
    GK.Sound("IG_ABILITY_PAGE_TURN")
end

--- The wanted poster for an enemy player. t = { key, guid, c, r, l, unit }.
function GK.ShowPoster(t)
    if not (t and t.key) then return end
    showing = { poster = t }
    Open(GK.PosterCard(t))
end

--- A guildie's record (or yours). unit: the unit it was opened from, for their face.
function GK.ShowRecord(key, unit)
    local d = GK.RecordCard(key, unit)
    if not d then return end
    showing = { record = d.key, unit = unit }
    Open(d)
end

-- ---------------------------------------------------------------------------
-- The game's right-click menu on a player
-- ---------------------------------------------------------------------------
-- Menu.ModifyMenu is how the game lets addons add to its menus: our part runs after Blizzard's own
-- entries are built, and adds its lines at the end. Nothing of Blizzard's is replaced or wrapped.
-- An enemy player always gets two: the poster, and the kill order on them. A friendly player gets the
-- record line only when there is a record: you, or a guildie on the board.
local FRIENDLY = { "SELF", "PLAYER", "PARTY", "RAID_PLAYER", "RAID", "FRIEND", "COMMUNITIES_GUILD_MEMBER", "GUILD" }

--- A name from the menu's context: a plain string the client lets us read, or nil.
local function Text(v)
    if type(v) ~= "string" or GK.Secret(v) or v == "" then return nil end
    return v
end

local function AddLine(root, fn, also, alsoFn)
    if root.CreateDivider then root:CreateDivider() end
    root:CreateButton(LABEL, fn)
    if also then root:CreateButton(also, alsoFn) end
end

--- Who a friendly menu is about, as a key: from its unit, else the name it was opened on (a chat
--- line's full "Name-Realm" before the menu split it, then the plain name), else its GUID.
function GK.MenuKey(ctx)
    if type(ctx) ~= "table" then return nil end
    local unit = Text(ctx.unit)
    if unit then return LIB.UnitKey(unit), unit end
    local name = Text(ctx.chatTarget) or Text(ctx.name)
    if name then return GK.KeyOf(name), nil end
    local guid = Text(ctx.guid)
    if guid and GetPlayerInfoByGUID then
        local ok, _, _, _, _, _, gname, realm = pcall(GetPlayerInfoByGUID, guid)
        if ok then return GK.KeyOf(Text(gname), Text(realm)), nil end
    end
    return nil
end

local function OnEnemyMenu(_, root, ctx)
    if not (GK.db and GK.db.unitMenu and GK.char) or type(ctx) ~= "table" then return end
    local unit = Text(ctx.unit)
    local t = unit and GK.ReadUnit(unit)   -- an enemy player we can tell apart, or nil
    if not t then return end
    t.unit = unit
    -- and the kill order itself, one click from the enemy: opening the ledger to post one was too much
    -- work (the owner, 2026-11-05). The label says which of the sheet's three cases it will open.
    AddLine(root, function() GK.ShowPoster(t) end, GK.PostLabel(t), function() GK.OpenPost(t) end)
end

local function OnFriendlyMenu(_, root, ctx)
    if not (GK.db and GK.db.unitMenu and GK.char) then return end
    local key, unit = GK.MenuKey(ctx)
    if not (key and GK.HasRecord(key)) then return end
    AddLine(root, function() GK.ShowRecord(key, unit) end)
end

function GK.StartProfiles()
    LIB.Listen("GRUDGEKEEPER_CHANGED", Refill)
    if not (Menu and Menu.ModifyMenu) then return end
    -- pcall: a menu tag this client doesn't have must not stop the others
    pcall(Menu.ModifyMenu, "MENU_UNIT_ENEMY_PLAYER", OnEnemyMenu)
    for _, which in ipairs(FRIENDLY) do pcall(Menu.ModifyMenu, "MENU_UNIT_" .. which, OnFriendlyMenu) end
end
