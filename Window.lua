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
local LIST_TOP = 96                                  -- the first row, down from the page's top
-- the right-hand column stops short of the row's end: folded, room for the » that says a click turns
-- the page (they ran into each other in the preview)
local COL1, COL2, COL_WIDE, COL_RIGHT = 232, 266, 196, PAGE_W - 36
local TAB_GAP, GROUP_GAP = 3, 16                     -- between two tabs; and before the friendly pages, or Friends

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
-- What each page lists. An item: { key, name, sub, rank, seal, face = { rf, sx, c }, c1, c2, wide,
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
local function Short(l, c, r)
    local s = GK.Describe(l, c, r):gsub("^Level ", "")
    return s ~= "" and s or nil
end

local function OrderItems()
    local items, me = {}, LIB.Me()
    for _, o in ipairs(GK.AllOrders()) do
        local pot, backers = GK.Pot(o)
        local it = { key = "o:" .. o.key, name = GK.Show(o.n), face = { c = o.c }, select = PosterSpec(o.n, o, o),
            desc = Short(o.l, o.c, o.r), ts = o.t,
            own = GK.char.accepted[o.key] or (me and (o.by == me or o.doneBy == me or (o.pot and o.pot[me]))) or nil }
        if o.state == "o" then
            it.bounty = pot
            it.right = pot > 0 and GK.Coins(pot) or "honour"
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
    return items, "No kill orders. Post one with Post a kill order, at the top of this page - or right-click "
        .. "an enemy player and pick it there."
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
            items[#items + 1] = { key = "w:" .. e.key, name = GK.Show(e.key), desc = Short(e.w.l, e.w.c, e.w.r),
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
            desc = Short(e.f.l, e.f.c, e.f.r), sub = "last met " .. GK.Ago(e.f.last),
            c1 = tostring(e.f.k or 0), c2 = tostring(e.f.d or 0), select = PosterSpec(e.key, e.f),
            you = e.f.k or 0, they = e.f.d or 0, ts = e.f.last, own = true }
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
--- click } }, linksTail = fn -> text, sortable, side, add, default = fn(items) -> the row chosen when none is }.
--- headings: the column headings over the table, { text, x, justify, sort, tip }: a heading with a sort
--- (an item field: "name", or a number, the biggest first) sorts the page when clicked, and tip finishes
--- "Sort by ..." in its tooltip. sortable: the headings sort and Only mine shows. links: ink links under
--- the title. add: the page's own action, top right - { text, kind } opens the who-picker (Pick.lua) for
--- that kind. side: "right" puts the tab over the right page in the open book (the friendly lists);
--- anything else is over the left page. Folded, all the tabs share one row. A page with links and a sub
--- line has the sub text after the links, on their line.
GK.LedgerPages = {
    { name = "Kill orders", items = OrderItems,
      headings = { { "Name", 48, nil, "name", "name, A to Z" }, { "Bounty", COL_RIGHT, "RIGHT", "bounty", "bounty" } },
      sortable = true, add = { text = "Post a kill order", kind = "order" },
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
      headings = { { "Name", 48, nil, "name", "name, A to Z" }, { "You", COL1, "CENTER", "you", "your kills" },
          { "They", COL2, "CENTER", "they", "their kills" } },
      sub = function() return "Everyone you have a history with" end,
      default = function() return { key = "me", select = { kind = "record", key = LIB.Me() } } end },
    { name = "News", items = NewsItems, sortable = true,
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

--- A page's rows in the order its clicked heading asks for, and only yours with GK.db.mineOnly. Sorting or
--- filtering drops the header rows and sorts the rest together; the page's own order, without Only mine,
--- is left alone. Names go A to Z, numbers the biggest first; ties go A to Z. Returns a new list, or the
--- same one untouched.
function GK.SortItems(items, page)
    local key, mineOnly = GK.SortKey(page), GK.db.mineOnly == true
    if not (page and page.sortable) or (not key and not mineOnly) then return items end
    local out, at = {}, {}
    for _, it in ipairs(items) do
        if not it.header and (not mineOnly or it.own or it.mine) then
            out[#out + 1] = it
            at[it] = #out
        end
    end
    if not key then return out end
    local function SortName(it) return (it.name or ""):lower() end
    table.sort(out, function(a, b)
        if key ~= "name" then
            local x, y = tonumber(a[key]) or 0, tonumber(b[key]) or 0
            if x ~= y then return x > y end
        end
        local na, nb = SortName(a), SortName(b)
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
    row.face.tex:SetPoint("CENTER", row, "LEFT", 55, 0)
    row.name = row:CreateFontString(nil, "ARTWORK")
    -- the name in the game's plain type: Morpheus' small capitals at this size were "litt vanskelig å
    -- lese" in a list (the owner, 2026-11-06); the titles over the lists and on the card keep it
    Ink(row.name, INK, TEXT_FONT, 13)
    row.name:SetPoint("TOPLEFT", 74, -4)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    -- what they are, in small type after the name ("35 Orc Rogue"), when it fits beside it
    row.desc = row:CreateFontString(nil, "ARTWORK")
    Ink(row.desc, FADED, TEXT_FONT, 10)
    row.desc:SetJustifyH("LEFT")
    row.desc:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "ARTWORK")
    Ink(row.sub, FADED, TEXT_FONT, 11)
    row.sub:SetPoint("TOPLEFT", 74, -22)
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
        if self.item and not self.item.header and not self.chosen then Wash(self.wash, 0.07) end
    end)
    row:SetScript("OnLeave", function(self) if self.fill then self.fill() end end)
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
        return
    end
    row.rule:Hide()
    row.name:SetPoint("TOPLEFT", 74, -4)
    Ink(row.name, it.mine and BLOOD or (it.faded and FADED or INK), TEXT_FONT, 13)
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
    -- the description after the name's own width, only when all of it fits before the stop: a cut
    -- "35 Orc Ro..." says less than none, and the name keeps its room
    local nameW = math.ceil(TextWidth(row.name))
    row.desc:SetText(it.desc or "")
    local descW = math.ceil(TextWidth(row.desc))
    local fits = it.desc ~= nil and nameW + 6 + descW <= stop - 74
    row.desc:SetShown(fits)
    if fits then
        row.desc:ClearAllPoints()
        row.desc:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 74 + nameW + 6, -18)
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
    page.rows = {}
    for i = 1, ROWS do page.rows[i] = BuildRow(page, i) end
    page.empty = page:CreateFontString(nil, "ARTWORK")
    Ink(page.empty, FADED, TEXT_FONT, 12)
    page.empty:SetPoint("TOPLEFT", 12, -(LIST_TOP + 12))
    page.empty:SetPoint("RIGHT", -24, 0)
    page.empty:SetJustifyH("LEFT")
    page.empty:SetSpacing(3)
    -- turning through a long list: the spellbook's page arrows at the foot, and the mouse wheel
    page.count = page:CreateFontString(nil, "ARTWORK")
    Ink(page.count, FADED, TEXT_FONT, 10)
    page.count:SetPoint("BOTTOMRIGHT", -46, 15)
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
    end, "Your kills and deaths, and the guild's kill orders - read again.")
    page.letters:SetPoint("BOTTOMLEFT", 8, 10)
    page.letters:Set("Letters")
    page.settings = Foot(function() if GK.OpenOptions() then win:Hide() end end,
        function() return SETTINGS or "Settings" end, "Grudgekeeper's settings: letters, warnings, sharing.")
    page.settings:SetPoint("LEFT", page.letters, "RIGHT", 6, 0)
    page.settings:Set(SETTINGS or "Settings")
