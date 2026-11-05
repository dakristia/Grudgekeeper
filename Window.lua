-- Grudgekeeper - the window (/grudge, the minimap button): the Grudgekeeper's ledger, an open book.
--   Leather tabs on top, one per page of GK.LedgerPages: Kill orders, Leaderboard, Grudges, News and
--   Kill on sight over the left page; Watch, Kudos and Names over the right page (NotesUI.lua).
--   The left page is that page's table; the right page is the row you clicked - an enemy's wanted
--   poster, a guildie's record (Profile.lua writes both, for the small cards and for here).
-- Folded by the bookmark on its right edge, the ledger is one page: the table, and a click on a row
-- turns that page to the row, with Back to return. GK.db.ledgerFolded keeps the choice.
-- Nothing here ever opens by itself: this is where you come to look.
-- The art (art/import_grudgekeeper.py): Media/ledger_book (the whole book lying open, pages and all),
-- ledger_tab (the tabs and the bookmark), rank_1..3 (the top three's seals), portrait_ring, close.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local TITLE_FONT = "Fonts\\MORPHEUS.ttf"
local TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local INK = { 0.22, 0.13, 0.05 }
local FADED = { 0.35, 0.25, 0.15 }        -- 0.42/0.33/0.22 blended into the parchment in the game
local BLOOD = { 0.47, 0.06, 0.04 }

-- The book, in UI units: one picture per view. Media/ledger_book is the book open at two pages (a
-- 1502x992 picture), Media/ledger_single the book folded back to one page (1103x1348). Measured by
-- art/import_grudgekeeper.py (2026-11-04), as fractions of each picture: where the parchment is (and
-- the gutter), the socket for the close button (centre, and radius as a fraction of the width), where
-- the cover's top edge is (the spine's headband can stand above it), and how far the top-right iron
-- reaches along that edge. The folded one is drawn at the scale that makes its page as wide as an open
-- one's, so what is written on a page sits the same in both.
local OPEN = { w = 1502, h = 992, left = 0.0499, gutter = 0.4987, top = 0.0302, bottom = 0.9466,
               sx = 0.9747, sy = 0.0373, sr = 0.0151, edge = 0.008, iron = 0.0586 }
local SINGLE = { w = 1103, h = 1348, left = 0.1215, right = 0.9166, top = 0.0564, bottom = 0.9444,
                 sx = 0.9405, sy = 0.0475, sr = 0.0367, edge = 0.016, iron = 0.146 }
local W_OPEN = 820
local function Fit(book, width)
    local scale = width / book.w
    book.W, book.H = width, book.h * scale
    book.x, book.y = book.left * width, book.top * book.H                   -- the page's top left
    book.close = { (1 - book.sx) * width, book.sy * book.H, 2 * book.sr * width }   -- in, down, across
    book.cover = book.edge * book.H                                         -- the cover's top edge
    book.stop = width - book.iron * width - 4                               -- where the tabs must end
    return book
end
Fit(OPEN, W_OPEN)                                    -- 820 x ~542, the hole ~25 across
local PAGE_W = (OPEN.gutter - OPEN.left) * W_OPEN    -- ~368
local PAGE_H = (OPEN.bottom - OPEN.top) * OPEN.H     -- ~496
local GUTTER_X = OPEN.gutter * W_OPEN                -- where the right page starts, ~409
Fit(SINGLE, PAGE_W / (SINGLE.right - SINGLE.left))   -- ~463 x ~566, the hole ~34 across
OPEN.stopRight = OPEN.stop                           -- open, the right group may run to the iron...
OPEN.stop = GUTTER_X - 30                            -- ...and the left group stays over the left page
OPEN.x2, SINGLE.x2 = GUTTER_X, SINGLE.x              -- where the right-hand (or only) page starts
-- The other look, to compare (GK.db.ledgerLook = "frame", switched from /grudge debug): the same pages
-- on a plain sheet (Media/sheet_wide, sheet_single) in Blizzard's own SettingsFrameTemplate, which
-- Forever draws in bronze. Laid out as Guildhall's window is: the sheet where the template's backdrop
-- goes (7,-18 to -3,3), the pages clear of the frame's edges and under its title bar.
local FX, FY, FGAP, FB = 20, 34, 16, 14
local FRAME = { W = 2 * FX + 2 * PAGE_W + FGAP, H = FY + PAGE_H + FB, x = FX, y = FY, cover = 0 }
FRAME.x2, FRAME.stop = FX + PAGE_W + FGAP, FX + PAGE_W
FRAME.stopRight = FRAME.W - 34                       -- clear of Blizzard's X in the corner
local FRAME_FOLDED = { W = 2 * FX + PAGE_W, H = FRAME.H, x = FX, y = FY, x2 = FX, cover = 0 }
FRAME_FOLDED.stop = FRAME_FOLDED.W - 34              -- clear of Blizzard's X in the corner
local ROW_H, ROWS = 32, 9
local FACE = 30                                      -- a row's portrait; 26 blended into the page
local LIST_TOP = 112                                 -- the first row, down from the page's top
-- the right-hand column stops short of the row's end: room for the chosen row's red bar, and folded,
-- for the » that says a click turns the page (they ran into each other in the preview)
local COL1, COL2, COL_WIDE, COL_RIGHT = 232, 266, 196, PAGE_W - 36
local TAB_V0, TAB_V1, TAB_CAP = 16 / 128, 112 / 128, 0.08   -- ledger_tab: the tab across rows 16-112
-- The tabs' height, 8 of it behind the book's top edge, so they come out of the pages (laid on the
-- cover they looked loose); 24/30 in 13pt was too big, 20/24 in 12pt read small in the game.
local TAB_H, TAB_H_ON, TAB_FONT = 22, 26, 14
local TAB_PAD, TAB_FONT_MIN = 22, 10                 -- a tab's width beyond its label; the smallest type FitTabs goes to

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

