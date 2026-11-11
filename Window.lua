-- Grudgekeeper - the window (/grudge, the minimap button): the Grudgekeeper's ledger, a sheet of parchment
-- in the game's own frame (SettingsFrameTemplate, which Forever draws in bronze), as Guildhall's window is.
--   The game's tabs under the frame, one per page of GK.LedgerPages: Kill orders, Leaderboard, Grudges,
--   Marked and News, then a step apart Shame and Kudos (NotesUI.lua adds the three lists).
--   On the left that page's table; on the right the row you clicked - an enemy's wanted poster, a
--   guildie's record (Profile.lua writes both, for the small cards and for here).
-- The red arrow beside the X (the spells panel's) folds it to one page: the table, and a click on a row
-- turns that page to the row, with Back to return. GK.db.ledgerFolded keeps the choice.
-- Nothing here ever opens by itself: this is where you come to look.
-- It was an open book until 2026-11-06 ("for mye problemer med custom design med boka", the owner): the
-- book's art had no place for the game's X, tabs or buttons, and everything laid on it looked stuck on.
-- The art: Media/sheet_wide and sheet_single (the parchment), rank_1..3 (the top three's seals),
-- portrait_ring.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local TITLE_FONT = "Fonts\\MORPHEUS.ttf"
local TEXT_FONT = "Fonts\\FRIZQT__.TTF"

-- The skin's colours and drawing (Core.lua): the same tables every skinned window holds, so a switch of
-- skin redraws all of them.
local INK, FADED, BLOOD = GK.INK, GK.FADED, GK.BLOOD
-- A grudge's score (FillRow): you leading in a dark olive, they in blood, a tie in ink, the other number
-- and the dash in the page's faded ink. As hex for the |c codes inside one string, made at each fill: a
-- skin switch changes the colours in place. A paler brown, "9a8462", left "1 - 0" "nesten usynlig" (the
-- owner, 2026-11-07).
local LEAD_YOU = { 0.31, 0.37, 0.07 }
local function Hex(c)
    local function B(v) return math.floor(v * 255 + 0.5) end
    return ("%02x%02x%02x"):format(B(c[1]), B(c[2]), B(c[3]))
end
local Ink, Paint, Wash = GK.Ink, GK.Paint, GK.Wash

-- The window, in UI units. A page is the list or the card; open, two pages side by side, folded one.
-- Laid out as Guildhall's window is: the sheet where the template's backdrop goes (7,-18 to -3,3), the
-- pages clear of the frame's edges and under its title bar. The pages kept the book's size, so what is
-- written on them sits as it did.
local PAGE_W, PAGE_H = 368, 496
local FX, FY, FGAP, FB = 20, 34, 16, 14
local OPEN = { W = 2 * FX + 2 * PAGE_W + FGAP, H = FY + PAGE_H + FB, x = FX, y = FY }    -- 792 x 544
OPEN.x2 = FX + PAGE_W + FGAP                         -- where the right-hand page starts
local FOLDED = { W = 2 * FX + PAGE_W, H = OPEN.H, x = FX, y = FY, x2 = FX }               -- 408 x 544
-- Rows of 38 with a faint stripe on every other one, as previewed (2026-11-06): 32 with a ruled line under
-- each read as a column of text. Nine fit between the headings and the foot, where Letters and Settings are.
local ROW_H, ROWS = 38, 9
local FACE = 30                                      -- a row's portrait; 26 blended into the page
-- Where a row's name starts: after its face, and on the leaderboard after its rank as well. Every page
-- kept the rank's room until 2026-11-07, which pushed their rows far to the right ("radene er skjøvet
-- veldig til høyre", the owner); the name's heading, at 48, now stands over the name.
local NAME_X, NAME_X_RANKED = 44, 74
local LIST_TOP = 96                                  -- the first row, down from the page's top
-- the right-hand column stops short of the row's end: folded, room for the » that says a click turns
-- the page (they ran into each other in the preview)
local COL1, COL2, COL_WIDE, COL_RIGHT = 232, 266, 196, PAGE_W - 36
local SCORE_X = COL_RIGHT - 34                       -- the middle of a grudge's score ("0 - 1")
local SUGGEST = 5            -- with no open order, who killed us most: this many, on the orders page
-- How far a list runs: its first LIST_MAX rows, about three pages, and under the open kill orders the
-- CLOSED_MAX closed last. A list ran to every row the store holds - 200 on Most wanted, 500 on the
-- leaderboard: "vi kan ikke ha evig pages heller. på most wanted og alt mulig" (the owner, 2026-11-10).
-- Only the pages stop: the store keeps what it kept, and posters, tooltips and warnings know everyone.
local LIST_MAX, CLOSED_MAX = 25, 10
GK.LIST_MAX = LIST_MAX       -- for the pages other files add (NotesUI.lua)
local TAB_GAP, GROUP_GAP = 3, 16                     -- between two tabs; and before the friendly pages, or Friends
-- How far up the tabs go, behind the frame's bottom edge. The game's own windows put them 2 up and over
-- the edge, which here read as buttons set under the book: "føler ikke tabsene henger helt ordentlig på?"
-- (the owner, 2026-11-08). The edge is 11 deep (rows 30-40 of the owner's screenshot). 10 up hid their tops
-- behind it and they hung from the book, but short: "de er litt lave, trenger ikke være så langt inn under"
-- (the owner, the same day). 6 up, half way.
local TAB_TUCK = 6
-- They are drawn in Forever's heavy tab art, not the game's bottom tabs: those (uiframe-tab-*-c60) have one
-- thin line where the frame's edge has a double one about 6 deep - "de ikke er like tykke i border som selve
-- ramma" (the owner, 2026-11-08). ui-frame-metal-Tabs-c60 is 60 x 60 (and a 2x copy): the same double
-- line, about 6 deep, square on its left side, its right corners cut off (looked at in the art, 2026-11-08).
-- Turned a quarter clockwise it is a bottom tab - the square side meets the frame, the cut corners hang
-- below. HEAVY_CUT leaves off the band along its square side, as the frame's edge is where a tab starts;
-- HEAVY_CORNER keeps the cut corners whole at any width. Its dark ground (-BG-) comes with it, and its
-- yellow glow (-Glow-), full on the chosen tab and fainter on hover (HeavyTab). The glow fades in from the
-- square side as far as 17 (GLOW_CUT): cut at 8 like the line, the rest drew a yellow bar under the edge.
local HEAVY = { ground = "ui-frame-metal-Tabs-BG-c60", edge = "ui-frame-metal-Tabs-c60", glow = "ui-frame-metal-Tabs-Glow-c60" }
local HEAVY_SIZE, HEAVY_CUT, GLOW_CUT, HEAVY_CORNER, HOVER_ALPHA = 60, 8, 17, 16, 0.45
local GLOW_FADE = 6          -- how far down the glow comes in from nothing, below the frame's edge (HeavyTab)
local TAB_H, TAB_H_ON = 36, 42      -- the tab's art, and the chosen tab's, longer: the game's own two heights
-- The text in the middle of what shows between the frame's edge and the art's bottom line, and clear of
-- its side lines and glow: "text er litt overlap med gløden og kantene på knappene" (the owner,
-- 2026-11-08). Measured on that screenshot: the inside runs from 4 to 27 down a tab (to 33 down the
-- chosen one, 6 longer), and the words' capitals stood at 14 to 21 (17 to 24 chosen), their tails to 24
-- (27): 3 up puts as much room over the capitals as under the tails. The game's
-- own tab puts its words 10 from each side (TAB_SIDES_PADDING 20 for both, SharedUIPanelTemplates.lua),
-- which in this art is on its 2-to-8 line and in the 8-to-17 glow: TAB_PAD more gives 16 a side.
local TAB_TEXT_Y, TAB_TEXT_Y_ON = 1, -2
local TAB_PAD = 12
-- Folded the tabs hang down the frame's right side instead, the art as it lies: under the one page they
-- were cut to "Lead..." and "Most..." ("collapsed så legger vi tabs på høyre side nedover isteden", the
-- owner, 2026-11-10). A side tab is as deep as a bottom tab is tall - the button's own 32
-- (PanelTabButtonTemplate, SharedUIPanelTemplates.xml) - so what is on it sits as far out from the edge.
-- The first starts under the title bar, level with the page. On each an icon, its name on the mouse: its
-- words turned to run down it were still cut ("Leade...") and hard to read ("teksten er for lav. men
-- kanskje vi kunne funnet noe gode ikoner isteden?", the owner, the same day). Long enough for the art's two
-- corners (16 each) and the icon between them.
local TAB_BUTTON_H, SIDE_TOP, SIDE_LEN, TAB_ICON = 32, 34, 46, 22
-- The icons: the ledger's own marks where it has one - the skull seal an order puts over a nameplate, the
-- gold seal the leaderboard's first wears - and the game's elsewhere, cut round like them. Every one is in
-- Forever's live build 70790 (manifestinterfacedata). A page another file adds brings its own (def.icon).
local ICONS = "Interface\\Icons\\"
local SWAP_ICON = { Friends = ICONS .. "INV_Misc_GroupNeedMore", Enemies = MEDIA .. "mark" }

--- Where each page of a list starts (0-based offsets into it): ROWS rows a page, but a heading is never
--- the last row of a page - it goes over to the next one with its rows. Turning a page goes from one
--- start to the next, so a page never shows what the page before showed: after 1-9 of 10 the last page
--- used to be 2-10, the list pushed back to fill it ("page turning burde jo ikke vise de samme", the
--- owner, 2026-11-07).
function GK.PageStarts(items)
    local starts, at = { 0 }, 0
    while at + ROWS < #items do
        local nextAt = at + ROWS
        if items[nextAt] and items[nextAt].header and nextAt - 1 > at then nextAt = nextAt - 1 end
        starts[#starts + 1] = nextAt
        at = nextAt
    end
    return starts
end

--- The page after (dir 1) or before (dir -1) the one that starts at `offset`; the same one at either end.
function GK.TurnPage(starts, offset, dir)
    starts = starts or { 0 }
    local at = 1
    for i, s in ipairs(starts) do
        if s <= offset then at = i end
    end
    return starts[math.max(1, math.min(#starts, at + dir))]
end

local win
local tab = 1
local weekly = true          -- the leaderboard shows this week until you ask for all time
local offset = 0             -- the first row shown, per the list as it stands
local selected = {}          -- [tab] = the key of the row whose detail is shown
local turned = false         -- folded: the page shows the detail, not the list

--- The book's art toned down: the generated parchment was "veldig bright" in the game. A part
--- desaturation and a darker vertex colour, the same on the book, the sheets and the leather tabs, so
--- nothing stands out brighter than the rest (previewed 2026-11-05: 0.45/0.78 went grey).
local TONE_D, TONE_M = 0.30, 0.86
local function Tone(tex, r, g, b)
    tex:SetDesaturation(TONE_D)
    tex:SetVertexColor((r or 1) * TONE_M, (g or 1) * TONE_M, (b or 1) * TONE_M)
end

local function Plural(n, word) return ("%d %s%s"):format(n, word, n == 1 and "" or "s") end

--- A text's own width, not cut to its box: GetStringWidth on a one-line string with a width set can
--- answer the box, which would always "fit".
local function TextWidth(fs)
    local w = fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()
    return w or fs:GetStringWidth() or 0
end

local function Folded() return GK.db and GK.db.ledgerFolded == true end

-- ---------------------------------------------------------------------------
-- What each page lists. An item: { key, name, sub, rank, seal, face = { key, rf, sx, c }, c1, c2, wide,
-- right, rightColour, faded, mine, own, ts, votes, header, select = { kind = "poster", t, order } or
-- { kind = "record", key } or { kind = "card", make } }
-- mine tints the row; own only says the row is yours, for Only mine; votes, bounty, you and they are the
-- numbers a column heading sorts by (GK.SortItems), ts when it happened.
-- ---------------------------------------------------------------------------
local STATE_WORD = { d = "FULFILLED", p = "PAID", x = "WITHDRAWN", e = "EXPIRED" }

local function PosterSpec(key, x, order)
    return { kind = "poster", order = order,
        t = { key = key, guid = x and x.guid, c = x and x.c, r = x and x.r, l = x and x.l } }
end

--- What they are, short, for after a row's name: "35 Orc Rogue". nil when we know nothing.
local function Short(l, c, r, sx)
    local s = GK.Describe(l, c, r, sx):gsub("^Level ", "")
    return s ~= "" and s or nil
end

-- The closed orders fold away under their heading, a click from showing: the page is for the open ones
-- ("history med kill orders som er lukket kan kanskje bare være en knapp eller noe? litt færre ting å gå
-- igjennom", the owner, 2026-11-10). Folded again at every login: a look back, not a setting.
local showClosed = false

--- The orders the page lists. open: the open ones, the biggest bounty first, LIST_MAX of them and any of
--- yours past those - an order you posted or put gold in never drops off. closed, latest first: those that
--- still ask something of you - a bounty you owe on it, or yours to tell the guild, its card's buttons
--- (DetailCard) - and, unfolded, the CLOSED_MAX latest of the rest. more: how many of those unfolding shows.
local function ListedOrders(me)
    local open, closed, nOpen, others, owing = {}, {}, 0, 0, {}
    for _, e in ipairs(GK.Owed()) do owing[e.o] = true end
    for _, o in ipairs(GK.AllOrders()) do
        if o.state == "o" then
            nOpen = nOpen + 1
            if nOpen <= LIST_MAX or (me and (o.by == me or (o.pot and o.pot[me]))) then open[#open + 1] = o end
        elseif owing[o] or GK.CanTellOrder(o) then
            closed[#closed + 1] = o                                  -- never folded away: it wants you
        else
            others = others + 1
            if showClosed and others <= CLOSED_MAX then closed[#closed + 1] = o end
        end
    end
    return open, closed, math.min(others, CLOSED_MAX)
end

--- One order's row on the page, open or closed.
local function OrderRow(o, me)
    local pot, backers = GK.Pot(o)
    local it = { key = "o:" .. o.key, name = GK.Show(o.n), face = { key = o.n, c = o.c, r = o.r },
        select = PosterSpec(o.n, o, o), desc = Short(o.l, o.c, o.r, GK.SexOf(o.n, o.sx)), ts = o.t,
        own = me and (o.by == me or o.doneBy == me or (o.pot and o.pot[me])) or nil }
    if o.state == "o" then
        it.bounty = pot
        it.right = pot > 0 and GK.Coins(pot) or "honour"
        -- your own order by you, as its card says: "by Critical Mango" over a card's "Posted by You"
        local byMe = o.by == me
        local bits = { o.auto and (byMe and "by your death" or ("by %s's death"):format(GK.Show(o.by)))
            or ("by " .. (byMe and "you" or GK.Show(o.by))) }
        if backers > 0 then bits[#bits + 1] = Plural(backers, "backer") end
        -- where a guildie saw them last: what a hunter needs, and every guildie is one
        if o.seen then
            bits[#bits + 1] = o.seen.z and ("seen in %s, %s"):format(o.seen.z, GK.Ago(o.seen.t))
                or ("seen " .. GK.Ago(o.seen.t))
        end
        it.sub = table.concat(bits, " - ")
    else
        it.faded, it.right, it.rightColour = true, STATE_WORD[o.state] or "", BLOOD
        it.sub = (o.doneBy and ("by " .. (o.doneBy == me and "you" or GK.Show(o.doneBy)) .. " - ") or "")
            .. GK.Ago(o.paidAt or o.doneAt)
    end
    return it
end

local function OrderItems()
    local items, me = {}, LIB.Me()
    local open, closed, more = ListedOrders(me)
    for _, o in ipairs(open) do items[#items + 1] = OrderRow(o, me) end
    -- No open order: the first page of the ledger was a blank one (the owner, 2026-11-06). Who has killed
    -- the guild most stands in - the ones you would put a price on - each a click from their poster and
    -- its Post a kill order.
    if #open == 0 then
        local wanted = GK.MostWanted()
        if #wanted > 0 then
            items[#items + 1] = { header = true, name = "Killed us most - no order yet" }
            for i = 1, math.min(#wanted, SUGGEST) do
                local e = wanted[i]
                items[#items + 1] = { key = "w:" .. e.key, name = GK.Show(e.key),
                    desc = Short(e.w.l, e.w.c, e.w.r, GK.SexOf(e.key, e.w.sx)),
                    face = { key = e.key, c = e.w.c, r = e.w.r }, wide = "killed us " .. e.total,
                    select = PosterSpec(e.key, e.w),
                    ts = e.w.last }
            end
        end
    end
    -- The closed orders under a heading of their own, folded: its word at the right shows them. What
    -- still wants you is there folded or not.
    if #closed > 0 or more > 0 then
        local head = { header = true, name = "Closed orders" }
        if more > 0 then
            head.order = showClosed and "hide" or ("show " .. more)
            head.clickTip = showClosed and "Click: fold the closed orders away" or "Click: show the latest closed orders"
            head.click = function() showClosed = not showClosed end
        end
        items[#items + 1] = head
        for _, o in ipairs(closed) do items[#items + 1] = OrderRow(o, me) end
    end
    -- Marked: enemies the guild marked to kill on sight, with no bounty and no end date (Guild Grudge's
    -- list). It had a tab of its own, one too many: kill orders and Most wanted say the rest ("most wanted
    -- og kill orders holder kanskje?", the owner, 2026-11-07). The word at its heading's right marks
    -- someone, as the tab's action did. The votes stay on the note's card: in this column they would
    -- read as a bounty.
    local marked = GK.NotesItems and GK.NotesItems("kos") or {}
    if #marked > 0 then
        items[#items + 1] = { header = true, name = "Marked", order = "mark someone",
            clickTip = "Mark an enemy to kill on sight, with no bounty", click = function() GK.OpenPicker("kos") end }
        for i = 1, math.min(#marked, LIST_MAX) do               -- the latest marked: the list's own order
            local it = marked[i]
            it.right = ""
            items[#items + 1] = it
        end
    end
    -- The watched guild: an enemy guild the guild knows, anyone of theirs near warns you (Notes.lua). An
    -- officer puts it on watch from the right-click menu on one of its players, or types its name in from
    -- the word at this heading's right, with none of theirs in sight ("la GM skrive inn et guildnavn", the
    -- owner, 2026-11-08); one at a time. The heading stays for an officer while none is watched, but not
    -- on a page with nothing else: there it would hide what the page says about posting, which says this
    -- too.
    local guilds = GK.WatchedGuildItems and GK.WatchedGuildItems() or {}
    local officer = GK.CanWatchGuild and GK.CanWatchGuild()
    if #guilds > 0 or (officer and #items > 0) then
        local head = { header = true, name = "Watched guild" }
        if officer then
            head.order = #guilds > 0 and "watch another" or "watch a guild"
            head.clickTip = "Type the name of an enemy guild: anyone of theirs near warns everyone"
            head.click = function() GK.OpenPicker("guild") end
        end
        items[#items + 1] = head
        for _, it in ipairs(guilds) do items[#items + 1] = it end
    end
    return items, "No kill orders. Post one with Post a kill order, at the top of this page - or right-click "
        .. "an enemy player and pick it there." .. (officer and " Put an enemy guild on watch with /grudge guild."
        or "")
end

local function BoardItems()
    local items, listed = {}, {}
    local function Add(r, p, k, d, rank)
        rank = rank or #items + 1
        listed[r.who] = true
        items[#items + 1] = { key = "b:" .. r.who, rank = rank, seal = rank <= 3 and p > 0,
            name = GK.Show(r.who), sub = GK.Title(r.total), face = { key = r.who, rf = r.rf, sx = r.sx, c = r.c },
            c1 = tostring(k), c2 = tostring(d), right = tostring(p), mine = r.me,
            select = { kind = "record", key = r.who } }
    end
    -- the top LIST_MAX, and you under them at your own place if you are further down
    for i, r in ipairs(GK.Board(weekly)) do
        if i <= LIST_MAX or r.me then Add(r, r.p, r.k, r.d, i) end
    end
    -- This week a short board fills its first page with the rest of the guild, at nothing yet: three rows
    -- and six empty ones under them looked like a list that hadn't loaded ("vis this week leaderboard folk
    -- med 0 poeng også", the owner, 2026-11-07). Only the first page - pages of zeros say nothing - and the
    -- best of all time first. The board itself (GK.Board, your place and "of N") counts only who scored.
    if weekly and #items < ROWS then
        for _, r in ipairs(GK.Board(false)) do
            if #items >= ROWS then break end
            if not listed[r.who] then Add(r, 0, 0, 0) end
        end
    end
    return items, ""
end

--- Who has killed the guild most, every one of them. A page of its own since 2026-11-07: under the
--- leaderboard they pushed it onto a second page ("en tab med most wanted og en tab med leaderboard",
--- the owner). The bounty column says what is on them now: gold, or an order for honour.
local function WantedItems()
    local items, me = {}, LIB.Me()
    for _, e in ipairs(GK.MostWanted()) do
        local o = GK.OrderOn(e.key)
        local pot = o and (GK.Pot(o)) or 0
        items[#items + 1] = { key = "w:" .. e.key, name = GK.Show(e.key),
            desc = Short(e.w.l, e.w.c, e.w.r, GK.SexOf(e.key, e.w.sx)),
            face = { key = e.key, c = e.w.c, r = e.w.r },
            sub = e.w.last and ("last kill " .. GK.Ago(e.w.last)) or nil,
            c1 = tostring(e.total), killed = e.total, bounty = pot,
            -- gold in the game's coins, as on the kill orders page; a red "85g" read as a word ("kjedelig at
            -- kill order bounty ikke vise gold icon", the owner, 2026-11-10). An order for honour in red.
            right = o and (pot > 0 and GK.Coins(pot) or "order") or "",
            rightColour = (o and pot == 0) and BLOOD or nil, select = PosterSpec(e.key, e.w), ts = e.w.last,
            own = me and e.w.victims[me] and true or nil }            -- Only mine: those who killed you
    end
    return items, "Nobody has killed the guild yet - not that the Grudgekeeper heard of."
end

-- How your grudges are ordered: the word at the right of their heading, clicked, goes to the next. The
-- page has no heading row to sort by - it stood over the page's own big headings (the owner, 2026-11-07).
local GRUDGE_ORDERS = { { "fought", "most fought first" }, { "recent", "latest first" }, { "name", "A to Z" } }
local grudgeOrder = 1

--- The order the Grudges page is in now, by its word: "fought", "recent" or "name".
function GK.GrudgeOrder() return GRUDGE_ORDERS[grudgeOrder][1] end

local function GrudgeItems()
    local items, c = {}, GK.char
    -- the last thing that happened with each of them: your log is newest first
    local lastOf = {}
    for _, e in ipairs(c.log) do
        if e.n and not lastOf[e.n] then lastOf[e.n] = e end
    end
    local foes = {}
    for k, v in pairs(c.foes) do
        if (v.k or 0) + (v.d or 0) > 0 then foes[#foes + 1] = { key = k, f = v, name = GK.Show(k) } end
    end
    local how = GRUDGE_ORDERS[grudgeOrder][1]
    local function Before(a, b, by)
        if by == "recent" then
            if (a.f.last or 0) ~= (b.f.last or 0) then return (a.f.last or 0) > (b.f.last or 0) end
        elseif by == "fought" then
            local x, y = (a.f.k or 0) + (a.f.d or 0), (b.f.k or 0) + (b.f.d or 0)
            if x ~= y then return x > y end
        end
        if a.name:lower() ~= b.name:lower() then return a.name:lower() < b.name:lower() end
        return a.key < b.key
    end
    -- LIST_MAX of them, the first by the order chosen; A to Z the latest met, put in that order - the
    -- first names of the alphabet would say nothing about who matters
    table.sort(foes, function(a, b) return Before(a, b, how == "name" and "recent" or how) end)
    for i = #foes, LIST_MAX + 1, -1 do foes[i] = nil end
    if how == "name" then table.sort(foes, function(a, b) return Before(a, b, "name") end) end
    if #foes > 0 then
        local nextOrder = GRUDGE_ORDERS[grudgeOrder % #GRUDGE_ORDERS + 1]
        items[#items + 1] = { header = true, name = "Your grudges", order = GRUDGE_ORDERS[grudgeOrder][2],
            clickTip = "Click: " .. nextOrder[2],
            click = function() grudgeOrder = grudgeOrder % #GRUDGE_ORDERS + 1 end }
    end
    for i = 1, #foes do
        local e = foes[i]
        local you, they = e.f.k or 0, e.f.d or 0
        -- what happened last, and where: "killed you 11 min ago · Ashenvale" says more than "last met"
        local last = lastOf[e.key]
        local sub
        if last then
            sub = (last.k == "K" and "you killed them " or "killed you ") .. GK.Ago(last.t)
                .. (last.z and (" \194\183 " .. last.z) or "")
        else
            sub = "last met " .. GK.Ago(e.f.last)
        end
        items[#items + 1] = { key = "f:" .. e.key, name = e.name, face = { key = e.key, c = e.f.c, r = e.f.r },
            desc = Short(e.f.l, e.f.c, e.f.r, GK.SexOf(e.key, e.f.sx)), sub = sub, score = { you, they },
            select = PosterSpec(e.key, e.f), you = you, they = they, ts = e.f.last, own = true }
    end
    if #c.log > 0 then items[#items + 1] = { header = true, name = "Lately" } end
    for i = 1, math.min(#c.log, LIST_MAX) do                   -- the latest: your log is newest first
        local e = c.log[i]
        local it ={ key = "l:" .. i, face = { key = e.n, c = e.c, r = e.r }, select = PosterSpec(e.n, e), ts = e.t, own = true,
            sub = table.concat({ e.z or "", GK.Ago(e.t) }, e.z and " - " or "") }
        if e.k == "K" then
            it.name = "Killed " .. GK.Show(e.n)
            it.right = (e.p or 0) > 0 and ("+%d"):format(e.p) or "no points"
        else
            -- the spell at the end of the line under the name, not in the right-hand column: there
            -- "Judgement of Righteousness" left the name "Slain by I..." and the place "Wetlands -..."
            -- (the owner, 2026-11-06). At the end it is what gets cut, if anything does.
            it.name = "Slain by " .. GK.Show(e.n)
            if e.s then it.sub = it.sub .. " - " .. e.s end
        end
        items[#items + 1] = it
    end
    return items, "No kills or deaths yet. Only the open world counts: dungeons and battlegrounds hide who is who."
end

-- What the news says, by kind: who, then whom. "AU" is a C whose poster's death posted it.
local SAID = { K = "%s killed %s", D = "%s fell to %s", F = "%s fulfilled the order on %s",
    C = "%s put a price on %s", AU = "%s death put a price on %s", T = "%s added to the pot on %s" }

--- A name by its first word: the character's own name, without the surname.
local function FirstName(key)
    local s = GK.Show(key)
    return s:match("^[^ ]+") or s                   -- not %S: see GK.SameName
end

local function NewsItems()
    local items = {}
    for i, e in ipairs(GK.Store().feed) do
        -- your own news says You: your full name and surname first left "Critical Mango killed Seedkek..."
        -- no room for whom (the owner, 2026-11-06)
        local mine = e.who ~= nil and LIB.IsMyStoredName(e.who)
        local kind = (e.kind == "C" and e.au) and "AU" or e.kind
        local said = SAID[kind]
        local line, short, right
        if said then
            local function Who(n)
                if kind == "AU" then return mine and "Your" or (n .. "'s") end
                return mine and "You" or n
            end
            -- an order got together: everyone who was there, the killing blow first (GK.WhoGotThem)
            local function Who2(show)
                local names = { Who(show(e.who)) }
                if kind == "F" and type(e.h) == "table" then
                    for _, k in ipairs(e.h) do names[#names + 1] = LIB.IsMyStoredName(k) and "you" or show(k) end
                end
                if #names == 1 then return names[1] end
                return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
            end
            -- the short form, for a line too long for its row (FillRow): first names only
            line = said:format(Who2(GK.Show), GK.Show(e.n))
            short = said:format(Who2(FirstName), FirstName(e.n))
        end
        if kind == "K" then
            right = (e.p or 0) > 0 and ("+%d"):format(e.p) or nil
        elseif kind == "F" then
            right = (e.p or 0) > 0 and GK.MoneyText(e.p) or nil
        elseif kind == "AU" then
            right = "honour"
        elseif kind == "C" then
            right = (e.p or 0) > 0 and GK.MoneyText(e.p) or "honour"
        elseif kind == "T" then
            right = GK.MoneyText(e.p or 0)
        end
        if line then
            items[#items + 1] = { key = "n:" .. i, name = line, short = short, face = { key = e.n, c = e.c }, right = right,
                sub = table.concat({ e.z or "", GK.Ago(e.t) }, e.z and " - " or ""), select = PosterSpec(e.n, e),
                ts = e.t, own = e.who and LIB.IsMyStoredName(e.who) or nil }
        end
    end
    return items, "Nothing yet. Kills, deaths and kill orders from everyone in your guild who runs Grudgekeeper "
        .. "show up here."
end

--- The leaderboard's resets-in text, after its links.
local function ResetText()
    local get = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
    local ok, secs = false, nil
    if get then ok, secs = pcall(get) end
    local days = ok and type(secs) == "number" and not GK.Secret(secs) and math.ceil(secs / 86400) or nil
    return days and ("-  resets in " .. Plural(days, "day")) or ""
end

--- The ledger's pages, in tab order; other files add theirs with GK.AddLedgerPage. A page is
--- { name, items = fn -> items, empty text, headings, sub = fn(items, all) -> text, links = fn -> { { text,
--- on, click } }, linksTail = fn -> text, sortable, max, side, add, icon, default = fn(items) -> the row chosen
--- when none is }. max: a sortable page with no section headings lists at most this many rows (GK.SortItems);
--- all, to sub, is how many there were before it. icon: the texture on its tab folded, down the frame's side.
--- headings: the column headings over the table, { text, x, justify, sort, tip }: a heading with a sort
--- (an item field: "name", or a number, the biggest first) sorts the page when clicked, and tip finishes
--- "Sort by ..." in its tooltip. sortable: the headings sort and Only mine shows. links: ink links under
--- the title. add: the page's own action, top right - { text, kind } opens the who-picker (Pick.lua) for
--- that kind. side: "right" puts the tab over the right page in the open book (the friendly lists);
--- anything else is over the left page. Folded, the page's group hangs down the frame's side. A page with links and a sub
--- line has the sub text after the links, on their line.
GK.LedgerPages = {
    { name = "Kill orders", items = OrderItems, icon = MEDIA .. "mark",
      headings = { { "Name", 48, nil, "name", "name, A to Z" }, { "Bounty", COL_RIGHT, "RIGHT", "bounty", "bounty" } },
      sortable = true, add = { text = "Post a kill order", kind = "order" },
      -- with nothing on the page at all, your own record rather than a blank page; otherwise the first
      -- open order, or the first of who killed us most (a closed order alone is not chosen by itself)
      default = function(items)
          for _, it in ipairs(items) do
              if not it.header then return nil end           -- a row, if only a closed order: none chosen
          end
          -- nothing but headings - the closed orders folded under theirs - is a page with nothing on it
          return { key = "me", select = { kind = "record", key = LIB.Me() } }
      end,
      sub = function()
          local rank, of = GK.MyRank()
          return ("%s  -  you: %s, #%d of %d"):format(Plural(#GK.OpenOrders(), "open order"),
              Plural(GK.char.points, "point"), rank, of)
      end },
    { name = "Leaderboard", items = BoardItems, icon = MEDIA .. "rank_1",
      headings = { { "#", 12 }, { "Name", NAME_X_RANKED + 4 }, { "K", COL1, "CENTER" }, { "D", COL2, "CENTER" },
          { "Points", COL_RIGHT, "RIGHT" } },
      links = function()
          return { { text = "This week", on = weekly, click = function() weekly = true end },
                   { text = "All time", on = not weekly, click = function() weekly = false end } }
      end,
      linksTail = ResetText,
      default = function(items)
          for _, it in ipairs(items) do
              if it.mine then return it end
          end
      end },
    { name = "Most wanted", items = WantedItems, sortable = true, max = LIST_MAX,
      icon = ICONS .. "Ability_Hunter_SniperShot",          -- the hunter's mark: marked to be hunted
      headings = { { "Name", 48, nil, "name", "name, A to Z" },
          { "Killed us", COL1, "CENTER", "killed", "how often they killed us" },
          { "Bounty", COL_RIGHT, "RIGHT", "bounty", "bounty" } },
      add = { text = "Post a kill order", kind = "order" },
      sub = function() return "Who has killed the guild most" end },
    -- no heading row: each grudge says its own score, and the order is a word on the section's line
    { name = "Grudges", items = GrudgeItems, headings = {}, icon = ICONS .. "Ability_DualWield",
      sub = function() return "Who you have a history with" end,       -- not everyone: LIST_MAX of them
      default = function() return { key = "me", select = { kind = "record", key = LIB.Me() } } end },
    { name = "News", items = NewsItems, sortable = true, max = LIST_MAX, icon = ICONS .. "INV_Scroll_03",
      headings = { { "What happened", 48 } },
      sub = function() return "What the guild has been up to" end },
}

--- Adds a page, after the ledger's own unless def.before names the page (by its name) to sit in front of;
--- a name nobody has goes last. Only before the book is first built: the tabs are made then. Pages are
--- opened by number only for the first two (GK.OpenWindow(1), (2): Kill orders and Leaderboard), so a
--- page put at 4 or later moves nothing that is opened by number - find a page by its def, not its index.
function GK.AddLedgerPage(def)
    assert(not win, "GK.AddLedgerPage: the ledger is already built")
    for i, page in ipairs(GK.LedgerPages) do
        if def.before and page.name == def.before then
            table.insert(GK.LedgerPages, i, def)
            return
        end
    end
    table.insert(GK.LedgerPages, def)
end

--- What a page is sorted by: the sort of the heading clicked last on it (GK.db.sortBy[page name]), or nil
--- for the page's own order - also when the saved one is no heading of the page (any more).
function GK.SortKey(page)
    local key = page and page.sortable and GK.db.sortBy and GK.db.sortBy[page.name]
    if key == nil then return nil end
    for _, h in ipairs(page.headings or {}) do
        if h[4] == key then return key end
    end
    return nil
end

--- A click on a heading: sort the page by it, or, clicked again, back to the page's own order.
function GK.SortBy(page, key)
    if type(GK.db.sortBy) ~= "table" then GK.db.sortBy = {} end
    GK.db.sortBy[page.name] = (GK.SortKey(page) ~= key) and key or nil
end

--- A page's rows in the order its clicked heading asks for, and only yours with GK.db.mineOnly; the page's
--- own order, without Only mine, is left alone. Each section is sorted on its own, under its heading: the
--- open kill orders among themselves, the closed ones folded under theirs - sorted together, a FULFILLED
--- stood among the open orders ("sortering i kill orders burde ikke ta med fulfulled og withdrawn", the
--- owner, 2026-11-10). A heading Only mine left with no rows goes. Names go A to Z, numbers the biggest
--- first; ties go A to Z. A page with a max keeps that many, the first in its own order, after Only mine and
--- before the sort: Most wanted by name is still the 25 who killed us most, A to Z, and Only mine finds the
--- one who killed you if they are 40th. Returns a new list, or the same one untouched, and how many rows
--- it had before the max.
function GK.SortItems(items, page)
    local key, mineOnly = GK.SortKey(page), GK.db.mineOnly == true
    local max = page and page.max
    if not (page and page.sortable) or (not key and not mineOnly and not max) then return items, #items end
    -- the sections: the rows before the first heading, then each heading with the rows under it
    local section, at, all = { rows = {} }, {}, 0
    local sections = { section }
    for _, it in ipairs(items) do
        if it.header then
            section = { head = it, rows = {} }
            sections[#sections + 1] = section
        elseif not mineOnly or it.own or it.mine then
            all = all + 1
            if not max or all <= max then
                section.rows[#section.rows + 1] = it
                at[it] = all
            end
        end
    end
    local function SortName(it) return (it.name or ""):lower() end
    local function Before(a, b)
        if key ~= "name" then
            local x, y = tonumber(a[key]) or 0, tonumber(b[key]) or 0
            if x ~= y then return x > y end
        end
        local na, nb = SortName(a), SortName(b)
        if na ~= nb then return na < nb end
        return at[a] < at[b]                   -- table.sort needs a strict order, or it can error
    end
    local out = {}
    for _, s in ipairs(sections) do
        if key then table.sort(s.rows, Before) end
        if s.head and (#s.rows > 0 or not mineOnly) then out[#out + 1] = s.head end
        for _, it in ipairs(s.rows) do out[#out + 1] = it end
    end
    return out, all
end

-- ---------------------------------------------------------------------------
-- The detail: what the right page (or the turned page) shows
-- ---------------------------------------------------------------------------
--- The card for a selected row. A closed order says so, and what you still owe on it.
local function DetailCard(spec)
    if not spec then return nil end
    if spec.kind == "card" then return spec.make() end
    if spec.kind == "record" then
        local d = GK.RecordCard(spec.key)
        if d then d.buttons = {} end            -- its one button opens the leaderboard: we are in it
        return d
    end
    local d = GK.PosterCard(spec.t, true)
    local o = spec.order
    if o and o.state ~= "o" then
        local word = STATE_WORD[o.state] or "CLOSED"
        local rows = { { "Closed", ("%s%s, %s"):format(word:sub(1, 1) .. word:sub(2):lower(),
            o.doneBy and (" by " .. GK.WhoGotThem(o.doneBy, o.helpers)) or "", GK.Ago(o.paidAt or o.doneAt)) } }
        -- what we owe on it: a part to each hunter, the bounty shared (GK.Owed)
        local owe = {}
        for _, e in ipairs(GK.Owed()) do
            if e.o == o then owe[#owe + 1] = ("%s %s"):format(GK.Show(e.to), GK.MoneyText(e.share)) end
        end
        if #owe > 0 then
            rows[2] = { "You owe", ("%s - mail or trade it, and it is marked paid."):format(#owe == 1 and owe[1]
                or (table.concat(owe, ", ", 1, #owe - 1) .. " and " .. owe[#owe])) }
            d.buttons = { { "Mark as paid", function() GK.PayShare(o) end } }
        end
        -- yours to tell, by your kill or with you there: here too, since a read letter is gone (GK.TellOrder)
        if GK.CanTellOrder(o) then
            d.buttons = { { "Tell the guild", function() GK.TellOrder(o) end }, d.buttons and d.buttons[1] }
        end
        -- the order's own section first, and the kicker says it is over ("ORDER FULFILLED") - unless a
        -- newer order on them is open, which keeps its own WANTED and its own section
        local open = d.title == "WANTED"
        -- with a newer order open, this one after that one's order and pot, before the History
        local at = 1
        if open then
            at = #d.rich.sections + 1
            for i, sec in ipairs(d.rich.sections) do
                if sec.head == "History" then
                    at = i
                    break
                end
            end
        end
        table.insert(d.rich.sections, at,
            { head = open and "An earlier order" or "The order", kind = "facts", rows = rows })
        -- who put what in it, and who has paid: only when it is the order the card is about, so the
        -- newer order's pot and the History keep their room
        local pot = not open and GK.PotRows(o)
        if pot then table.insert(d.rich.sections, at + 1, { head = "The pot", kind = "facts", rows = pot }) end
        if not open then d.rich.kicker = "Order " .. word:lower() end
    end
    return d
end

--- "All time: 31 kills, 12 deaths." reads as a two-column row: a short label, then the rest.
local function Split(line)
    local label, value = line:match("^([^:,]+): (.+)$")
    if label and #label <= 14 then return label, value end
    return nil, line
end

-- ---------------------------------------------------------------------------
-- Building the book
-- ---------------------------------------------------------------------------
--- A round portrait in the bronze ring (Letters.lua, shared with the sheets' heads).
local MakePortrait = GK.MakePortrait

local Refresh                -- below; the rows and buttons call it

local function Select(item)
    selected[tab] = item.key
    if Folded() then turned = true end
    GK.Sound("IG_ABILITY_PAGE_TURN")
    Refresh()
end

local function BuildRow(parent, i)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 4, -(LIST_TOP + (i - 1) * ROW_H))
    row:SetPoint("RIGHT", parent, "RIGHT", -6, 0)
    -- every other row a shade darker, so the eye keeps its line across (Refresh fills from the top, so
    -- the stripes stay put while the rows turn)
    row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, -1)
    row.stripe:SetAllPoints()
    Paint(row.stripe, "stripe")
    row.stripe:SetShown(i % 2 == 0)
    row.wash = row:CreateTexture(nil, "BACKGROUND")
    row.wash:SetAllPoints()
    row.rule = row:CreateTexture(nil, "BORDER")            -- under a header row ("Most wanted") only
    Paint(row.rule, "rule")
    row.rule:SetHeight(1)
    row.rule:SetPoint("BOTTOMLEFT", 4, 0)
    row.rule:SetPoint("BOTTOMRIGHT", -4, 0)
    row.mark = row:CreateTexture(nil, "ARTWORK")           -- the chosen row's red bar, at its start
    Paint(row.mark, "blood", 0.9)
    row.mark:SetPoint("TOPLEFT")
    row.mark:SetPoint("BOTTOMLEFT")
    row.mark:SetWidth(3)
    row.seal = row:CreateTexture(nil, "ARTWORK")
    row.seal:SetSize(24, 24)
    row.seal:SetPoint("LEFT", 2, 0)
    -- every font string gets its font HERE, not when filled: the game refuses SetText - even SetText("")
    -- - on one that has none, and a header row is filled before any player row ever was (2026-11-05)
    row.rank = row:CreateFontString(nil, "OVERLAY")
    Ink(row.rank, FADED, TITLE_FONT, 13)
    row.rank:SetPoint("CENTER", row.seal, "CENTER", 0, 0)
    row.face = MakePortrait(row, FACE)
    row.face.tex:SetPoint("CENTER", row, "LEFT", NAME_X - 19, 0)        -- FillRow moves it for a rank
    row.name = row:CreateFontString(nil, "ARTWORK")
    -- the name in the game's plain type: Morpheus' small capitals at this size were "litt vanskelig å
    -- lese" in a list (the owner, 2026-11-06); the titles over the lists and on the card keep it
    Ink(row.name, INK, TEXT_FONT, 13)
    row.name:SetPoint("TOPLEFT", NAME_X, -4)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    -- what they are, in small type after the name ("35 Orc Rogue"), when it fits beside it
    row.desc = row:CreateFontString(nil, "ARTWORK")
    Ink(row.desc, FADED, TEXT_FONT, 10)
    row.desc:SetJustifyH("LEFT")
    row.desc:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "ARTWORK")
    Ink(row.sub, FADED, TEXT_FONT, 11)
    row.sub:SetPoint("TOPLEFT", NAME_X, -22)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    local function Col(x, justify)
        local fs = row:CreateFontString(nil, "ARTWORK")
        Ink(fs, INK, TEXT_FONT, 12)
        if justify == "RIGHT" then fs:SetPoint("RIGHT", row, "LEFT", x - 4, 0)
        elseif justify == "CENTER" then fs:SetPoint("CENTER", row, "LEFT", x - 4, 0)
        else fs:SetPoint("LEFT", row, "LEFT", x - 4, 0) end
        return fs
    end
    row.c1, row.c2 = Col(COL1, "CENTER"), Col(COL2, "CENTER")
    row.wide, row.right = Col(COL_WIDE), Col(COL_RIGHT, "RIGHT")
    -- A grudge's score, read like a match's: "0 - 1", the leader's number in colour, and under it who
    -- leads. Two bare columns of 0 and 1 under YOU and THEY were "litt dårlig vist" (the owner,
    -- 2026-11-07), and their heading row stood over the page's own big headings.
    -- In the game's plain type: Morpheus' thin strokes left the faded number and the dash all but gone.
    row.score = row:CreateFontString(nil, "ARTWORK")
    Ink(row.score, INK, TEXT_FONT, 15)
    row.score:SetPoint("CENTER", row, "LEFT", SCORE_X, 5)
    row.lead = row:CreateFontString(nil, "ARTWORK")
    Ink(row.lead, FADED, TEXT_FONT, 10)
    row.lead:SetPoint("CENTER", row, "LEFT", SCORE_X, -10)
    -- a heading's own order, a word to click at its right ("most fought first"), where a page has no
    -- heading row
    row.order = row:CreateFontString(nil, "ARTWORK")
    Ink(row.order, FADED, TEXT_FONT, 10)
    row.order:SetPoint("BOTTOMRIGHT", row, "BOTTOMLEFT", COL_RIGHT - 4, 6)
    row.open = row:CreateFontString(nil, "ARTWORK")        -- folded: "this turns the page"
    Ink(row.open, FADED, TEXT_FONT, 13)
    row.open:SetPoint("RIGHT", -4, 0)
    row.open:SetText("\194\187")                            -- », in the game's Latin-1 fonts
    row:SetScript("OnClick", function(self)
        local it = self.item
        if it and not it.header then
            Select(it)
        elseif it and it.click then            -- a heading's order word: the next order
            it.click()
            Refresh()
        end
    end)
    row:SetScript("OnEnter", function(self)
        local it = self.item
        if it and not it.header and not self.chosen then Wash(self.wash, 0.07) end
        if it and it.header and it.click then
            Wash(self.wash, 0.05)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(it.clickTip or "Click to sort", 1, 1, 1)
            GameTooltip:Show()
            self.tipped = true
        elseif it and not it.header and self.cut then
            -- a line the row had to shorten or cut, whole (FillRow)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(it.name or "", 1, 1, 1, true)
            if it.sub and it.sub ~= "" then GameTooltip:AddLine(it.sub, 0.8, 0.8, 0.8, true) end
            GameTooltip:Show()
            self.tipped = true
        end
    end)
    row:SetScript("OnLeave", function(self)
        if self.fill then self.fill() end
        if self.tipped then
            self.tipped = false
            GameTooltip:Hide()
        end
    end)
    return row
end

local function FillRow(row, it, chosen)
    row.item, row.chosen = it, chosen
    local function Tint()
        if chosen then Wash(row.wash, 0.14)
        elseif it.mine then Wash(row.wash, 0.06)
        else row.wash:SetColorTexture(0, 0, 0, 0) end
    end
    row.fill = Tint
    Tint()
    if it.header then
        Ink(row.name, BLOOD, TITLE_FONT, 16)
        row.name:SetPoint("TOPLEFT", 12, -12)
        row.name:SetWidth(PAGE_W - 24)
        row.name:SetText(it.name)
        row.desc:SetText("")
        row.sub:SetText("")
        row.seal:Hide()
        row.rank:SetText("")
        row.face:SetShown(false)
        row.mark:Hide()
        row.open:Hide()
        row.rule:Show()
        row.c1:SetText("") row.c2:SetText("") row.wide:SetText("") row.right:SetText("")
        row.score:SetText("") row.lead:SetText("")
        row.order:SetText(it.order or "")
        row.cut = false
        return
    end
    row.rule:Hide()
    row.order:SetText("")
    -- the score: the leader's number in their colour, the other faded, and who leads under it
    local sc = it.score
    if sc then
        local you, they = sc[1], sc[2]
        local tie, dim = Hex(INK), Hex(FADED)
        local mine = you > they and Hex(LEAD_YOU) or (you > 0 and you == they and tie or dim)
        local theirs = they > you and Hex(BLOOD) or (they > 0 and you == they and tie or dim)
        row.score:SetText(("|cff%s%d|r |cff%s-|r |cff%s%d|r"):format(mine, you, dim, theirs, they))
        if you > they then
            row.lead:SetText("you lead")
            row.lead:SetTextColor(LEAD_YOU[1], LEAD_YOU[2], LEAD_YOU[3])
        elseif they > you then
            row.lead:SetText("they lead")
            row.lead:SetTextColor(BLOOD[1], BLOOD[2], BLOOD[3])
        else
            row.lead:SetText("even")
            row.lead:SetTextColor(FADED[1], FADED[2], FADED[3])
        end
    else
        row.score:SetText("")
        row.lead:SetText("")
    end
    local x0 = it.rank and NAME_X_RANKED or NAME_X
    row.face.tex:ClearAllPoints()
    row.face.tex:SetPoint("CENTER", row, "LEFT", x0 - 19, 0)
    row.name:SetPoint("TOPLEFT", x0, -4)
    row.sub:SetPoint("TOPLEFT", x0, -22)
    local rc = it.rightColour or (it.faded and FADED or INK)
    row.right:SetTextColor(rc[1], rc[2], rc[3])
    row.right:SetText(it.right or "")
    -- The name runs to whichever column is there. Before a right-hand number it stops at that number's
    -- own width, not a fixed 70 kept for "12g 34s": a "+2" in the news cut "Seedkek One" to "Seedke..."
    -- with half the row empty (2026-11-05), and a long sum ran past the fixed stop into the name. Before
    -- a score, short of its "they lead", the widest thing under it.
    local stop = (it.score and SCORE_X - 32) or (it.c1 and COL1 - 20) or (it.wide and COL_WIDE - 8)
        or (it.right and COL_RIGHT - 4 - row.right:GetStringWidth() - 12) or (PAGE_W - 24)
    local room = stop - x0
    -- A line too long for its room steps down a size, then says its short form (first names only, where
    -- the item has one), and only then is cut - whole in the row's tooltip. "Hellig Bro added to the pot
    -- on Ikka Levici" lost its last name in the news (the owner, 2026-11-07).
    local colour = it.mine and BLOOD or (it.faded and FADED or INK)
    Ink(row.name, colour, TEXT_FONT, 13)
    row.name:SetText(it.name or "")
    if TextWidth(row.name) > room then
        Ink(row.name, colour, TEXT_FONT, 12)
        if TextWidth(row.name) > room and it.short then row.name:SetText(it.short) end
    end
    Ink(row.sub, FADED, TEXT_FONT, 11)
    row.sub:SetText(it.sub or "")
    row.cut = row.name:GetText() ~= (it.name or "") or TextWidth(row.name) > room or TextWidth(row.sub) > room
    row.name:SetWidth(room)
    row.sub:SetWidth(room)
    -- the description after the name's own width, only when all of it fits before the stop: a cut
    -- "35 Orc Ro..." says less than none, and the name keeps its room
    local nameW = math.ceil(TextWidth(row.name))
    row.desc:SetText(it.desc or "")
    local descW = math.ceil(TextWidth(row.desc))
    local fits = it.desc ~= nil and nameW + 6 + descW <= room
    row.desc:SetShown(fits)
    if fits then
        row.desc:ClearAllPoints()
        row.desc:SetPoint("BOTTOMLEFT", row, "TOPLEFT", x0 + nameW + 6, -18)
    end
    row.seal:SetShown(it.seal == true)
    if it.seal then row.seal:SetTexture(MEDIA .. "rank_" .. it.rank) end
    Ink(row.rank, it.seal and { 0.23, 0.14, 0.02 } or FADED, TITLE_FONT, it.seal and 12 or 13)
    row.rank:SetText(it.rank and tostring(it.rank) or "")
    row.face:SetShown(true)
    row.face:Set(it.face or {})
    row.c1:SetText(it.c1 or "")
    row.c2:SetText(it.c2 or "")
    row.wide:SetText(it.wide or "")
    row.mark:SetShown(chosen and not Folded())
    row.open:SetShown(Folded())
end

local function BuildList(page)
    page.title = page:CreateFontString(nil, "ARTWORK")
    Ink(page.title, BLOOD, TITLE_FONT, 22)
    page.title:SetPoint("TOPLEFT", 10, -10)
    page.sub = page:CreateFontString(nil, "ARTWORK")
    Ink(page.sub, FADED, TEXT_FONT, 11)
    page.sub:SetPoint("TOPLEFT", 12, -44)
    page.sub:SetJustifyH("LEFT")
    page.sub:SetWordWrap(false)
    -- An ink link: faded, or in blood and underlined when it is the one chosen. Refresh fills and places them.
    -- A choice of what the page shows (the leaderboard's This week and All time): the game's radio button
    -- with its words beside it, the words part of what you click. As underlined ink they were not seen to
    -- be choices at all ("det var vanskelig å se at det var tabs der", the owner, 2026-11-06).
    local function Link(click)
        local b = CreateFrame("Button", nil, page)
        b:SetHeight(18)
        b.radio = CreateFrame("CheckButton", nil, b, "UIRadioButtonTemplate")
        b.radio:SetSize(16, 16)
        b.radio:SetPoint("LEFT")
        b.radio:EnableMouse(false)                    -- the whole choice is the button
        b.text = b:CreateFontString(nil, "ARTWORK")
        Ink(b.text, FADED, TEXT_FONT, 11)
        b.text:SetPoint("LEFT", b.radio, "RIGHT", 3, 0)
        function b:Set(text, on)
            self.text:SetText(text)
            self.on = on and true or false
            self.radio:SetChecked(self.on)
            Ink(self.text, self.on and INK or FADED, TEXT_FONT, 11)
            self:SetWidth(19 + math.ceil(TextWidth(self.text)) + 2)
        end
        b:SetScript("OnClick", function(self)
            click(self)
            offset = 0
            Refresh()
        end)
        b:SetScript("OnEnter", function(self) if not self.on then self.text:SetTextColor(INK[1], INK[2], INK[3]) end end)
        b:SetScript("OnLeave", function(self) if not self.on then self.text:SetTextColor(FADED[1], FADED[2], FADED[3]) end end)
        return b
    end
    -- the page's own links (the leaderboard's this week and all time), laid out from its links()
    page.links = {}
    for i = 1, 4 do page.links[i] = Link(function(self) self.click() end) end
    -- Only mine: the game's own checkbox, on the line under the title at the page's right, its words in
    -- ink after it. (Drawn in ink at the foot of the page it read as part of the page; the frame has real
    -- controls now, so this is one too - previewed 2026-11-06.)
    local mine = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    mine:SetSize(22, 22)
    mine.label = page:CreateFontString(nil, "ARTWORK")
    Ink(mine.label, FADED, TEXT_FONT, 11)
    mine.label:SetPoint("LEFT", mine, "RIGHT", 1, 0)
    function mine:Set(text, on)
        self.label:SetText(text)
        self.on = on and true or false
        self:SetChecked(self.on)
        Ink(self.label, self.on and INK or FADED, TEXT_FONT, 11)
        self.width = 23 + math.ceil(TextWidth(self.label))
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", page, "TOPRIGHT", -(self.width + 6), -38)
    end
    mine:SetScript("OnClick", function()
        GK.db.mineOnly = not (GK.db.mineOnly == true)
        offset = 0
        Refresh()
    end)
    mine:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Only mine", 1, 1, 1)
        GameTooltip:AddLine("Only the rows that are yours: what you posted, backed, wrote or voted on.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    mine:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mine:HookScript("OnShow", function(self) self.label:Show() end)
    mine:HookScript("OnHide", function(self) self.label:Hide() end)
    page.mine = mine
    -- The page's own action, where the eye starts: the game's red button on the title's line, at its
    -- right, naming what it does on this page ("Put someone on Shame"). Before, it was ink and a seal on the
    -- page, and "knapper osv ikke har noe tydelig 'jeg er en knapp'" (the owner, 2026-11-06); before that,
    -- three buttons at the foot of the page that said too little, where Post a kill order did nothing
    -- without a target. It opens the who-picker, so it works with no target.
    local add = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    add:SetHeight(22)
    add:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -14)
    function add:Set(def)
        self.def = def
        self:SetText(def.text)
        self:SetWidth(math.max(110, math.ceil(self:GetTextWidth() or 100) + 28))
    end
    add:SetScript("OnClick", function(self) GK.OpenPicker(self.def.kind) end)
    add:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self.def.text, 1, 1, 1)
        GameTooltip:AddLine("Pick who: your target, someone you met lately, or type a name.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    add:SetScript("OnLeave", function() GameTooltip:Hide() end)
    page.add = add
    page.reset = page:CreateFontString(nil, "ARTWORK")    -- the links' tail, anchored after the last one shown
    Ink(page.reset, FADED, TEXT_FONT, 11)
    -- The column headings. One with a sort is a button: a click sorts by it, a second click goes back
    -- to the page's own order; the one in use is in blood and underlined, like a chosen link.
    page.heads = {}
    for i = 1, 5 do
        local b = CreateFrame("Button", nil, page)
        b:SetHeight(14)
        b.text = b:CreateFontString(nil, "ARTWORK")
        Ink(b.text, FADED, TEXT_FONT, 10)
        b.text:SetPoint("LEFT")
        b.line = b:CreateTexture(nil, "ARTWORK")
        Paint(b.line, "blood", 0.7)
        b.line:SetHeight(1)
        b.line:SetPoint("BOTTOMLEFT", 0, -1)
        b.line:SetPoint("BOTTOMRIGHT", 0, -1)
        b:SetScript("OnClick", function(self)
            GK.SortBy(GK.LedgerPages[tab], self.key)
            offset = 0
            Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if self.on then
                GameTooltip:AddLine("Click again for the page's own order", 1, 1, 1)
            else
                GameTooltip:AddLine("Sort by " .. (self.tip or self.text:GetText():lower()), 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        page.heads[i] = b
    end
    local underline = page:CreateTexture(nil, "BORDER")
    Paint(underline, "rule")
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT", 8, -(LIST_TOP - 4))
    underline:SetPoint("TOPRIGHT", -8, -(LIST_TOP - 4))
    page.underline = underline                         -- a page with no heading row has no line under it
    page.rows = {}
    for i = 1, ROWS do page.rows[i] = BuildRow(page, i) end
    page.empty = page:CreateFontString(nil, "ARTWORK")
    Ink(page.empty, FADED, TEXT_FONT, 12)
    page.empty:SetPoint("TOPLEFT", 12, -(LIST_TOP + 12))
    page.empty:SetPoint("RIGHT", -24, 0)
    page.empty:SetJustifyH("LEFT")
    page.empty:SetSpacing(3)
    -- turning through a long list: the spellbook's page arrows at the foot, and the mouse wheel
    -- in the gap between the last row (58 up) and the buttons at the foot (32 up), its arrows 36 to 56 up:
    -- on the foot's line, Read all covered "1-9" and left "of 21" (the store pictures, 2026-11-10)
    page.count = page:CreateFontString(nil, "ARTWORK")
    Ink(page.count, FADED, TEXT_FONT, 10)
    page.count:SetPoint("BOTTOMRIGHT", -46, 39)
    local function Arrow(kind, dir)
        local b = CreateFrame("Button", nil, page)
        b:SetSize(20, 20)
        b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Down")
        b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Disabled")
        b:SetScript("OnClick", function()
            offset = GK.TurnPage(page.starts, offset, dir)
            Refresh()
        end)
        return b
    end
    page.prev = Arrow("Prev", -1)
    page.prev:SetPoint("LEFT", page.count, "RIGHT", 2, 0)
    page.next = Arrow("Next", 1)
    page.next:SetPoint("LEFT", page.prev, "RIGHT", -2, 0)
    page:EnableMouseWheel(true)
    -- the wheel turns a page too: a few rows at a time left pages that began anywhere
    page:SetScript("OnMouseWheel", function(_, delta)
        offset = GK.TurnPage(page.starts, offset, delta > 0 and -1 or 1)
        Refresh()
    end)
    -- Letters and Settings: the game's red buttons at the foot of the list, as previewed (2026-11-06).
    -- On the book they went from buttons here to bookmarks on its edge, with words, then icons, then words
    -- turned down the leather - none of it looked right ("tabs på siden funker ikke").
    local function Foot(onClick, title, line)
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        b:SetHeight(22)
        function b:Set(text)
            self:SetText(text)
            self:SetWidth(math.max(80, math.ceil(self:GetTextWidth() or 60) + 28))
        end
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(title(), 1, 1, 1)
            GameTooltip:AddLine(line, nil, nil, nil, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    page.letters = Foot(function() GK.OpenLetters() end, function()
        local n = GK.Unread()
        return n > 0 and ("Letters - %d unread"):format(n) or "Letters"
    end, "New kill orders, your new titles and what you are owed. A letter goes once it is read and closed - "
        .. "the ledger keeps what it said.")
    page.letters:SetPoint("BOTTOMLEFT", 8, 10)
    page.letters:Set("Letters")
    page.settings = Foot(function() if GK.OpenOptions() then win:Hide() end end,
        function() return SETTINGS or "Settings" end, "Grudgekeeper's settings: letters, warnings, sharing.")
    page.settings:SetPoint("LEFT", page.letters, "RIGHT", 6, 0)
    page.settings:Set(SETTINGS or "Settings")
    -- a pile of letters, read in one click (GK.ReadAllLetters): there while two or more wait (Refresh)
    page.readAll = Foot(function() GK.ReadAllLetters() end, function() return "Read all letters" end,
        "Every letter waiting, read at once - and so gone. The ledger keeps what they said.")
    page.readAll:SetPoint("LEFT", page.settings, "RIGHT", 6, 0)
    page.readAll:Set("Read all")
    page.readAll:Hide()
end

-- Where the card's parts sit, in units from the page's top left. The ledger's right page has these; the
-- Inspect tab (Inspect.lua) has a smaller page and lays the same card out tighter, at the same type
-- sizes rather than scaled down (scaled to fit, 12pt ink came out under 10). h: the page's height, for
-- the buttons that follow the lines (else they sit at the foot). rich: the page has room for a card's
-- rich form (Profile.lua's d.rich, FillRich below): its tiles start tilesY down, and a fact's value
-- factX in. A card without one - a note card - is drawn as lines here too.
local DETAIL = { w = PAGE_W, h = PAGE_H, face = 84, faceX = 66, faceY = 76, bigY = 128, bigSize = 26,
    titleX = 124, titleY = 48, titleSize = 24, seal = 46, sealX = 26, sealY = 36, ruleY = 194, linesY = 206,
    padX = 24, valueX = 120, signY = 24, buttonY = 18, rich = true, tilesY = 130, factX = 128 }

-- ---------------------------------------------------------------------------
-- The rich card: tiles, the way to the next title, and sections of facts, pairs or news, as previewed
-- with the owner (2026-11-06). Its texts and textures come from pools on the page and go back at every
-- fill, so a card with more rows than the last makes what it needs once and keeps it.
-- ---------------------------------------------------------------------------
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local SEAL_INK = { 0.23, 0.14, 0.02 }         -- a number on a wax seal, as on the leaderboard's rows

local function Take(pool)
    pool.n = pool.n + 1
    local x = pool[pool.n]
    if not x then
        x = pool.make()
        pool[pool.n] = x
    end
    x:ClearAllPoints()
    x:Show()
    return x
end

local function Reset(pool)
    for i = 1, #pool do pool[i]:Hide() end
    pool.n = 0
end

--- A text's height, never less than its type size: offline (and for an empty string) it can say 0.
local function Height(fs, least) return math.max(least, fs:GetStringHeight() or 0) end

local function Text(page, colour, size, width, lines)
    local fs = Take(page.richParts.texts)
    Ink(fs, colour, TEXT_FONT, size)
    fs:SetWidth(width or 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(lines ~= 1)
    if fs.SetMaxLines then fs:SetMaxLines(lines or 0) end
    fs:SetSpacing(0)
    return fs
end

local function Flat(page, role, a, sub)
    local t = Take(page.richParts.paint)
    Paint(t, role, a)
    t:SetDrawLayer("BORDER", sub or 0)
    return t
end

--- Draw d.rich on a page built with a rich layout. Returns how far down it went, for the buttons.
local function FillRich(page, d, L)
    local rich = d.rich
    local w, pad = L.w, L.padX
    local inner = w - 2 * pad
    local y = L.tilesY
    -- the tiles: a number, what it counts, and a line that says something about it
    local n = #rich.tiles
    if n > 0 then
        local tw = inner / n
        local tallest, divs = 0, {}
        for i, tile in ipairs(rich.tiles) do
            local v = Text(page, INK, 20)
            v:SetText(tile[1])
            v:SetPoint("TOP", page, "TOPLEFT", pad + (i - 0.5) * tw, -y)
            local k = Text(page, FADED, 9)
            k:SetText(tile[2]:upper())
            k:SetPoint("TOP", v, "BOTTOM", 0, -2)
            -- a zone's name may take two lines; a line under it (when the last was) has its own, so a
            -- long guild name is cut rather than pushing the time off the tile
            local s = Text(page, FADED, 10, tw - 6, tile[4] and 1 or 2)
            s:SetJustifyH("CENTER")
            s:SetText(tile[3] or "")
            s:SetPoint("TOP", k, "BOTTOM", 0, -2)
            local h = Height(v, 20) + Height(k, 10) + Height(s, 11) + 4
            if tile[4] then
                local s2 = Text(page, FADED, 10, tw - 6, 1)
                s2:SetJustifyH("CENTER")
                s2:SetText(tile[4])
                s2:SetPoint("TOP", s, "BOTTOM", 0, -1)
                h = h + Height(s2, 11) + 1
            end
            tallest = math.max(tallest, h)
            if i > 1 then
                local div = Flat(page, "rule")
                div:SetPoint("TOPLEFT", page, "TOPLEFT", pad + (i - 1) * tw, -(y + 2))
                divs[#divs + 1] = div
            end
        end
        for _, div in ipairs(divs) do div:SetSize(1, tallest - 2) end
        y = y + tallest + 12
    end
    -- the way to the next title
    local bar = rich.bar
    if bar then
        local track = Flat(page, "rule", 0.3)
        track:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -y)
        track:SetSize(inner, 7)
        if bar.frac > 0 then
            local fill = Flat(page, "blood", 0.85, 1)
            fill:SetPoint("TOPLEFT", track, "TOPLEFT")
            fill:SetSize(math.max(1, math.min(1, bar.frac) * inner), 7)
        end
        local left = Text(page, FADED, 10)
        left:SetText(bar.left)
        left:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -(y + 10))
        local right = Text(page, FADED, 10)
        right:SetText(bar.right)
        right:SetPoint("TOPRIGHT", page, "TOPLEFT", w - pad, -(y + 10))
        y = y + 35
    end
    -- the sections, as many as fit above the buttons and the signature: the last ones give way first
    local limit = L.h - L.signY - 22 - (#d.buttons > 0 and 34 or 0)
    for _, sec in ipairs(rich.sections) do
        if y + 32 > limit then break end
        local top, drawn = y, 0
        -- the section's name in red capitals, its rows' labels in plain grey words: in the same small grey
        -- capitals, every label read as one more heading (the owner, 2026-11-06)
        local head = Text(page, BLOOD, 10)
        head:SetText(sec.head:upper())
        head:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -y)
        local after = pad + math.ceil(TextWidth(head)) + 6
        local line = Flat(page, "rule")
        line:SetPoint("TOPLEFT", page, "TOPLEFT", after, -(y + 5))
        line:SetSize(math.max(1, w - pad - after), 1)
        y = y + 17
        if sec.kind == "events" then
            for i, e in ipairs(sec.rows) do
                if y + 28 > limit then break end
                if i % 2 == 0 then
                    local stripe = Flat(page, "stripe")
                    stripe:SetPoint("TOPLEFT", page, "TOPLEFT", pad - 4, -(y - 1))
                    stripe:SetSize(inner + 8, 30)
                end
                local icon = Take(page.richParts.icons)
                icon:SetSize(22, 22)
                icon:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -(y + 3))
                local coords = e.c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[e.c]
                if coords then
                    icon:SetTexture(CLASS_ICONS)
                    icon:SetTexCoord(unpack(coords))
                else
                    icon:SetTexture(MEDIA .. "portrait")
                    icon:SetTexCoord(0, 1, 0, 1)
                end
                local room = inner - 30
                if e.right then
                    local r = Text(page, INK, 12)
                    r:SetText(e.right)
                    r:SetPoint("TOPRIGHT", page, "TOPLEFT", w - pad, -(y + 8))
                    room = room - math.ceil(TextWidth(r)) - 10
                end
                local t = Text(page, INK, 12, room, 1)
                t:SetText(e.text)
                -- a line a size smaller before it is cut, as a row's name (FillRow)
                if TextWidth(t) > room then Ink(t, INK, TEXT_FONT, 11) end
                t:SetPoint("TOPLEFT", page, "TOPLEFT", pad + 30, -(y + 2))
                local s = Text(page, FADED, 10, room, 1)
                s:SetText(e.under or "")
                s:SetPoint("TOPLEFT", page, "TOPLEFT", pad + 30, -(y + 17))
                y = y + 30
                drawn = drawn + 1
            end
        else
            -- facts: a label in plain words, its value beside it, and after the value - on its line when it
            -- fits, else under it - a grey word on it ("best ever 11"); a row with no label is a paragraph
            local room = w - L.factX - pad
            for _, row in ipairs(sec.rows) do
                if y + 14 > limit then break end
                local k, v, more
                if row[1] then
                    k = Text(page, FADED, 11)
                    k:SetText(row[1])
                    k:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -(y + 1))
                    v = Text(page, INK, 12, room)
                    v:SetPoint("TOPLEFT", page, "TOPLEFT", L.factX, -y)
                else
                    v = Text(page, INK, 12, inner)
                    v:SetPoint("TOPLEFT", page, "TOPLEFT", pad, -y)
                end
                v:SetSpacing(2)
                v:SetText(row[2] or "")
                local h = Height(v, 13)
                if row[1] and row[3] then
                    more = Text(page, FADED, 11, nil, 1)
                    more:SetText(row[3])
                    local used = math.ceil(TextWidth(v))
                    if h <= 16 and used + 8 + TextWidth(more) <= room then
                        more:SetPoint("TOPLEFT", page, "TOPLEFT", L.factX + used + 8, -(y + 1))
                    else
                        more:SetWidth(room)
                        more:SetPoint("TOPLEFT", page, "TOPLEFT", L.factX, -(y + h + 2))
                        h = h + 2 + Height(more, 11)
                    end
                end
                -- the whole row or none of it: its first line fitting said nothing of the second, and "died
                -- to them 5 / times" ran into the poster's buttons (the store pictures, 2026-11-10)
                if y + h > limit then
                    if k then k:Hide() end
                    v:Hide()
                    if more then more:Hide() end
                    break
                end
                y = y + math.max(18, h + 5)
                drawn = drawn + 1
            end
        end
        -- a heading whose first row did not fit goes too, and nothing after it fits either
        if drawn == 0 and #sec.rows > 0 then
            head:Hide()
            line:Hide()
            y = top
            break
        end
        y = y + 6
    end
    return y
end

local function BuildDetail(page, L)
    L = L or DETAIL
    page.layout = L
    page.back = CreateFrame("Button", nil, page)
    page.back:SetSize(220, 16)
    page.back:SetPoint("TOPLEFT", 24, -16)
    page.back.text = page.back:CreateFontString(nil, "ARTWORK")
    Ink(page.back.text, BLOOD, TEXT_FONT, 12)
    page.back.text:SetPoint("LEFT")
    page.back:SetScript("OnClick", function()
        turned = false
        Refresh()
    end)
    page.face = MakePortrait(page, L.face)
    page.face.tex:SetPoint("CENTER", page, "TOPLEFT", L.faceX, -L.faceY)
    page.big = page:CreateFontString(nil, "ARTWORK")
    Ink(page.big, BLOOD, TITLE_FONT, L.bigSize)
    page.big:SetPoint("TOP", page, "TOPLEFT", L.faceX, -L.bigY)
    page.caption = page:CreateFontString(nil, "ARTWORK")
    Ink(page.caption, INK, TEXT_FONT, 11)
    page.caption:SetPoint("TOP", page.big, "BOTTOM", 0, -1)
    page.seal = page:CreateTexture(nil, "ARTWORK")
    page.seal:SetSize(L.seal, L.seal)
    page.seal:SetPoint("TOPRIGHT", -L.sealX, -L.sealY)
    page.blood = page:CreateTexture(nil, "BORDER")
    page.blood:SetTexture(MEDIA .. "blood")
    page.blood:SetSize(170, 170)
    page.blood:SetPoint("CENTER", page, "RIGHT", -80, -10)
    page.blood:SetRotation(-0.5)
    page.blood:SetAlpha(0.4)
    page.title = page:CreateFontString(nil, "ARTWORK")
    Ink(page.title, BLOOD, TITLE_FONT, L.titleSize)
    page.title:SetPoint("TOPLEFT", L.titleX, -L.titleY)
    page.title:SetJustifyH("LEFT")
    page.title:SetWordWrap(false)                  -- one line: FillDetail steps the size down to fit
    page.name = page:CreateFontString(nil, "ARTWORK")
    Ink(page.name, INK, TITLE_FONT, 15)
    page.name:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -4)
    page.info = page:CreateFontString(nil, "ARTWORK")
    Ink(page.info, FADED, TEXT_FONT, 11)
    page.info:SetPoint("TOPLEFT", page.name, "BOTTOMLEFT", 0, -3)
    -- A page with room for the rich card: the small red line over the name, the number on a rank's wax
    -- seal, and the pools FillRich draws the rest from.
    if L.rich then
        page.kicker = page:CreateFontString(nil, "ARTWORK")
        Ink(page.kicker, BLOOD, TEXT_FONT, 10)
        page.kicker:SetPoint("BOTTOMLEFT", page.title, "TOPLEFT", 1, 2)
        page.sealNum = page:CreateFontString(nil, "OVERLAY")
        Ink(page.sealNum, SEAL_INK, TITLE_FONT, 16)
        page.sealNum:SetPoint("CENTER", page.seal, "CENTER", 0, 1)
        page.richParts = {
            texts = { n = 0, make = function() return page:CreateFontString(nil, "ARTWORK") end },
            paint = { n = 0, make = function() return page:CreateTexture(nil, "BORDER") end },
            icons = { n = 0, make = function() return page:CreateTexture(nil, "ARTWORK") end },
        }
    end
    -- below the portrait's number and its caption (on the ledger they end about 172 down)
    page.rule = page:CreateTexture(nil, "BORDER")
    Paint(page.rule, "rule")
    page.rule:SetHeight(1)
    page.rule:SetPoint("TOPLEFT", L.padX, -L.ruleY)
    page.rule:SetPoint("TOPRIGHT", -L.padX, -L.ruleY)
    page.labels, page.values = {}, {}
    for i = 1, 9 do
        local l = page:CreateFontString(nil, "ARTWORK")
        Ink(l, FADED, TEXT_FONT, 10)
        l:SetJustifyH("LEFT")
        local v = page:CreateFontString(nil, "ARTWORK")
        Ink(v, INK, TEXT_FONT, 12)
        v:SetJustifyH("LEFT")
        v:SetSpacing(2)
        page.labels[i], page.values[i] = l, v
    end
    page.sign = page:CreateFontString(nil, "ARTWORK")
    Ink(page.sign, INK, TITLE_FONT, 14)
    page.sign:SetPoint("BOTTOMRIGHT", -(L.padX + 2), L.signY)
    page.sign:SetText("- the Grudgekeeper")
    page.buttons = {}
    for i = 1, 2 do
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        b:SetSize(140, 22)
        if i == 1 then b:SetPoint("BOTTOMLEFT", L.padX, L.buttonY) else b:SetPoint("LEFT", page.buttons[1], "RIGHT", 6, 0) end
        page.buttons[i] = b
    end
end

--- With no card, the page is blank but for the signature: no rule under nothing, and "choose a row" only
--- when the list has rows to choose (in the game it sat beside "0 open orders").
local function FillDetail(page, d, anyRows)
    local L = page.layout
    local rich = L.rich and d and d.rich or nil
    if page.richParts then
        for _, pool in pairs(page.richParts) do Reset(pool) end
        page.kicker:SetText("")
        page.sealNum:SetText("")
    end
    page.rule:SetShown(d ~= nil and not rich)
    if not d then
        page.face:SetShown(false)
        page.title:SetText("")
        page.name:SetText("")
        page.info:SetText(anyRows and "Choose a row on the left." or "")
        page.big:SetText("")
        page.caption:SetText("")
        page.seal:Hide()
        page.blood:Hide()
        for i = 1, #page.labels do page.labels[i]:SetText("") page.values[i]:SetText("") end
        for _, b in ipairs(page.buttons) do b:Hide() end
        return
    end
    page.face:SetShown(true)
    page.face:Set(d)
    -- the rich card's head: its kicker over the name, the name, and under it the title or the nemesis
    local title, sub, seal
    if rich then title, sub, seal = rich.head, rich.sub or "", rich.seal
    else title, sub, seal = d.title or "", d.name or "", d.seal end
    -- The title on one line, beside the seal (or to the edge without one): a long name steps down in size
    -- until it fits rather than breaking in two ("Kriger-" over "Skaalvik" in the Inspect tab, 2026-11-05).
    local room = L.w - L.titleX - (seal and (L.sealX + L.seal + 4) or L.padX)
    page.title:SetWidth(room)
    page.title:SetText(title)
    local size = L.titleSize
    Ink(page.title, BLOOD, TITLE_FONT, size)
    while size > 14 and TextWidth(page.title) > room do
        size = size - 1
        Ink(page.title, BLOOD, TITLE_FONT, size)
    end
    page.name:SetText(sub)
    -- what they are right under the name when nothing stands between (a poster's enemy who is no nemesis)
    page.info:ClearAllPoints()
    page.info:SetPoint("TOPLEFT", sub ~= "" and page.name or page.title, "BOTTOMLEFT", 0, -3)
    page.info:SetText((rich and rich.info) or d.info or "")
    page.big:SetText(rich and "" or (d.big or ""))
    page.caption:SetText(rich and "" or (d.caption or ""))
    page.seal:SetShown(seal ~= nil)
    if seal then page.seal:SetTexture(MEDIA .. seal) end
    page.blood:SetShown(d.blood == true)
    local y
    if rich then
        page.kicker:SetText((rich.kicker or ""):upper())
        page.sealNum:SetText(rich.sealNum or "")
        for i = 1, #page.labels do page.labels[i]:SetText("") page.values[i]:SetText("") end
        y = FillRich(page, d, L)
    else
        y = L.linesY
    end
    -- a card without a rich form, as lines: a short "Label: value" as two columns, anything else as a
    -- paragraph
    local lines = rich and {} or d.lines
    for i = 1, rich and 0 or #page.labels do
        local l, v = page.labels[i], page.values[i]
        local line = lines[i]
        l:ClearAllPoints()
        v:ClearAllPoints()
        if line then
            local label, value = Split(line)
            if label then
                l:SetPoint("TOPLEFT", L.padX, -(y + 2))
                l:SetText(label:upper())
                v:SetPoint("TOPLEFT", L.valueX, -y)
                v:SetWidth(L.w - L.valueX - L.padX)
            else
                l:SetText("")
                v:SetPoint("TOPLEFT", L.padX, -y)
                v:SetWidth(L.w - 2 * L.padX)
            end
            v:SetText(value)
            y = y + math.max(18, (v:GetStringHeight() or 14) + 6)
        else
            l:SetText("")
            v:SetText("")
        end
    end
    -- the buttons right under the lines, where the eye already is (at the foot of the page they sat
    -- under a hand's width of nothing) - but never down into the signature
    if L.h then
        local first = page.buttons[1]
        first:ClearAllPoints()
        first:SetPoint("TOPLEFT", L.padX, -math.min(y + 10, L.h - L.signY - 48))
    end
    for i, b in ipairs(page.buttons) do
        local spec = d.buttons[i]
        b:SetShown(spec ~= nil)
        if spec then
            b:SetText(spec[1])
            b:SetScript("OnClick", function()
                spec[2]()
                if page.refill then page.refill() else Refresh() end
            end)
        end
    end
end

--- The ledger's card on a page of someone else's (the Inspect tab): built with its own layout (see
--- DETAIL), filled from GK.RecordCard or GK.PosterCard; refill is called after one of its buttons.
function GK.BuildCardPage(page, layout, refill)
    BuildDetail(page, layout)
    page.back:Hide()
    page.refill = refill
end

function GK.FillCardPage(page, d) FillDetail(page, d, false) end

--- The parchment's tone (see Tone), for a page of ours drawn elsewhere.
GK.Tone = function(tex, r, g, b) Tone(tex, r, g, b) end

-- ---------------------------------------------------------------------------
-- The whole window
-- ---------------------------------------------------------------------------
--- The game's tabs under the frame, as the character window has them. Open, all of them: the enemy's
--- pages, then a step apart the friendly ones (side = "right"). Folded the window is one page wide, too
--- narrow for all of them: only the active page's group, then a step apart a last tab that switches to
--- the other group. Each tab at its words' width; if a row is still wider than the window, the chosen
--- tab keeps its width and the others share what is left (the game's own PanelTemplates_ResizeTabsToFit
--- does the same, but wants the tabs in one numbered row).
local TabSide                    -- made with the tabs' art, below: under the frame, or down its right side

--- The icon on a tab folded: ours as drawn, the game's cut round like ours - the square's border trimmed and
--- the round mask on (as Blizzard rounds an icon, AlertFrameSystems.lua) - so they sit together as medallions.
local function SetTabIcon(t, path)
    t.icon:SetTexture(path)
    local game = path:sub(1, #ICONS) == ICONS
    local a, b = game and 0.08 or 0, game and 0.92 or 1
    t.icon:SetTexCoord(a, b, a, b)
    if game and not t.iconMasked then
        t.icon:AddMaskTexture(t.iconMask)
    elseif not game and t.iconMasked then
        t.icon:RemoveMaskTexture(t.iconMask)
    end
    t.iconMasked = game
end

local function PlaceTabs(folded)
    local current = GK.LedgerPages[tab]
    local friends = current ~= nil and current.side == "right"
    local row = {}
    for _, t in ipairs(win.tabs) do
        local show = not folded or (t.side == "right") == friends
        t:SetShown(show)
        if show then row[#row + 1] = t end
    end
    win.swap:SetShown(folded)
    if folded then
        win.swap:SetText(friends and "Enemies" or "Friends")
        row[#row + 1] = win.swap
    end
    -- down the side only in the heavy art, which is drawn as a side tab; the game's thin art is not. Every
    -- tab, the hidden ones too, so none waits the other way round for the next fold
    local side = folded and win.swap.heavy ~= nil
    for _, t in ipairs(win.tabs) do TabSide(t, side) end
    TabSide(win.swap, side)
    for i, t in ipairs(row) do
        t.gap = (i > 1 and (t == win.swap or t.side ~= row[i - 1].side)) and GROUP_GAP or TAB_GAP
    end
    if side then
        -- down the right side, an icon each (TabSide); the switch shows the group it switches to
        SetTabIcon(win.swap, SWAP_ICON[friends and "Enemies" or "Friends"])
        for i, t in ipairs(row) do
            t:SetSize(TAB_BUTTON_H, SIDE_LEN)
            t:ClearAllPoints()
            if i == 1 then t:SetPoint("TOPLEFT", win, "TOPRIGHT", -TAB_TUCK, -SIDE_TOP)
            else t:SetPoint("TOPLEFT", row[i - 1], "BOTTOMLEFT", 0, -t.gap) end
        end
        return
    end
    local width, chosen = 0, nil
    for i, t in ipairs(row) do
        PanelTemplates_TabResize(t, TAB_PAD)
        width = width + t:GetWidth() + (i > 1 and t.gap or 0)
        if t.selected then chosen = t end
    end
    local room = (folded and FOLDED.W or OPEN.W) - 24
    if width > room and #row > 1 then
        local gaps = 0
        for i, t in ipairs(row) do if i > 1 then gaps = gaps + t.gap end end
        local share = math.floor((room - gaps - (chosen and chosen:GetWidth() or 0)) / (#row - (chosen and 1 or 0)))
        for _, t in ipairs(row) do
            if t ~= chosen then PanelTemplates_TabResize(t, TAB_PAD, share) end
        end
    end
    -- Open, the friendly pages sit at the frame's right edge, apart from the enemy's ("skyv shame og kudos
    -- lenger ut til høyre", the owner, 2026-11-07); folded under the frame (no heavy art), the row runs on
    -- from the left.
    local firstRight
    if not folded then
        for i, t in ipairs(row) do
            if t.side == "right" then firstRight = i break end
        end
    end
    for i, t in ipairs(row) do
        t:ClearAllPoints()
        if i == 1 then t:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 12, TAB_TUCK)
        elseif not firstRight or i < firstRight then t:SetPoint("TOPLEFT", row[i - 1], "TOPRIGHT", t.gap, 0) end
    end
    if firstRight then
        for i = #row, firstRight, -1 do
            local t = row[i]
            if i == #row then t:SetPoint("TOPRIGHT", win, "BOTTOMRIGHT", -12, TAB_TUCK)
            else t:SetPoint("TOPRIGHT", row[i + 1], "TOPLEFT", -row[i + 1].gap, 0) end
        end
    end
end

local function Layout()
    local folded = Folded()
    local b = folded and FOLDED or OPEN
    win:SetSize(b.W, b.H)
    -- the skin's background: the parchment, or in classic the frame's own panel, as Guildhall has it
    if GK.Classic() then
        win.sheet:SetAtlas("heavybronze-frame-background")
        win.sheet:SetDesaturation(0)
        win.sheet:SetVertexColor(1, 1, 1)
    else
        win.sheet:SetTexture(MEDIA .. (folded and "sheet_single" or "sheet_wide"))
        win.sheet:SetTexCoord(0, 1, 0, 1)            -- an atlas before it leaves its corner of the art behind
        Tone(win.sheet)
    end
    win.divider:SetShown(not folded)                 -- folded there is one page: nothing to divide
    -- folded, the tabs down the right side stay on the screen with the frame (PlaceTabs)
    win:SetClampRectInsets(0, folded and -(TAB_H_ON - TAB_TUCK) or 0, 0, 0)
    win.list:ClearAllPoints()
    win.list:SetPoint("TOPLEFT", b.x, -b.y)
    win.detail:ClearAllPoints()
    win.detail:SetPoint("TOPLEFT", folded and b.x or b.x2, -b.y)
    PlaceTabs(folded)
    win.fold:Set(folded)
end

-- a switch of skin (Core.lua's GK.SetLook) redraws the texts and lines; the background and panels are ours
GK.OnLook(function()
    if not win then return end
    Layout()
    Refresh()
end)

--- Keep the left edge where it is when the window changes width: anchor it by its top left first.
local function Fold(on)
    GK.db.ledgerFolded = on or nil
    turned = false
    local l, t = win:GetLeft(), win:GetTop()
    if l and t then
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t)
    end
    Layout()
    Refresh()
end

--- One of the heavy art's atlases over a tab (HEAVY, at the top), cut in six: two rows - what stretches with
--- the tab's height, then the cut corners - by three columns - a corner, what stretches with its width, a
--- corner. Under the frame turned a quarter clockwise: the art's x runs down the tab, its y from the tab's
--- right to its left. Down the frame's side as it lies (HeavyCoords): its x across the tab, its y down it.
local function HeavyPieces(t, info, layer, sub, cut, fade)
    local l, r, top, bottom = info.leftTexCoord, info.rightTexCoord, info.topTexCoord, info.bottomTexCoord
    local function U(x) return l + (r - l) * x / HEAVY_SIZE end
    local function V(y) return top + (bottom - top) * y / HEAVY_SIZE end
    local S, C = HEAVY_SIZE, HEAVY_CORNER
    local rows, cols = { { cut, S - C }, { S - C, S } }, { { S - C, S }, { C, S - C }, { 0, C } }
    -- with a fade, a short row of its own on top, as long on screen as in the art (TabLook)
    if fade then rows = { { cut, cut + fade }, { cut + fade, S - C }, { S - C, S } } end
    local set = { fade = fade }
    for i, x in ipairs(rows) do
        set[i] = {}
        for j, y in ipairs(cols) do
            local p = t:CreateTexture(nil, layer, nil, sub)
            p:SetTexture(info.file or info.filename)
            p.u, p.v = { U(x[1]), U(x[2]) }, { V(y[1]), V(y[2]) }      -- its piece of the art (HeavyCoords)
            set[i][j] = p
        end
    end
    return set
end

--- The pieces' corners of the art for the way the tab hangs (t.sideways): under the frame the art a quarter
--- turned clockwise; down its right side the art as it lies, as drawn - square side against the frame, cut
--- corners out. The glow's short fade from the frame's edge goes with it: down from the top, or across from
--- the left (HeavyTab says why it fades).
local function HeavyCoords(t)
    local side = t.sideways
    for key, set in pairs(t.heavy) do
        local full = key == "hover" and HOVER_ALPHA or 1
        for i, row in ipairs(set) do
            for _, p in ipairs(row) do
                local u, v = p.u, p.v
                if side then
                    p:SetTexCoord(u[1], u[2], v[1], v[2])
                else
                    -- top left, bottom left, top right, bottom right: the art's bottom left, bottom right,
                    -- top left, top right - the quarter turn
                    p:SetTexCoord(u[1], v[2], u[2], v[2], u[1], v[1], u[2], v[1])
                end
                if set.fade and i == 1 then
                    if side then
                        p:SetGradient("HORIZONTAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, full))
                    else
                        p:SetGradient("VERTICAL", CreateColor(1, 1, 1, full), CreateColor(1, 1, 1, 0))
                    end
                end
            end
        end
    end
end

--- Forever's heavy art in place of the tab's thin art: false, and the tab left as the game draws it, when
--- the client has any of the three missing (the client's data has all three, build 70425).
local function HeavyTab(t)
    local info = {}
    for key, atlas in pairs(HEAVY) do
        info[key] = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
        if not (info[key] and (info[key].file or info[key].filename)) then return false end
    end
    t.heavy = {
        ground = HeavyPieces(t, info.ground, "BACKGROUND", 1, HEAVY_CUT),
        glow = HeavyPieces(t, info.glow, "BORDER", 0, GLOW_CUT, GLOW_FADE),
        edge = HeavyPieces(t, info.edge, "BORDER", 1, HEAVY_CUT),
        hover = HeavyPieces(t, info.glow, "HIGHLIGHT", 0, GLOW_CUT, GLOW_FADE),
    }
    for i, row in ipairs(t.heavy.hover) do
        for _, p in ipairs(row) do
            p:SetBlendMode("ADD")
            if i > 1 then p:SetAlpha(HOVER_ALPHA) end        -- the fade's row has it in its gradient, below
        end
    end
    -- The glow begins where the frame's edge ends (TabLook) and fades in from nothing there, over its top
    -- GLOW_FADE. Begun there at full it stopped hard against the edge: "hover gløden har litt hard kant
    -- opp mot ramma ... ser cutoff" (the owner, 2026-11-08). Begun behind the edge instead it showed
    -- through the edge's lower band, which is not solid ("nope", the owner's screenshot the same day: the
    -- band yellow over the tab's sides only). Faded down the whole of the sides, they were brightest just
    -- over the cut corners, which begin at full - "fortsatt en strek midt over gløden?" (the next
    -- screenshot: 115 then 60 across that seam). A gradient's first colour is its bottom, as the game's
    -- nameplates fade theirs (Blizzard_NamePlates.lua) - and as those screenshots showed, brighter down.
    -- The hover's faintness goes into the gradient itself: with SetAlpha as well, the fade's row ended at
    -- full, about twice the rest of the hover glow ("fortsatt glød cut midt på?", the owner, 2026-11-09:
    -- 97 then 49 across that seam, as 1 to 0.45) - the gradient's colours carry an alpha, and it won.
    HeavyCoords(t)
    -- the game's thin art and its glow stay, unseen: the tab's least width is theirs (PanelTemplates_TabResize)
    for _, k in ipairs({ "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
        "LeftHighlight", "MiddleHighlight", "RightHighlight" }) do
        if type(t[k]) == "table" then t[k]:SetAlpha(0) end
    end
    return true
end

--- The heavy art laid out for the tab's state: the chosen tab longer and lit, as the game's own chosen
--- tab is longer. The glow, lit or hover, starts below the frame's edge (HeavyTab says why).
local function TabLook(t)
    local on = t.selected and true or false
    -- the icon (folded, down the side) in the middle of what shows of the tab, as far out from the edge as
    -- the words under the frame sit down from it: 1 toward the edge, and 2 out on the chosen, longer tab
    t.icon:SetPoint("CENTER", t, "CENTER", on and -TAB_TEXT_Y_ON or -TAB_TEXT_Y, 0)
    if not t.heavy then return end
    local h, C = on and TAB_H_ON or TAB_H, HEAVY_CORNER
    for key, set in pairs(t.heavy) do
        local from = (key == "glow" or key == "hover") and TAB_TUCK or 0
        -- the rows' depths out from the frame's edge: the fade's own (the glow), what stretches, the cut
        -- corners - down the tab under the frame, across it down the frame's side
        local tall = set.fade and { set.fade, h - C - from - set.fade, C } or { h - C - from, C }
        local at = from
        for i, row in ipairs(set) do
            for j, p in ipairs(row) do
                p:ClearAllPoints()
                if t.sideways then
                    -- a row of the art is a column here, its three pieces down the tab: the art's bottom
                    -- (piece 1) at the tab's bottom, what stretches with the tab's length between the corners
                    p:SetWidth(tall[i])
                    if j == 2 then
                        p:SetPoint("TOPLEFT", t, "TOPLEFT", at, -C)
                        p:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", at, C)
                    else
                        local corner = j == 1 and "BOTTOMLEFT" or "TOPLEFT"
                        p:SetHeight(C)
                        p:SetPoint(corner, t, corner, at, 0)
                    end
                else
                    p:SetHeight(tall[i])
                    if j == 2 then
                        p:SetPoint("TOPLEFT", t, "TOPLEFT", C, -at)
                        p:SetPoint("TOPRIGHT", t, "TOPRIGHT", -C, -at)
                    else
                        p:SetWidth(C)
                        p:SetPoint(j == 1 and "TOPLEFT" or "TOPRIGHT", t, j == 1 and "TOPLEFT" or "TOPRIGHT", 0, -at)
                    end
                end
            end
            at = at + tall[i]
        end
    end
    for _, row in ipairs(t.heavy.glow) do
        for _, p in ipairs(row) do p:SetShown(on) end
    end
end

--- Hang a tab under the frame (side false) or down its right side (side true, folded): the art turned or as
--- it lies (HeavyCoords), and its words, or down the side its icon in their place (Tab, SetTabIcon).
TabSide = function(t, side)
    side = side and true or false
    if t.sideways == side then return end
    t.sideways = side
    t.Text:SetShown(not side)
    t.icon:SetShown(side)
    if not side then t:SetHeight(TAB_BUTTON_H) end
    if t.heavy then HeavyCoords(t) end
    TabLook(t)
end

local function SelectTab(i)
    tab, offset, turned = i, 0, false
    -- the game's chosen look: the tab raised and joined to the frame, and not clickable again
    for j, t in ipairs(win.tabs) do
        t.selected = j == i
        if t.selected then PanelTemplates_SelectTab(t) else PanelTemplates_DeselectTab(t) end
        TabLook(t)
    end
    PlaceTabs(Folded())                              -- folded, the row shows the group of the page
    Refresh()
end

--- A frame drawn from an atlas cut in nine, so its corners stay as drawn at any size - the ledger open is
--- far wider than the art, folded much narrower. corner: the corner pieces, in the art's pixels and on
--- screen. Without the atlas' numbers it is the art stretched whole, as Skillwright draws it.
--- The art is common-insideframe (107 x 107 in Forever): the profession window's inner panel, thin lines
--- with a small curl at each corner, see-through inside - the frame the owner pointed at in Skillwright
--- (2026-11-06). Options_InnerFrame was tried first and is a filled panel: it laid a second sheet, out of
--- place, over the page ("nå er det blitt skikkelig ødelagt").
local function InnerFrame(parent, atlas, corner)
    local f = CreateFrame("Frame", nil, parent)
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    local file = info and (info.file or info.filename)
    if not (file and (info.width or 0) > 2 * corner and (info.height or 0) > 2 * corner) then
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetAtlas(atlas)
        return f
    end
    local du = (info.rightTexCoord - info.leftTexCoord) * corner / info.width
    local dv = (info.bottomTexCoord - info.topTexCoord) * corner / info.height
    local u = { info.leftTexCoord, info.leftTexCoord + du, info.rightTexCoord - du, info.rightTexCoord }
    local v = { info.topTexCoord, info.topTexCoord + dv, info.bottomTexCoord - dv, info.bottomTexCoord }
    f.file, f.u, f.v, f.corner = file, u, v, corner           -- for a line in the same art (the divider)
    local function Piece(col, row)
        local t = f:CreateTexture(nil, "ARTWORK")
        t:SetTexture(file)
        t:SetTexCoord(u[col], u[col + 1], v[row], v[row + 1])
        return t
    end
    local tl, tr, bl, br = Piece(1, 1), Piece(3, 1), Piece(1, 3), Piece(3, 3)
    for _, c in ipairs({ { tl, "TOPLEFT" }, { tr, "TOPRIGHT" }, { bl, "BOTTOMLEFT" }, { br, "BOTTOMRIGHT" } }) do
        c[1]:SetSize(corner, corner)
        c[1]:SetPoint(c[2])
    end
    local top, bottom, left, right = Piece(2, 1), Piece(2, 3), Piece(1, 2), Piece(3, 2)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
    top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    return f
end

--- One of the game's tabs under the frame. Its size and place are PlaceTabs' alone: the template's own
--- OnShow and OnEvent size it to its words again, which undid a row squeezed to fit the folded window.
--- It sits at the frame's own level, under its edge (Build raises the edge), in Forever's heavy art
--- (HeavyTab), its text in the middle of what shows; the game's select and deselect read the two offsets.
local function Tab(text, onClick, icon)
    local t = CreateFrame("Button", nil, win, "PanelTabButtonTemplate")
    t:SetFrameLevel(win:GetFrameLevel())
    t.deselectedTextY, t.selectedTextY = TAB_TEXT_Y, TAB_TEXT_Y_ON
    t:SetText(text)
    t:SetScript("OnShow", nil)
    t:SetScript("OnEvent", nil)
    t:SetScript("OnClick", function(self)
        GK.Sound("IG_CHARACTER_INFO_TAB")
        onClick(self)
    end)
    -- folded, down the frame's side: an icon in its words' place (TabSide), and its name on the mouse
    t.icon = t:CreateTexture(nil, "ARTWORK")
    t.icon:SetSize(TAB_ICON, TAB_ICON)
    t.icon:Hide()
    t.iconMask = t:CreateMaskTexture()
    t.iconMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE",
        "CLAMPTOBLACKADDITIVE")
    t.iconMask:SetAllPoints(t.icon)
    SetTabIcon(t, icon or (ICONS .. "INV_Misc_QuestionMark"))       -- a page that brought none
    t:HookScript("OnEnter", function(self)
        if not self.sideways then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self:GetText() or "")
        GameTooltip:Show()
    end)
    t:HookScript("OnLeave", function(self)
        if self.sideways then GameTooltip:Hide() end
    end)
    HeavyTab(t)
    TabLook(t)
    return t
end

local function Build()
    -- The game's own frame: its bronze edges, title bar and X. Its flat grey backdrop gives way to the
    -- parchment, where Guildhall puts its wood panel.
    win = CreateFrame("Frame", "GrudgekeeperFrame", UIParent, "SettingsFrameTemplate")
    win:SetSize(OPEN.W, OPEN.H)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetPoint("CENTER", 0, 30)
    if type(win.Bg) == "table" then win.Bg:Hide() end
    if type(win.NineSlice) == "table" and win.NineSlice.Text then win.NineSlice.Text:SetText("Grudgekeeper") end
    win.sheet = win:CreateTexture(nil, "BACKGROUND")       -- the look's background (Layout)
    win.sheet:SetPoint("TOPLEFT", 7, -18)
    win.sheet:SetPoint("BOTTOMRIGHT", -3, 3)
    -- what is written on the pages (+3), the fold beside the X (the X's own level)
    local level = win:GetFrameLevel()
    win.list = CreateFrame("Frame", nil, win)
    win.list:SetFrameLevel(level + 3)
    win.list:SetSize(PAGE_W, PAGE_H)
    BuildList(win.list)
    win.detail = CreateFrame("Frame", nil, win)
    win.detail:SetFrameLevel(level + 3)
    win.detail:SetSize(PAGE_W, PAGE_H)
    BuildDetail(win.detail)
    -- One thin inner frame round both pages, the profession window's own as Skillwright has it
    -- (common-insideframe, its corners kept as drawn at any size), and one line between the pages. Two
    -- bronze inset boxes, one per page, "ser litt rart ut" - "hva med den tynne rammen som hadde litt
    -- border pynt? ... bare en strek som deler hver side" (the owner, 2026-11-06). Over the sheet, under
    -- the pages.
    win.inner = InnerFrame(win, "common-insideframe", 32)
    win.inner:SetFrameLevel(level + 2)
    win.inner:SetPoint("TOPLEFT", FX - 8, -(FY - 6))
    win.inner:SetPoint("BOTTOMRIGHT", -(FX - 8), FB - 8)
    -- The line between the pages, in the same art: a strip of the frame's own left edge, run from its top
    -- line to its bottom one down the middle. The edge's line sits LINE_X in from the piece's outer side
    -- (measured on the owner's screenshot, 2026-11-06: about 3.5 of its 32), so the strip starts that much
    -- left of the middle, and is only as wide as the line and its shading. (The Settings window's
    -- divider stood on end was tried first and drew nothing.)
    local LINE_X, STRIP = 4, 8
    local mid = FX + PAGE_W + FGAP / 2 - (FX - 8)            -- the middle, from the inner frame's left
    win.divider = win.inner:CreateTexture(nil, "ARTWORK")
    if win.inner.file then
        local u, v = win.inner.u, win.inner.v
        win.divider:SetTexture(win.inner.file)
        win.divider:SetTexCoord(u[1], u[1] + (u[2] - u[1]) * STRIP / win.inner.corner, v[2], v[3])
    else
        Paint(win.divider, "rule")
    end
    win.divider:SetWidth(STRIP)
    win.divider:SetPoint("TOPLEFT", win.inner, "TOPLEFT", mid - LINE_X, -LINE_X)
    win.divider:SetPoint("BOTTOMLEFT", win.inner, "BOTTOMLEFT", mid - LINE_X, LINE_X)
    -- the tabs (PlaceTabs puts them under the frame)
    win.tabs = {}
    for i, def in ipairs(GK.LedgerPages) do
        local t = Tab(def.name, function() SelectTab(i) end, def.icon)
        t.side = def.side
        win.tabs[i] = t
    end
    -- folded: the last tab of the row, which switches to the other group of pages
    win.swap = Tab("Friends", function()
        local toRight = not (GK.LedgerPages[tab] and GK.LedgerPages[tab].side == "right")
        for i, def in ipairs(GK.LedgerPages) do
            if (def.side == "right") == toRight then return SelectTab(i) end
        end
    end)
    PanelTemplates_DeselectTab(win.swap)
    win.swap:Hide()
    -- The frame's edge over the tabs' tops (they are at the frame's own level, Tab), and under the inner
    -- frame and the pages as before. The template makes it at the frame's own level too.
    if type(win.NineSlice) == "table" then win.NineSlice:SetFrameLevel(level + 1) end
    -- the template's X: its click is our own, as the template's HideUIPanel does nothing in combat. Over
    -- the edge, now the edge is raised: the X sits on its corner.
    local close = type(win.ClosePanelButton) == "table" and win.ClosePanelButton
        or CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetScript("OnClick", function() win:Hide() end)
    close:SetFrameLevel(level + 4)
    win.close = close
    -- The fold: the spells panel's own button beside the X (the owner's screenshot, 2026-11-06), the
    -- game's red square with the arrow - out to open the window, in to fold it to one page. Its own
    -- button with the template's atlases, not MaximizeMinimizeButtonFrameTemplate: that one keeps a state
    -- of its own and resets it from a CVar on show, and ours is GK.db.ledgerFolded. Against the X, 1 apart,
    -- as the world map and the spells panel have theirs.
    local fold = CreateFrame("Button", nil, win)
    fold:SetFrameLevel(close:GetFrameLevel())
    fold:SetPoint("RIGHT", close, "LEFT", -1, 0)
    fold:SetSize(24, 24)
    fold:SetHighlightAtlas("RedButton-Highlight", "ADD")
    function fold:Set(folded)
        local art = folded and "RedButton-Expand" or "RedButton-Condense"
        self:SetNormalAtlas(art)
        self:SetPushedAtlas(art .. "-Pressed")
        self.tip = folded and "Show both pages" or "Fold to one page"
    end
    fold:SetScript("OnClick", function()
        GK.Sound("IG_MAINMENU_OPTION_CHECKBOX_ON")
        Fold(not Folded())
    end)
    fold:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.tip or "Fold to one page", 1, 1, 1)
        GameTooltip:Show()
    end)
    fold:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.fold = fold
    win:Hide()
    if LIB.RegisterWindow then LIB.RegisterWindow(win, GK.db, "window") end
    win:HookScript("OnShow", function() Refresh() end)
    -- a sheet opened on the ledger (a note, a kill order, the who-picker) closes with it (Letters.lua)
    win:HookScript("OnHide", function() GK.CloseLedgerSheets() end)
    Layout()
    SelectTab(tab)
end

--- The row whose detail shows: the chosen one if it is still there, else the page's own default.
local function Chosen(items)
    local key = selected[tab]
    if key then
        for _, it in ipairs(items) do
            if it.key == key then return it end
        end
    end
    local def = GK.LedgerPages[tab]
    local first = def.default and def.default(items)
    if first then return first end
    for _, it in ipairs(items) do
        if not it.header and not it.faded then return it end
    end
    return nil
end

Refresh = function()
    if not (win and win:IsShown()) then return end
    local folded = Folded()
    local def = GK.LedgerPages[tab]
    local items, empty = def.items()
    local all = #items                                 -- before the page's max (GK.SortItems)
    if def.sortable then items, all = GK.SortItems(items, def) end
    local list, detail = win.list, win.detail
    local chosen = Chosen(items)
    -- the list page
    list.title:SetText(def.name)
    local links = def.links and def.links() or {}
    local last
    for i, b in ipairs(list.links) do
        local l = links[i]
        b:SetShown(l ~= nil)
        if l then
            b:Set(l.text, l.on)
            b.click = l.click
            b:ClearAllPoints()
            if last then b:SetPoint("LEFT", last, "RIGHT", 12, 0) else b:SetPoint("TOPLEFT", 10, -40) end
            last = b
        end
    end
    list.reset:ClearAllPoints()
    if last then list.reset:SetPoint("LEFT", last, "RIGHT", 4, 0) end
    list.reset:SetText(last and def.linksTail and def.linksTail() or "")
    list.sub:ClearAllPoints()
    if last then
        -- on the links' line, after the tail if there is one; under them it ran into the links
        list.sub:SetPoint("LEFT", list.reset:GetText() ~= "" and list.reset or last, "RIGHT", 10, 0)
    else
        list.sub:SetPoint("TOPLEFT", 12, -44)
    end
    local sortable = def.sortable == true
    list.mine:SetShown(sortable)
    if sortable then list.mine:Set("Only mine", GK.db.mineOnly == true) end
    -- the line stops short of Only mine, on its own line at the page's right (after links it is free:
    -- no page has both)
    list.sub:SetWidth(last and 0 or (PAGE_W - 24 - (sortable and list.mine.width + 10 or 0)))
    list.sub:SetText(def.sub and def.sub(items, all) or "")
    list.add:SetShown(def.add ~= nil)
    list.underline:SetShown(#def.headings > 0)
    -- A page with no heading row starts its list where the headings would be: the Grudges page's list
    -- sat a heading row's height too far down ("trenger ikke bli dytta så langt inn", the owner, 2026-11-07).
    local top = #def.headings > 0 and LIST_TOP or LIST_TOP - 30
    if list.top ~= top then
        list.top = top
        for i, row in ipairs(list.rows) do row:SetPoint("TOPLEFT", 4, -(top + (i - 1) * ROW_H)) end
    end
    if def.add then list.add:Set(def.add) end
    local sortKey = GK.SortKey(def)
    for i, b in ipairs(list.heads) do
        local h = def.headings[i]
        b:ClearAllPoints()
        b:SetShown(h ~= nil)
        if not h then b.key, b.on = nil, false end
        if h then
            b.key, b.tip = sortable and h[4] or nil, h[5]
            b.on = b.key ~= nil and b.key == sortKey
            b:EnableMouse(b.key ~= nil)
            b.text:SetText(h[1]:upper())
            Ink(b.text, b.on and BLOOD or FADED, TEXT_FONT, 10)
            b.line:SetShown(b.on)
            b:SetWidth(math.ceil(TextWidth(b.text)) + 2)
            if h[3] == "RIGHT" then b:SetPoint("BOTTOMRIGHT", list, "TOPLEFT", h[2] - 4, -(LIST_TOP - 6))
            elseif h[3] == "CENTER" then b:SetPoint("BOTTOM", list, "TOPLEFT", h[2] - 4, -(LIST_TOP - 6))
            else b:SetPoint("BOTTOMLEFT", list, "TOPLEFT", h[2], -(LIST_TOP - 6)) end
        end
    end
    -- whole pages: the page the offset falls in, and where it stops
    local starts = GK.PageStarts(items)
    list.starts = starts
    local at = 1
    for i, s in ipairs(starts) do
        if s <= offset then at = i end
    end
    offset = starts[at]
    local stop = starts[at + 1] or #items              -- the last item on this page
    for i, row in ipairs(list.rows) do
        local it = offset + i <= stop and items[i + offset] or nil
        if it then
            row:Show()
            FillRow(row, it, chosen ~= nil and it.key == chosen.key)
        else
            row:Hide()
        end
    end
    list.empty:SetText(#items == 0 and empty or "")
    local more = #starts > 1
    list.count:SetShown(more)
    list.prev:SetShown(more)
    list.next:SetShown(more)
    if more then
        list.count:SetText(offset + 1 == stop and ("%d of %d"):format(stop, #items)
            or ("%d-%d of %d"):format(offset + 1, stop, #items))
        list.prev:SetEnabled(at > 1)
        list.next:SetEnabled(at < #starts)
    end
    local unread = GK.Unread()
    list.letters:Set(unread > 0 and ("Letters \194\183 %d new"):format(unread) or "Letters")      -- "Letters · 2 new"
    -- with no letter waiting it has nothing to open: a read letter is gone once closed (Letters.lua)
    list.letters:SetEnabled(#GK.char.letters > 0)
    list.readAll:SetShown(unread > 1)
    -- the detail: the right-hand page, or the page turned
    local showDetail = not folded or turned
    list:SetShown(not folded or not turned)
    detail:SetShown(showDetail)
    detail.back:SetShown(folded)
    detail.back.text:SetText("\194\171 Back to " .. def.name:lower())
    if showDetail then FillDetail(detail, DetailCard(chosen and chosen.select), #items > 0) end
end

function GK.OpenWindow(page)
    if not win then Build() end
    if page and win.tabs[page] then SelectTab(page) end
    win:Show()
    win:Raise()
    Refresh()
end

--- The kill orders page, on this order (by its key) when it has a row there; else the page as it was.
function GK.OpenOrder(orderKey)
    GK.OpenWindow(1)                                 -- first: choosing the tab starts the page afresh
    if type(orderKey) == "string" and GK.Store().orders[orderKey] then
        selected[1] = "o:" .. orderKey
        turned = turned or Folded()                  -- folded: the page turned to it
        Refresh()
    end
end

function GK.ToggleWindow()
    if win and win:IsShown() then win:Hide() else GK.OpenWindow() end
end

--- The ledger open at a page found by its name, on the row with this key when the page has one; the book
--- open or folded (folded, nil: as it is) and the leaderboard on this week or all time (weeklyBoard, nil:
--- as it is). For the screenshot mode (Shots.lua), which names the page it wants a picture of. False when
--- there is no such page.
function GK.ShowLedgerPage(name, rowKey, folded, weeklyBoard)
    if not win then Build() end
    for i, def in ipairs(GK.LedgerPages) do
        if def.name == name then
            if folded ~= nil and folded ~= Folded() then Fold(folded) end
            if weeklyBoard ~= nil then weekly = weeklyBoard end
            SelectTab(i)
            selected[i] = rowKey
            win:Show()
            win:Raise()
            Refresh()
            return true
        end
    end
    return false
end

--- Fold the ledger to one page (on) or open it to two, kept as the choice, as its own button does.
function GK.FoldLedger(on)
    if win then Fold(on) else GK.db.ledgerFolded = on or nil end
end

--- The ledger's frame and its tabs, which hang below it - folded, down its right side: what a picture of the
--- ledger has to take in.
function GK.LedgerFrames()
    if not win then return {} end
    local list = { win, win.swap }                  -- the swap tab: folded, the last of them
    for _, t in ipairs(win.tabs) do list[#list + 1] = t end
    return list
end

-- Once per burst of changes (GK.Changed gathers them); Refresh returns at once while the book is shut.
LIB.Listen("GRUDGEKEEPER_CHANGED", function() Refresh() end)