end

-- Where the card's parts sit, in units from the page's top left. The ledger's right page has these; the
-- Inspect tab (Inspect.lua) has a smaller page and lays the same card out tighter, at the same type
-- sizes rather than scaled down (scaled to fit, 12pt ink came out under 10). statsY: the card's stats
-- (Profile.lua), side by side statsW apart, under the face where the one big number goes on a page
-- without them. h: the page's height, for the buttons that follow the lines (else they sit at the foot).
local DETAIL = { w = PAGE_W, h = PAGE_H, face = 92, faceX = 70, faceY = 86, bigY = 138, bigSize = 26,
    titleX = 128, titleY = 44, titleSize = 24, seal = 46, sealX = 26, sealY = 40, statsY = 146, statsW = 110,
    ruleY = 194, linesY = 206, padX = 24, valueX = 120, signY = 24, buttonY = 18 }

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
    -- the stats: a small capital label over each number, as previewed (2026-11-06)
    page.stats = {}
    for i = 1, L.statsY and 3 or 0 do
        local s = {}
        s.label = page:CreateFontString(nil, "ARTWORK")
        Ink(s.label, FADED, TEXT_FONT, 10)
        s.label:SetPoint("TOPLEFT", L.padX + (i - 1) * L.statsW, -L.statsY)
        s.value = page:CreateFontString(nil, "ARTWORK")
        Ink(s.value, INK, TEXT_FONT, 18)
        s.value:SetPoint("TOPLEFT", s.label, "BOTTOMLEFT", 0, -3)
        page.stats[i] = s
    end
    -- A guildie's record as a small table where the stats go: all time and this week down the side, the
    -- points, kills, deaths and place on the board across - so the place reads beside what it counts, in
    -- the card rather than squeezed into the line under the name ("bak det inn i hovedområdet", the owner,
    -- 2026-11-06). Columns: the row's name; Points, Kills and Deaths centred; Place to the right edge.
    page.grid = { heads = {}, rows = {} }
    if L.statsY then
        local GX = { L.padX, 152, 210, 268, L.w - L.padX }
        local function Cell(i, y, colour, size)
            local fs = page:CreateFontString(nil, "ARTWORK")
            Ink(fs, colour, TEXT_FONT, size)
            if i == 1 then fs:SetPoint("TOPLEFT", page, "TOPLEFT", GX[1], -y)
            elseif i == 5 then fs:SetPoint("TOPRIGHT", page, "TOPLEFT", GX[5], -y)
            else fs:SetPoint("TOP", page, "TOPLEFT", GX[i], -y) end
            return fs
        end
        for i = 2, 5 do page.grid.heads[i] = Cell(i, L.statsY, FADED, 10) end
        for r = 1, 2 do
            local y = L.statsY + 16 + (r - 1) * 20
            local row = { Cell(1, y + 3, FADED, 10) }
            for i = 2, 5 do row[i] = Cell(i, y, INK, 14) end
            page.grid.rows[r] = row
        end
    end
    -- below the portrait's number and its caption (on the ledger they end about 182 down), or the stats
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
        for _, s in ipairs(page.stats) do s.label:SetText("") s.value:SetText("") end
        for i = 2, 5 do if page.grid.heads[i] then page.grid.heads[i]:SetText("") end end
        for _, row in ipairs(page.grid.rows) do for i = 1, 5 do row[i]:SetText("") end end
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
    Ink(page.title, BLOOD, TITLE_FONT, size)
    while size > 14 and TextWidth(page.title) > room do
        size = size - 1
        Ink(page.title, BLOOD, TITLE_FONT, size)
    end
    page.name:SetText(d.name or "")
    -- Where the page has room: a record's table (d.grid), else the stats in a row (d.stats), and then
    -- not the big number they stand in for. Under the name, with the table, what they are (d.gridInfo)
    -- instead of their place, which the table says.
    local grid = page.grid.rows[1] and d.grid or nil
    local stats = not grid and #page.stats > 0 and d.stats or nil
    page.info:SetText(grid and d.gridInfo or d.info or "")
    page.big:SetText((stats or grid) and "" or (d.big or ""))
    page.caption:SetText((stats or grid) and "" or (d.caption or ""))
    for i, s in ipairs(page.stats) do
        local v = stats and stats[i]
        s.label:SetText(v and v[1]:upper() or "")
        s.value:SetText(v and v[2] or "")
    end
    for i = 2, 5 do
        if page.grid.heads[i] then page.grid.heads[i]:SetText(grid and grid.cols[i - 1] and grid.cols[i - 1]:upper() or "") end
    end
    for r, row in ipairs(page.grid.rows) do
        local data = grid and grid.rows[r]
        row[1]:SetText(data and data[1]:upper() or "")
        for i = 2, 5 do row[i]:SetText(data and data[i] or "") end
    end
    page.seal:SetShown(d.seal ~= nil)
    if d.seal then page.seal:SetTexture(MEDIA .. d.seal) end
    page.blood:SetShown(d.blood == true)
    -- the rule and the lines a little lower under the table, which is one row taller than the stats
    local drop = grid and 14 or 0
    page.rule:ClearAllPoints()
    page.rule:SetPoint("TOPLEFT", L.padX, -(L.ruleY + drop))
    page.rule:SetPoint("TOPRIGHT", -L.padX, -(L.ruleY + drop))
    -- the lines: a short "Label: value" as two columns, anything else as a paragraph; with the stats or
    -- the table shown, a line they already say gives way to its shorter form, or goes (d.withStats)
    local lines, swap = {}, (stats or grid) and d.withStats or {}
    for _, line in ipairs(d.lines) do
        local alt = swap[line]
        if alt ~= false then lines[#lines + 1] = alt or line end
    end
    local y = L.linesY + drop
    for i = 1, #page.labels do
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
    local width, chosen = 0, nil
    for i, t in ipairs(row) do
        PanelTemplates_TabResize(t, 0)
        t.gap = (i > 1 and (t == win.swap or t.side ~= row[i - 1].side)) and GROUP_GAP or TAB_GAP
        width = width + t:GetWidth() + (i > 1 and t.gap or 0)
        if t.selected then chosen = t end
    end
    local room = (folded and FOLDED.W or OPEN.W) - 24
    if width > room and #row > 1 then
        local gaps = 0
        for i, t in ipairs(row) do if i > 1 then gaps = gaps + t.gap end end
        local share = math.floor((room - gaps - (chosen and chosen:GetWidth() or 0)) / (#row - (chosen and 1 or 0)))
        for _, t in ipairs(row) do
            if t ~= chosen then PanelTemplates_TabResize(t, 0, share) end
        end
    end
    for i, t in ipairs(row) do
        t:ClearAllPoints()
        if i == 1 then t:SetPoint("TOPLEFT", win, "BOTTOMLEFT", 12, 2)
        else t:SetPoint("TOPLEFT", row[i - 1], "TOPRIGHT", t.gap, 0) end
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

local function SelectTab(i)
    tab, offset, turned = i, 0, false
    -- the game's chosen look: the tab raised and joined to the frame, and not clickable again
    for j, t in ipairs(win.tabs) do
        t.selected = j == i
        if t.selected then PanelTemplates_SelectTab(t) else PanelTemplates_DeselectTab(t) end
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
local function Tab(text, onClick)
    local t = CreateFrame("Button", nil, win, "PanelTabButtonTemplate")
    t:SetText(text)
    t:SetScript("OnShow", nil)
    t:SetScript("OnEvent", nil)
    t:SetScript("OnClick", function(self)
        GK.Sound("IG_CHARACTER_INFO_TAB")
        onClick(self)
    end)
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
        local t = Tab(def.name, function() SelectTab(i) end)
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
    -- the template's X: its click is our own, as the template's HideUIPanel does nothing in combat
    local close = type(win.ClosePanelButton) == "table" and win.ClosePanelButton
        or CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetScript("OnClick", function() win:Hide() end)
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
    list.sub:SetText(def.sub and def.sub(items) or "")
    list.add:SetShown(def.add ~= nil)
    if def.add then list.add:Set(def.add) end
    local sortKey = GK.SortKey(def)
    for i, b in ipairs(list.heads) do
        local h = def.headings[i]
        b:ClearAllPoints()
        b:SetShown(h ~= nil)
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
    local unread = GK.Unread()
    list.letters:Set(unread > 0 and ("Letters \194\183 %d new"):format(unread) or "Letters")      -- "Letters · 2 new"
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

-- Once per burst of changes (GK.Changed gathers them); Refresh returns at once while the book is shut.
LIB.Listen("GRUDGEKEEPER_CHANGED", function() Refresh() end)