local function Ink(fs, colour, font, size)
    fs:SetFont(font, size, "")
    fs:SetTextColor(colour[1], colour[2], colour[3])
    fs:SetShadowOffset(0, 0)
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
-- What each page lists. An item: { key, name, sub, rank, seal, face = { rf, sx, c }, c1, c2, wide,
-- right, rightColour, faded, mine, own, ts, votes, header, select = { kind = "poster", t, order } or
-- { kind = "record", key } or { kind = "card", make } }
-- mine tints the row; own only says the row is yours, for Mine only; ts and votes are what the sort
-- menu orders by (GK.SortItems).
-- ---------------------------------------------------------------------------
local STATE_WORD = { d = "FULFILLED", p = "PAID", x = "WITHDRAWN", e = "EXPIRED" }

local function PosterSpec(key, x, order)
    return { kind = "poster", order = order,
        t = { key = key, guid = x and x.guid, c = x and x.c, r = x and x.r, l = x and x.l } }
end

local function OrderItems()
    local items, me = {}, LIB.Me()
    for _, o in ipairs(GK.AllOrders()) do
        local pot, backers = GK.Pot(o)
        local it = { key = "o:" .. o.key, name = GK.Show(o.n), face = { c = o.c }, select = PosterSpec(o.n, o, o),
            ts = o.t, own = GK.char.accepted[o.key] or (me and (o.by == me or o.doneBy == me or (o.pot and o.pot[me]))) or nil }
        if o.state == "o" then
            it.right = pot > 0 and GK.MoneyText(pot) or "honour"
            local hunting = 0
            for _ in pairs(o.hunters or {}) do hunting = hunting + 1 end
            local bits = { o.auto and ("by %s's death"):format(GK.Show(o.by)) or ("by " .. GK.Show(o.by)) }
            if backers > 0 then bits[#bits + 1] = Plural(backers, "backer") end
            if hunting > 0 then bits[#bits + 1] = hunting .. " hunting" end
            if o.seen then bits[#bits + 1] = "seen " .. GK.Ago(o.seen.t) end
            it.sub = table.concat(bits, " - ")
        else
            it.faded, it.right, it.rightColour = true, STATE_WORD[o.state] or "", BLOOD
            it.sub = (o.doneBy and ("by " .. GK.Show(o.doneBy) .. " - ") or "") .. GK.Ago(o.paidAt or o.doneAt)
        end
        items[#items + 1] = it
    end
    return items, "No kill orders. Right-click an enemy player and pick Post a kill order - or put a price "
        .. "on someone who killed you, from the Grudges page."
end

local function BoardItems()
    local items = {}
    for i, r in ipairs(GK.Board(weekly)) do
        items[#items + 1] = { key = "b:" .. r.who, rank = i, seal = i <= 3 and r.p > 0,
            name = GK.Show(r.who), sub = GK.Title(r.total), face = { rf = r.rf, sx = r.sx, c = r.c },
            c1 = tostring(r.k), c2 = tostring(r.d), right = tostring(r.p), mine = r.me,
            select = { kind = "record", key = r.who } }
    end
    local wanted = GK.MostWanted()
    if #wanted > 0 then
        items[#items + 1] = { header = true, name = "Most wanted" }
        for i = 1, math.min(#wanted, 10) do
            local e = wanted[i]
            local o = GK.OrderOn(e.key)
            items[#items + 1] = { key = "w:" .. e.key, name = GK.Show(e.key), sub = GK.Describe(e.w.l, e.w.c, e.w.r),
                face = { c = e.w.c }, wide = "killed us " .. e.total,
                right = o and ((GK.Pot(o)) > 0 and GK.MoneyText((GK.Pot(o))) or "order") or "",
                rightColour = BLOOD, select = PosterSpec(e.key, e.w) }
        end
    end
    return items, ""
end

local function GrudgeItems()
    local items, c = {}, GK.char
    local foes = {}
    for k, v in pairs(c.foes) do
        if (v.k or 0) + (v.d or 0) > 0 then foes[#foes + 1] = { key = k, f = v } end
    end
    table.sort(foes, function(a, b) return (a.f.k + a.f.d) > (b.f.k + b.f.d) end)
    if #foes > 0 then items[#items + 1] = { header = true, name = "Your grudges" } end
    for i = 1, math.min(#foes, 40) do
        local e = foes[i]
        items[#items + 1] = { key = "f:" .. e.key, name = GK.Show(e.key), face = { c = e.f.c },
            sub = GK.Describe(e.f.l, e.f.c, e.f.r) .. " - last met " .. GK.Ago(e.f.last),
            c1 = tostring(e.f.k or 0), c2 = tostring(e.f.d or 0), select = PosterSpec(e.key, e.f),
            ts = e.f.last, own = true }
    end
    if #c.log > 0 then items[#items + 1] = { header = true, name = "Lately" } end
    for i, e in ipairs(c.log) do
        local it = { key = "l:" .. i, face = { c = e.c }, select = PosterSpec(e.n, e), ts = e.t, own = true,
            sub = table.concat({ e.z or "", GK.Ago(e.t) }, e.z and " - " or "") }
        if e.k == "K" then
            it.name = "Killed " .. GK.Show(e.n)
            it.right = (e.p or 0) > 0 and ("+%d"):format(e.p) or "no points"
        else
            it.name, it.right, it.rightColour = "Slain by " .. GK.Show(e.n), e.s or "", BLOOD
        end
        items[#items + 1] = it
    end
    return items, "No kills or deaths yet. Only the open world counts: dungeons and battlegrounds hide who is who."
end

local function NewsItems()
    local items = {}
    for i, e in ipairs(GK.Store().feed) do
        local who, target = GK.Show(e.who), GK.Show(e.n)
        local line, right
        if e.kind == "K" then
            line = ("%s killed %s"):format(who, target)
            right = (e.p or 0) > 0 and ("+%d"):format(e.p) or nil
        elseif e.kind == "D" then
            line = ("%s fell to %s"):format(who, target)
        elseif e.kind == "F" then
            line = ("%s fulfilled the order on %s"):format(who, target)
            right = (e.p or 0) > 0 and GK.MoneyText(e.p) or nil
        elseif e.kind == "C" and e.au then
            line, right = ("%s's death put a price on %s"):format(who, target), "honour"
        elseif e.kind == "C" then
            line = ("%s put a price on %s"):format(who, target)
            right = (e.p or 0) > 0 and GK.MoneyText(e.p) or "honour"
        elseif e.kind == "T" then
            line, right = ("%s added to the pot on %s"):format(who, target), GK.MoneyText(e.p or 0)
        end
        if line then
            items[#items + 1] = { key = "n:" .. i, name = line, face = { c = e.c }, right = right,
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
--- { name, items = fn -> items, empty text, headings, sub = fn(items) -> text, links = fn -> { { text, on,
--- click } }, linksTail = fn -> text, sortable, side, default = fn(items) -> the row chosen when none is }.
--- headings: the column headings over the table, { text, x, justify }. links: ink links under the title.
--- side: "right" puts the tab over the right page in the open book (the friendly lists); anything else is
--- over the left page. Folded, all the tabs share one row. A page with links and a sub line has the sub
--- text after the links, on their line.
GK.LedgerPages = {
    { name = "Kill orders", items = OrderItems,
      headings = { { "Name", 48 }, { "Bounty", COL_RIGHT, "RIGHT" } }, sortable = true,
      sub = function()
          local rank, of = GK.MyRank()
          return ("%s  -  you: %s, #%d of %d"):format(Plural(#GK.OpenOrders(), "open order"),
              Plural(GK.char.points, "point"), rank, of)
      end },
    { name = "Leaderboard", items = BoardItems,
      headings = { { "#", 12 }, { "Name", 48 }, { "K", COL1, "CENTER" }, { "D", COL2, "CENTER" },
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
    { name = "Grudges", items = GrudgeItems, sortable = true,
      headings = { { "Name", 48 }, { "You", COL1, "CENTER" }, { "They", COL2, "CENTER" } },
      sub = function() return "Everyone you have a history with" end,
      default = function() return { key = "me", select = { kind = "record", key = LIB.Me() } } end },
    { name = "News", items = NewsItems, sortable = true,
      headings = { { "What happened", 48 } },
      sub = function() return "What the guild has been up to" end },
}

--- Adds a page after the ledger's own. Only before the book is first built: the tabs are made then.
function GK.AddLedgerPage(def)
    assert(not win, "GK.AddLedgerPage: the ledger is already built")
    table.insert(GK.LedgerPages, def)
end

local SORTS = { { "default", "Default" }, { "newest", "Newest" }, { "oldest", "Oldest" }, { "name", "A-Z" },
    { "votes", "Votes" } }

local function SortWord(mode)
    for _, s in ipairs(SORTS) do
        if s[1] == mode then return s[2] end
    end
    return SORTS[1][2]
end

--- A page's rows in the order GK.db.sortMode asks for, and only yours with GK.db.mineOnly. Sorting or
--- filtering drops the header rows and sorts the rest together; the page's own order, without Mine only,
--- is left alone. Ties go A-Z. Returns a new list, or the same one untouched.
function GK.SortItems(items, page)
    local mode, mineOnly = GK.db.sortMode or "default", GK.db.mineOnly == true
    if not (page and page.sortable) or (mode == "default" and not mineOnly) then return items end
    local out, at = {}, {}
    for _, it in ipairs(items) do
        if not it.header and (not mineOnly or it.own or it.mine) then
            out[#out + 1] = it
            at[it] = #out
        end
    end
    if mode == "default" then return out end
    local function Name(it) return (it.name or ""):lower() end
    table.sort(out, function(a, b)
        local x, y
        if mode == "newest" then x, y = b.ts or 0, a.ts or 0
        elseif mode == "oldest" then x, y = a.ts or 0, b.ts or 0
        elseif mode == "votes" then x, y = b.votes or 0, a.votes or 0 end
        if x and x ~= y then return x < y end
        local na, nb = Name(a), Name(b)
        if na ~= nb then return na < nb end
        return at[a] < at[b]                   -- table.sort needs a strict order, or it can error
    end)
    return out
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
        local me = LIB.Me()
        table.insert(d.lines, 1, ("The order is closed: %s%s, %s."):format(STATE_WORD[o.state] or "",
            o.doneBy and (" by " .. GK.Show(o.doneBy)) or "", GK.Ago(o.paidAt or o.doneAt)))
        local owe = 0
        for _, e in ipairs(GK.Owed()) do
            if e.o == o then owe = owe + e.share end
        end
        if owe > 0 and o.doneBy ~= me then
            table.insert(d.lines, 2, ("You owe %s %s - at a mailbox, Pay bounty fills it in."):format(
                GK.Show(o.doneBy), GK.MoneyText(owe)))
            d.buttons = { { "Mark as paid", function() GK.PayShare(o) end } }
        end
    end
    return d
end
GK.LedgerCard = DetailCard                 -- the Classic look shows the same card for a row's select

--- "All time: 31 kills, 12 deaths." reads as a two-column row: a short label, then the rest.
local function Split(line)
    local label, value = line:match("^([^:,]+): (.+)$")
    if label and #label <= 14 then return label, value end
    return nil, line
end

-- ---------------------------------------------------------------------------
-- Building the book
-- ---------------------------------------------------------------------------
--- A leather tab: the tab art in three pieces, so any width keeps its rounded ends. h is the tab's
--- thickness. side: the tab turned a quarter clockwise, standing out of the book's right edge, its rounded
--- end outward (in one stretched piece its corners were squashed flat: "ser ikke så bra ut").
local function TabArt(parent, h, side)
    local cap = h * 512 * TAB_CAP / 96
    local function Piece(u0, u1)
        local t = parent:CreateTexture(nil, "ARTWORK")
        t:SetTexture(MEDIA .. "ledger_tab")
        -- turned: down the screen runs along the art, rightward runs up it (eight-number form: UL, LL, UR, LR)
        if side then t:SetTexCoord(u0, TAB_V1, u1, TAB_V1, u0, TAB_V0, u1, TAB_V0)
        else t:SetTexCoord(u0, u1, TAB_V0, TAB_V1) end
        return t
    end
    local a, m, b = Piece(0, TAB_CAP), Piece(TAB_CAP, 1 - TAB_CAP), Piece(1 - TAB_CAP, 1)
    if side then
        a:SetPoint("TOPLEFT")
        a:SetPoint("TOPRIGHT")
        a:SetHeight(cap)
        b:SetPoint("BOTTOMLEFT")
        b:SetPoint("BOTTOMRIGHT")
        b:SetHeight(cap)
        m:SetPoint("TOPLEFT", a, "BOTTOMLEFT")
        m:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT")
    else
        a:SetPoint("TOPLEFT")
        a:SetPoint("BOTTOMLEFT")
        a:SetWidth(cap)
        b:SetPoint("TOPRIGHT")
        b:SetPoint("BOTTOMRIGHT")
        b:SetWidth(cap)
        m:SetPoint("TOPLEFT", a, "TOPRIGHT")
        m:SetPoint("BOTTOMRIGHT", b, "BOTTOMLEFT")
    end
    return { a, m, b }
end

--- A round portrait in the bronze ring; badge: a class crest on its lower right, for a face.
local function MakePortrait(parent, size)
    local p = {}
    p.tex = parent:CreateTexture(nil, "ARTWORK")
    p.tex:SetSize(size * 0.82, size * 0.82)
    local mask = parent:CreateMaskTexture()
    mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(p.tex)
    p.tex:AddMaskTexture(mask)
    p.ring = parent:CreateTexture(nil, "OVERLAY")
    p.ring:SetTexture(MEDIA .. "portrait_ring")
    p.ring:SetSize(size, size)
    p.ring:SetPoint("CENTER", p.tex, "CENTER")
    -- No dark rim behind the ring: one was tried for contrast and read as a brown halo ("ser litt rart
    -- ut", 2026-11-05).
    p.badge = parent:CreateTexture(nil, "OVERLAY", nil, 2)
    p.badge:SetSize(size * 0.42, size * 0.42)
    p.badge:SetPoint("CENTER", p.tex, "BOTTOMRIGHT", -size * 0.06, size * 0.06)
    function p:Set(face)
        local kind = GK.SetPortrait(self.tex, face)
        local coords = kind == "race" and face.c and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[face.c]
        self.badge:SetShown(coords and true or false)
        if coords then
            self.badge:SetTexture(CLASS_ICONS)
            self.badge:SetTexCoord(unpack(coords))
        end
    end
    function p:SetShown(on)
        self.tex:SetShown(on)
        self.ring:SetShown(on)
        if not on then self.badge:Hide() end
    end
    return p
end

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
    row.wash = row:CreateTexture(nil, "BACKGROUND")
    row.wash:SetAllPoints()
    row.rule = row:CreateTexture(nil, "BORDER")
    row.rule:SetColorTexture(0.27, 0.35, 0.55, 0.28)      -- a ledger's blue rule
    row.rule:SetHeight(1)
    row.rule:SetPoint("BOTTOMLEFT", 4, 0)
    row.rule:SetPoint("BOTTOMRIGHT", -4, 0)
    row.mark = row:CreateTexture(nil, "ARTWORK")           -- the chosen row's red bar
    row.mark:SetColorTexture(BLOOD[1], BLOOD[2], BLOOD[3], 0.9)
    row.mark:SetSize(3, ROW_H - 6)
    row.mark:SetPoint("RIGHT", -2, 0)
    row.seal = row:CreateTexture(nil, "ARTWORK")
    row.seal:SetSize(24, 24)
    row.seal:SetPoint("LEFT", 2, 0)
    -- every font string gets its font HERE, not when filled: the game refuses SetText - even SetText("")
    -- - on one that has none, and a header row is filled before any player row ever was (2026-11-05)
    row.rank = row:CreateFontString(nil, "OVERLAY")
    Ink(row.rank, FADED, TITLE_FONT, 13)
    row.rank:SetPoint("CENTER", row.seal, "CENTER", 0, 0)
    row.face = MakePortrait(row, FACE)
    row.face.tex:SetPoint("CENTER", row, "LEFT", 55, 0)
    row.name = row:CreateFontString(nil, "ARTWORK")
    Ink(row.name, INK, TITLE_FONT, 13)
    row.name:SetPoint("TOPLEFT", 74, -3)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "ARTWORK")
    Ink(row.sub, FADED, TEXT_FONT, 11)
    row.sub:SetPoint("TOPLEFT", 74, -19)
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
    row.open = row:CreateFontString(nil, "ARTWORK")        -- folded: "this turns the page"
    Ink(row.open, FADED, TEXT_FONT, 13)
    row.open:SetPoint("RIGHT", -4, 0)
    row.open:SetText("\194\187")                            -- », in the game's Latin-1 fonts
    row:SetScript("OnClick", function(self) if self.item and not self.item.header then Select(self.item) end end)
    row:SetScript("OnEnter", function(self)
        if self.item and not self.item.header and not self.chosen then self.wash:SetColorTexture(0.6, 0.12, 0.05, 0.07) end
    end)
    row:SetScript("OnLeave", function(self) if self.fill then self.fill() end end)
    return row
end

local function FillRow(row, it, chosen)
    row.item, row.chosen = it, chosen
    local function Wash()
        if chosen then row.wash:SetColorTexture(0.6, 0.12, 0.05, 0.14)
        elseif it.mine then row.wash:SetColorTexture(0.6, 0.12, 0.05, 0.06)
        else row.wash:SetColorTexture(0, 0, 0, 0) end
    end
    row.fill = Wash
    Wash()
    if it.header then
        Ink(row.name, BLOOD, TITLE_FONT, 16)
        row.name:SetPoint("TOPLEFT", 44, -8)
        row.name:SetText(it.name)
        row.sub:SetText("")
        row.seal:Hide()
        row.rank:SetText("")
        row.face:SetShown(false)
        row.mark:Hide()
        row.open:Hide()
        row.c1:SetText("") row.c2:SetText("") row.wide:SetText("") row.right:SetText("")
        row.rule:SetColorTexture(0.42, 0.33, 0.22, 0.6)
        return
    end
    row.rule:SetColorTexture(0.27, 0.35, 0.55, 0.28)
    row.name:SetPoint("TOPLEFT", 74, -3)
    Ink(row.name, it.mine and BLOOD or (it.faded and FADED or INK), TITLE_FONT, 13)
    row.name:SetText(it.name or "")
    Ink(row.sub, FADED, TEXT_FONT, 11)
    row.sub:SetText(it.sub or "")
    local rc = it.rightColour or (it.faded and FADED or INK)
    row.right:SetTextColor(rc[1], rc[2], rc[3])
    row.right:SetText(it.right or "")
    -- The name runs to whichever column is there. Before a right-hand number it stops at that number's
    -- own width, not a fixed 70 kept for "12g 34s": a "+2" in the news cut "Seedkek One" to "Seedke..."
    -- with half the row empty (2026-11-05), and a long sum ran past the fixed stop into the name.
    local stop = (it.c1 and COL1 - 20) or (it.wide and COL_WIDE - 8)
        or (it.right and COL_RIGHT - 4 - row.right:GetStringWidth() - 12) or (PAGE_W - 24)
    row.name:SetWidth(stop - 74)
    row.sub:SetWidth(stop - 74)
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
    local margin = page:CreateTexture(nil, "BORDER")
    margin:SetColorTexture(0.63, 0.12, 0.08, 0.45)          -- the ledger's red margin line
    margin:SetWidth(1)
    margin:SetPoint("TOPLEFT", 38, -8)
    margin:SetPoint("BOTTOMLEFT", 38, 48)                  -- it stops above the buttons, which ran across it
    page.title = page:CreateFontString(nil, "ARTWORK")
    Ink(page.title, BLOOD, TITLE_FONT, 21)
    page.title:SetPoint("TOPLEFT", 48, -22)
    page.sub = page:CreateFontString(nil, "ARTWORK")
    Ink(page.sub, FADED, TEXT_FONT, 11)
    page.sub:SetPoint("TOPLEFT", 48, -52)
    -- An ink link: faded, or in blood and underlined when it is the one chosen. Refresh fills and places them.
    local function Link(click)
        local b = CreateFrame("Button", nil, page)
        b.text = b:CreateFontString(nil, "ARTWORK")
        Ink(b.text, FADED, TEXT_FONT, 11)
        b.text:SetPoint("LEFT")
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetColorTexture(BLOOD[1], BLOOD[2], BLOOD[3], 0.7)
        b.line:SetHeight(1)
        b.line:SetPoint("BOTTOMLEFT", 0, 0)
        b.line:SetPoint("BOTTOMRIGHT", 0, 0)
        b:SetSize(70, 16)
        function b:Set(text, on)
            self.text:SetText(text)
            Ink(self.text, on and BLOOD or FADED, TEXT_FONT, 11)
            self.line:SetShown(on and true or false)
            -- at least the 70 the leaderboard's links always had; a longer label ("Kill on sight") gets
            -- its own width, or it ran into the link after it
            self:SetWidth(math.max(70, math.ceil(TextWidth(self.text)) + 2))
        end
        b:SetScript("OnClick", function(self)
            click(self)
            offset = 0
            Refresh()
        end)
        return b
    end
    -- the page's own links (the leaderboard's this week and all time), laid out from its links()
    page.links = {}
    for i = 1, 4 do page.links[i] = Link(function(self) self.click() end) end
    -- Sort is the game's own dropdown, so it looks clickable (ink links read as text). It sits on the title
    -- row, right-aligned with the column headings, and Mine only is a checkbox at the foot of its menu.
    page.sort = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    page.sort:SetWidth(120)
    page.sort:SetPoint("RIGHT", page, "TOPRIGHT", -40, -33)
    if page.sort.SetupMenu then
        -- one radio per mode; the mode we pass is what the game hands back to both functions
        page.sort:SetupMenu(function(_, root)
            for _, s in ipairs(SORTS) do
                root:CreateRadio(s[2], function(mode) return (GK.db.sortMode or "default") == mode end,
                    function(mode)
                        GK.db.sortMode = mode
                        offset = 0
                        Refresh()
                    end, s[1])
            end
            root:CreateDivider()
            root:CreateCheckbox("Mine only", function() return GK.db.mineOnly == true end, function()
                GK.db.mineOnly = not (GK.db.mineOnly == true)
                offset = 0
                Refresh()
            end)
        end)
    end
    page.reset = page:CreateFontString(nil, "ARTWORK")    -- the links' tail, anchored after the last one shown
    Ink(page.reset, FADED, TEXT_FONT, 11)
    page.heads = {}
    for i = 1, 5 do
        local fs = page:CreateFontString(nil, "ARTWORK")
        Ink(fs, FADED, TEXT_FONT, 10)
        page.heads[i] = fs
    end
    local underline = page:CreateTexture(nil, "BORDER")
    underline:SetColorTexture(0.42, 0.33, 0.22, 0.6)
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT", 8, -(LIST_TOP - 4))
    underline:SetPoint("TOPRIGHT", -8, -(LIST_TOP - 4))
    page.rows = {}
    for i = 1, ROWS do page.rows[i] = BuildRow(page, i) end
    page.empty = page:CreateFontString(nil, "ARTWORK")
    Ink(page.empty, FADED, TEXT_FONT, 12)
    page.empty:SetPoint("TOPLEFT", 48, -(LIST_TOP + 12))
    page.empty:SetPoint("RIGHT", -24, 0)
    page.empty:SetJustifyH("LEFT")
    page.empty:SetSpacing(3)
    -- turning through a long list: the spellbook's page arrows, and the mouse wheel
    page.count = page:CreateFontString(nil, "ARTWORK")
    Ink(page.count, FADED, TEXT_FONT, 10)
    page.count:SetPoint("TOPRIGHT", -46, -(LIST_TOP + ROWS * ROW_H + 8))
    local function Arrow(kind, dir)
        local b = CreateFrame("Button", nil, page)
        b:SetSize(20, 20)
        b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Down")
        b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. kind .. "Page-Disabled")
        b:SetScript("OnClick", function()
            offset = math.max(0, offset + dir * ROWS)
            Refresh()
        end)
        return b
    end
    page.prev = Arrow("Prev", -1)
    page.prev:SetPoint("LEFT", page.count, "RIGHT", 2, 0)
    page.next = Arrow("Next", 1)
    page.next:SetPoint("LEFT", page.prev, "RIGHT", -2, 0)
    page:EnableMouseWheel(true)
    page:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 3)
        Refresh()
    end)
    local function MakeButton(text, w)
        local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetText(text)
        return b
    end
    page.post = MakeButton("Post a kill order", 140)
    page.post:SetPoint("BOTTOMLEFT", 24, 18)
    page.post:SetScript("OnClick", function() GK.PostOnTarget() end)
    page.letters = MakeButton("Letters", 96)
    page.letters:SetPoint("LEFT", page.post, "RIGHT", 6, 0)
    page.letters:SetScript("OnClick", function() GK.OpenLetters() end)
    page.settings = MakeButton(SETTINGS or "Settings", 76)
    page.settings:SetPoint("LEFT", page.letters, "RIGHT", 6, 0)
    page.settings:SetScript("OnClick", function() if GK.OpenOptions() then win:Hide() end end)
end

-- Where the card's parts sit, in units from the page's top left. The ledger's right page has these; the
-- Inspect tab (Inspect.lua) has a smaller page and lays the same card out tighter, at the same type
-- sizes rather than scaled down (scaled to fit, 12pt ink came out under 10).
local DETAIL = { w = PAGE_W, face = 92, faceX = 70, faceY = 86, bigY = 138, bigSize = 26, titleX = 128,
    titleY = 44, titleSize = 24, seal = 46, sealX = 26, sealY = 40, ruleY = 194, linesY = 206, padX = 24,
    valueX = 120, signY = 48, buttonY = 18 }

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
    -- below the portrait's number and its caption (on the ledger they end about 182 down)
    page.rule = page:CreateTexture(nil, "BORDER")
    page.rule:SetColorTexture(0.42, 0.33, 0.22, 0.6)
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
    page.rule:SetShown(d ~= nil)
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
    local L = page.layout
    page.face:SetShown(true)
    page.face:Set(d)
    -- The title on one line, beside the seal (or to the edge without one): a long name steps down in size
    -- until it fits rather than breaking in two ("Kriger-" over "Skaalvik" in the Inspect tab, 2026-11-05).
    local room = L.w - L.titleX - (d.seal and (L.sealX + L.seal + 4) or L.padX)
    page.title:SetWidth(room)
    page.title:SetText(d.title or "")
    local size = L.titleSize
    page.title:SetFont(TITLE_FONT, size, "")
    while size > 14 and TextWidth(page.title) > room do
        size = size - 1
        page.title:SetFont(TITLE_FONT, size, "")
    end
    page.name:SetText(d.name or "")
    page.info:SetText(d.info or "")
    page.big:SetText(d.big or "")
    page.caption:SetText(d.caption or "")
    page.seal:SetShown(d.seal ~= nil)
    if d.seal then page.seal:SetTexture(MEDIA .. d.seal) end
    page.blood:SetShown(d.blood == true)
    -- the lines: a short "Label: value" as two columns, anything else as a paragraph
    local y = L.linesY
    for i = 1, #page.labels do
        local l, v = page.labels[i], page.values[i]
        local line = d.lines[i]
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

--- The book's tone (see Tone), for a page of ours drawn elsewhere.
GK.Tone = function(tex, r, g, b) Tone(tex, r, g, b) end

-- ---------------------------------------------------------------------------
-- The whole book
-- ---------------------------------------------------------------------------
--- The frame look's frame, made the first time it is asked for: the book alone loads no sheet.
local function BuildFrame()
    if win.frame then return end
    local f = CreateFrame("Frame", nil, win, "SettingsFrameTemplate")
    f:SetAllPoints()
    f:SetFrameLevel(win.bookFrame:GetFrameLevel())   -- where the book is: over the tabs, under the pages
    f:EnableMouse(false)                             -- the window under it is what drags
    -- the template's flat grey backdrop gives way to the sheet, where Guildhall puts its wood panel
    if type(f.Bg) == "table" then f.Bg:Hide() end
    win.sheet = f:CreateTexture(nil, "BACKGROUND")
    win.sheet:SetPoint("TOPLEFT", 7, -18)
    win.sheet:SetPoint("BOTTOMRIGHT", -3, 3)
    Tone(win.sheet)
    if type(f.NineSlice) == "table" and f.NineSlice.Text then f.NineSlice.Text:SetText("Grudgekeeper") end
    -- the template's X calls HideUIPanel, which does nothing in combat from addon code
    if type(f.ClosePanelButton) == "table" then
        f.ClosePanelButton:SetScript("OnClick", function() win:Hide() end)
    end
    win.frame = f
end

--- Sizes a group of tabs to fit in `room`. The row is only so wide (a page, short of the top-right iron),
--- and every page another file adds makes it longer, so the labels step down a point at a time, with
--- their padding, until it fits (or reach TAB_FONT_MIN). Each group takes its own size: the right group
--- is short and keeps the full type while the left one steps down.
local function FitTabs(tabs, room)
    local size = TAB_FONT
    while true do
        local x = 0
        local pad = math.floor(TAB_PAD * size / TAB_FONT + 0.5)
        for _, t in ipairs(tabs) do
            t.label:SetFont(TITLE_FONT, size, "")
            t.w = math.ceil(t.label:GetStringWidth() or 60) + pad
            t.dx = x
            t:SetWidth(t.w)
            x = x + t.w + 4
        end
        if size <= TAB_FONT_MIN or x - 4 <= room then return end
        size = size - 1
    end
end

--- Places a group of tabs along the book's top edge, as far in as they fit: from `want` if there is room,
--- else pushed left, but never left of `least` nor past `stop`. They come out from under the cover's top
--- edge. The labels' real widths decide (in the preview's stand-in font, News ran under the iron).
local function PlaceTabs(tabs, want, least, stop, cover)
    if #tabs == 0 then return end
    FitTabs(tabs, stop - least)
    local last = tabs[#tabs]
    local x = math.max(least, math.min(want, stop - last.dx - last.w))
    for _, t in ipairs(tabs) do
        t:ClearAllPoints()
        t:SetPoint("BOTTOMLEFT", win, "TOPLEFT", x + t.dx, -(cover + 8))
    end
end

local function Layout()
    local folded, framed = Folded(), GK.db.ledgerLook == "frame"
    local b
    if framed then b = folded and FRAME_FOLDED or FRAME else b = folded and SINGLE or OPEN end
    win:SetSize(b.W, b.H)
    win.book:SetShown(not framed and not folded)
    win.single:SetShown(not framed and folded)
    if framed then
        BuildFrame()
        win.sheet:SetTexture(MEDIA .. (folded and "sheet_single" or "sheet_wide"))
    end
    if win.frame then win.frame:SetShown(framed) end
    win.close:SetShown(not framed)                   -- framed, Blizzard's own X closes it
    win.list:ClearAllPoints()
    win.list:SetPoint("TOPLEFT", b.x, -b.y)
    win.detail:ClearAllPoints()
    win.detail:SetPoint("TOPLEFT", folded and b.x or b.x2, -b.y)
    -- Two groups in the open book: the enemy's pages over the left page, the friendly ones (side = "right")
    -- over the right page, from just inside its left edge to the iron. Folded there is one page and one
    -- row, too short for all of them: only the active page's group shows, with a last tab that switches to
    -- the other group.
    local left, right = {}, {}
    local current = GK.LedgerPages[tab]
    local friends = current ~= nil and current.side == "right"
    for _, t in ipairs(win.tabs) do
        if folded then
            t:SetShown((t.side == "right") == friends)
            if t:IsShown() then left[#left + 1] = t end
        else
            t:Show()
            local into = t.side == "right" and right or left
            into[#into + 1] = t
        end
    end
    win.swap:SetShown(folded)
    if folded then
        win.swap.label:SetText(friends and "Enemies" or "Friends")
        left[#left + 1] = win.swap
    end
    PlaceTabs(left, b.x + 12, 8, b.stop, b.cover)
    if b.stopRight then PlaceTabs(right, b.x2 + 12, b.x2 + 4, b.stopRight, b.cover) end
    -- the close button fills its socket; the cross sits inside it, clear of the rim
    if b.close then
        local hole = b.close[3]
        win.close:SetSize(hole, hole)
        win.close.cross:SetSize(hole * 0.7, hole * 0.7)
        win.close.glow:SetSize(hole * 1.26, hole * 1.26)
        win.close:ClearAllPoints()
        win.close:SetPoint("CENTER", win, "TOPRIGHT", -b.close[1], -b.close[2])
    end
    win.fold.label:SetText(folded and "\194\187" or "\194\171")    -- » opens the book, « folds it
end

--- Keep the left edge where it is when the book changes width: anchor it by its top left first.
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

local function SelectTab(i)
    tab, offset, turned = i, 0, false
    if Folded() then Layout() end                  -- the row shows the group of the page
    for j, t in ipairs(win.tabs) do
        local on = j == i
        t:SetHeight(on and TAB_H_ON or TAB_H)
        for _, piece in ipairs(t.art) do
            if on then Tone(piece, 0.9, 0.38, 0.28) else Tone(piece, 0.78, 0.62, 0.5) end
        end
        t.label:SetTextColor(on and 1 or 0.95, on and 0.9 or 0.86, on and 0.72 or 0.68)
    end
    Refresh()
end

local function Build()
    win = CreateFrame("Frame", "GrudgekeeperFrame", UIParent)
    win:SetSize(OPEN.W, OPEN.H)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetPoint("CENTER", 0, 30)
    -- In levels above the window: the tabs and the bookmark (+1), BEHIND the book (+2), so they come
    -- out of its pages; what is written on the pages (+3); the close button (+10). Each frame takes its
    -- level before anything is built in it, so what it holds starts above it.
    local level = win:GetFrameLevel()
    local book = CreateFrame("Frame", nil, win)
    book:SetAllPoints()
    book:SetFrameLevel(level + 2)
    win.bookFrame = book
    -- one picture per view, the window always its size (Layout)
    win.book = book:CreateTexture(nil, "BACKGROUND")
    win.book:SetTexture(MEDIA .. "ledger_book")
    win.book:SetAllPoints()
    Tone(win.book)
    win.single = book:CreateTexture(nil, "BACKGROUND")
    win.single:SetTexture(MEDIA .. "ledger_single")
    win.single:SetAllPoints()
    Tone(win.single)
    win.list = CreateFrame("Frame", nil, win)
    win.list:SetFrameLevel(level + 3)
    win.list:SetSize(PAGE_W, PAGE_H)
    BuildList(win.list)
    win.detail = CreateFrame("Frame", nil, win)
    win.detail:SetFrameLevel(level + 3)
    win.detail:SetSize(PAGE_W, PAGE_H)
    BuildDetail(win.detail)
    -- Layout places the tabs, each group over its page as far in as it fits
    win.tabs = {}
    local x = 0
    for i, def in ipairs(GK.LedgerPages) do
        local t = CreateFrame("Button", nil, win)
        t:SetFrameLevel(level + 1)
        t.label = t:CreateFontString(nil, "OVERLAY")
        t.label:SetFont(TITLE_FONT, TAB_FONT, "")
        t.label:SetShadowOffset(1, -1)
        t.label:SetText(def.name)
        t.label:SetPoint("CENTER", 0, 4)
        local w = math.ceil(t.label:GetStringWidth() or 60) + TAB_PAD
        t:SetWidth(w)
        t:SetHeight(TAB_H)
        t.art = TabArt(t, TAB_H_ON)
        t.side = def.side
        t.dx, t.w = x, w
        t:SetScript("OnClick", function() SelectTab(i) end)
        win.tabs[i] = t
        x = x + w + 4
    end
    -- folded: the last tab of the row, which switches to the other group of pages
    local swap = CreateFrame("Button", nil, win)
    swap:SetFrameLevel(level + 1)
    swap.label = swap:CreateFontString(nil, "OVERLAY")
    swap.label:SetFont(TITLE_FONT, TAB_FONT, "")
    swap.label:SetShadowOffset(1, -1)
    swap.label:SetTextColor(0.95, 0.86, 0.68)
    swap.label:SetText("Friends")
    swap.label:SetPoint("CENTER", 0, 4)
    swap:SetHeight(TAB_H)
    swap.art = TabArt(swap, TAB_H_ON)
    for _, piece in ipairs(swap.art) do Tone(piece, 0.78, 0.62, 0.5) end
    swap.dx, swap.w = 0, 60
    swap:SetScript("OnClick", function()
        local toRight = not (GK.LedgerPages[tab] and GK.LedgerPages[tab].side == "right")
        for i, def in ipairs(GK.LedgerPages) do
            if (def.side == "right") == toRight then return SelectTab(i) end
        end
    end)
    swap:Hide()
    win.swap = swap
    -- the bookmark that folds the book: a tab like the ones on top, standing 20 out of the right-hand
    -- edge (both covers end ~4 inside the window's edge, so 10 of its 30 are behind the cover)
    local fold = CreateFrame("Button", nil, win)
    fold:SetFrameLevel(level + 1)
    fold:SetSize(30, 76)
    fold:SetPoint("LEFT", win, "RIGHT", -14, 60)
    for _, piece in ipairs(TabArt(fold, 30, true)) do Tone(piece, 0.78, 0.62, 0.5) end
    fold.label = fold:CreateFontString(nil, "OVERLAY")
    fold.label:SetFont(TEXT_FONT, 18, "")
    fold.label:SetShadowOffset(1, -1)
    fold.label:SetTextColor(1, 0.9, 0.72)
    fold.label:SetPoint("CENTER", 5, 1)                -- the middle of the part that shows
    fold:SetScript("OnClick", function() Fold(not Folded()) end)
    fold:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Folded() and "Open the book" or "Fold to one page", 1, 1, 1)
        GameTooltip:Show()
    end)
    fold:SetScript("OnLeave", function(self)
        self.label:SetTextColor(1, 0.9, 0.72)
        GameTooltip:Hide()
    end)
    win.fold = fold
    -- the close button, in the top-right iron's socket (Layout sizes and places it per view)
    local close = GK.MakeCloseButton(win, OPEN.close[3], function() win:Hide() end)
    close:SetFrameLevel(level + 10)
    win.close = close
    win:Hide()
    if LIB.RegisterWindow then LIB.RegisterWindow(win, GK.db, "window") end
    win:HookScript("OnShow", function() Refresh() end)
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
    if def.sortable then items = GK.SortItems(items, def) end
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
            if last then b:SetPoint("LEFT", last, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", 48, -50) end
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
        list.sub:SetPoint("TOPLEFT", 48, -52)
    end
    list.sub:SetText(def.sub and def.sub(items) or "")
    local sortable = def.sortable == true
    list.sort:SetShown(sortable)
    if sortable then
        if list.sort.GenerateMenu then list.sort:GenerateMenu() end
        -- the chosen mode's own name, led by what it is for ("Sort: Newest"); ", mine" while Mine only is on
        if list.sort.OverrideText then
            list.sort:OverrideText("Sort: " .. SortWord(GK.db.sortMode) .. (GK.db.mineOnly == true and ", mine" or ""))
        end
    end
    for i, fs in ipairs(list.heads) do
        local h = def.headings[i]
        fs:ClearAllPoints()
        if h then
            fs:SetText(h[1]:upper())
            if h[3] == "RIGHT" then fs:SetPoint("BOTTOMRIGHT", list, "TOPLEFT", h[2] - 4, -(LIST_TOP - 6))
            elseif h[3] == "CENTER" then fs:SetPoint("BOTTOM", list, "TOPLEFT", h[2] - 4, -(LIST_TOP - 6))
            else fs:SetPoint("BOTTOMLEFT", list, "TOPLEFT", h[2], -(LIST_TOP - 6)) end
        else
            fs:SetText("")
        end
    end
    offset = math.max(0, math.min(offset, math.max(0, #items - ROWS)))
    for i, row in ipairs(list.rows) do
        local it = items[i + offset]
        if it then
            row:Show()
            FillRow(row, it, chosen ~= nil and it.key == chosen.key)
        else
            row:Hide()
        end
    end
    list.empty:SetText(#items == 0 and empty or "")
    local more = #items > ROWS
    list.count:SetShown(more)
    list.prev:SetShown(more)
    list.next:SetShown(more)
    if more then
        list.count:SetText(("%d-%d of %d"):format(offset + 1, math.min(offset + ROWS, #items), #items))
        list.prev:SetEnabled(offset > 0)
        list.next:SetEnabled(offset + ROWS < #items)
    end
    list.letters:SetText(("Letters (%d)"):format((GK.Unread())))
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

function GK.ToggleWindow()
    if win and win:IsShown() then win:Hide() else GK.OpenWindow() end
end

--- The book, or the plain sheet in Blizzard's frame - while we compare them (/grudge debug).
function GK.SwitchLedgerLook()
    GK.db.ledgerLook = GK.db.ledgerLook ~= "frame" and "frame" or nil
    if not win then Build() end
    Layout()
    GK.OpenWindow()
end

-- Once per burst of changes (GK.Changed gathers them); Refresh returns at once while the book is shut.
LIB.Listen("GRUDGEKEEPER_CHANGED", function() Refresh() end)
