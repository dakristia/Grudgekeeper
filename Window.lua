-- Grudgekeeper - the window (/grudge, the minimap button): four pages on one sheet of parchment.
--   Kill orders   every order the guild has out, with its pot, and the ones that closed lately
--   Leaderboard   the guild's points this week or all time, with titles, and who the guild most wants dead
--   Grudges       your nemesis, every enemy you have a history with, and your own log
--   News          what the guild has been up to: kills, deaths, orders posted, backed and fulfilled
-- Nothing here ever opens by itself: this is where you come to look.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local W, H, ROLL_H = 500, 532, 38
local ROW_H, ROWS = 46, 7
local MEDIA = "Interface\\AddOns\\Grudgekeeper\\Media\\"
local TITLE_FONT = "Fonts\\MORPHEUS.ttf"
local TEXT_FONT = "Fonts\\FRIZQT__.TTF"
local INK = { 0.22, 0.13, 0.05 }
local FADED = { 0.42, 0.33, 0.22 }
local BLOOD = { 0.47, 0.06, 0.04 }
local SKULL = "Interface\\Worldmap\\GlowSkull_64Red"
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local MAX_FOES_SHOWN = 40

local win
local tab = 1
local weekly = true          -- the leaderboard shows this week until you ask for all time

local function Ink(fs, colour, font, size)
    fs:SetFont(font, size, "")
    fs:SetTextColor(colour[1], colour[2], colour[3])
    fs:SetShadowOffset(0, 0)
end

local function ClassIcon(tex, class)
    local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if coords then
        tex:SetTexture(CLASS_ICONS)
        tex:SetTexCoord(unpack(coords))
    else
        tex:SetTexture(SKULL)
        tex:SetTexCoord(0, 1, 0, 1)
    end
end

local function Plural(n, word)
    return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

local function PostOn(t) return function() GK.OpenPost(t) end end
-- Clicking a row opens the card on whoever it is about (Profile.lua): an enemy's wanted poster, a
-- guildie's record. x: any record that carries their guid, class, race and level.
local function PosterOf(key, x)
    return function() GK.ShowPoster({ key = key, guid = x and x.guid, c = x and x.c, r = x and x.r, l = x and x.l }) end
end
local function RecordOf(key) return function() GK.ShowRecord(key) end end

-- ---------------------------------------------------------------------------
-- What each page lists. An item: { class, skull, text1, right1, text2, faded, header, mine,
-- button = { text, fn }, button2 = { text, fn }, open = fn (a click on the row) }
-- ---------------------------------------------------------------------------
local STATE_WORD = { d = "FULFILLED", p = "PAID", x = "WITHDRAWN", e = "EXPIRED" }

local function OrderItems()
    local me, items = LIB.Me(), {}
    -- What I owe, worked out once for the page (it was asked again for every closed order).
    local owed = {}
    for _, e in ipairs(GK.Owed()) do owed[e.o] = (owed[e.o] or 0) + e.share end
    for _, o in ipairs(GK.AllOrders()) do
        local it = { class = o.c, text1 = GK.Show(o.n), open = PosterOf(o.n, o) }
        local pot, backers = GK.Pot(o)
        if o.state == "o" then
            it.right1 = pot > 0 and GK.Coins(pot) or "for honour"
            local hunting = 0
            if o.hunters then
                for _ in pairs(o.hunters) do hunting = hunting + 1 end
            end
            local bits = { GK.Describe(o.l, o.c, o.r), "by " .. GK.Show(o.by) }
            if backers > 0 then bits[#bits + 1] = Plural(backers, "backer") end
            if hunting > 0 then bits[#bits + 1] = hunting .. " hunting" end
            if o.seen then bits[#bits + 1] = ("seen in %s %s"):format(o.seen.z or "?", GK.Ago(o.seen.t)) end
            it.text2 = table.concat(bits, "  -  ")
            if o.by == me then
                it.button = { "Withdraw", function() GK.Withdraw(o) end }
            else
                local mine = GK.char.accepted[o.key]
                it.button = { mine and "Drop it" or "Take it", function() GK.Accept(o, not mine) end }
                it.button2 = { o.pot and o.pot[me] and "Your share" or "Add to pot",
                    PostOn({ key = o.n, guid = o.guid, c = o.c, r = o.r, l = o.l }) }
            end
        else
            it.faded = true
            it.right1 = STATE_WORD[o.state] or ""
            local bits = {}
            if o.doneBy then bits[#bits + 1] = "by " .. GK.Show(o.doneBy) end
            bits[#bits + 1] = GK.Ago(o.paidAt or o.doneAt)
            if pot > 0 and o.state ~= "x" and o.state ~= "e" then bits[#bits + 1] = GK.MoneyText(pot) end
            if owed[o] then
                bits[#bits + 1] = "you owe " .. GK.MoneyText(owed[o])
                it.button = { "Paid", function() GK.PayShare(o) end }
            end
            it.text2 = table.concat(bits, "  -  ")
        end
        items[#items + 1] = it
    end
    return items, "No kill orders. Target an enemy player and click Post a kill order - or put a price on someone "
        .. "who killed you, from the Grudges page."
end

local function BoardItems()
    local items = {}
    for i, r in ipairs(GK.Board(weekly)) do
        items[#items + 1] = { class = r.c, text1 = ("#%d  %s"):format(i, GK.Show(r.who)),
            right1 = Plural(r.p, "point"),
            text2 = ("%s  -  %s  -  %s"):format(GK.Title(r.total), Plural(r.k, "kill"), Plural(r.d, "death")),
            mine = r.me, open = RecordOf(r.who) }
    end
    local wanted = GK.MostWanted()
    if #wanted > 0 then
        items[#items + 1] = { header = true, text1 = "Most wanted" }
        for i = 1, math.min(#wanted, 10) do
            local e = wanted[i]
            local victims = {}
            for who, n in pairs(e.w.victims) do victims[#victims + 1] = { who = who, n = n } end
            table.sort(victims, function(a, b) return a.n > b.n end)
            local names = {}
            for j = 1, math.min(3, #victims) do names[j] = ("%s %d"):format(GK.Show(victims[j].who), victims[j].n) end
            local it = { class = e.w.c, text1 = GK.Show(e.key),
                right1 = ("killed us %s"):format(Plural(e.total, "time")),
                text2 = GK.Describe(e.w.l, e.w.c, e.w.r) .. "  -  " .. table.concat(names, ", "),
                open = PosterOf(e.key, e.w) }
            if not GK.OrderOn(e.key) then
                it.button = { "Post order", PostOn({ key = e.key, c = e.w.c, r = e.w.r, l = e.w.l }) }
            end
            items[#items + 1] = it
        end
    end
    return items, ""
end

local function GrudgeItems()
    local items, c = {}, GK.char
    local key, f = GK.Nemesis()
    if key then
        items[#items + 1] = { skull = true, text1 = "Your nemesis: " .. GK.Show(key),
            right1 = ("%d - %d"):format(f.k or 0, f.d or 0),
            text2 = ("Has killed you %s; you got them %s."):format(Plural(f.d, "time"), Plural(f.k or 0, "time")),
            open = PosterOf(key, f) }
    end
    if (c.bestStreak or 0) > 0 then
        items[#items + 1] = { skull = true, text1 = ("%s - %s"):format(GK.Title(c.points), Plural(c.points, "point")),
            right1 = ("streak %d"):format(c.streak or 0),
            text2 = ("Best streak %d kills without dying.  %s, %s all time."):format(c.bestStreak,
                Plural(c.kills, "kill"), Plural(c.deaths, "death")),
            open = RecordOf(LIB.Me()) }
    end
    -- Everyone you have a history with, the longest history first.
    local foes = {}
    for k, v in pairs(c.foes) do
        if (v.k or 0) + (v.d or 0) > 0 then foes[#foes + 1] = { key = k, f = v } end
    end
    table.sort(foes, function(a, b) return (a.f.k + a.f.d) > (b.f.k + b.f.d) end)
    if #foes > 0 then items[#items + 1] = { header = true, text1 = "Your grudges" } end
    for i = 1, math.min(#foes, MAX_FOES_SHOWN) do
        local e = foes[i]
        local it = { class = e.f.c, text1 = GK.Show(e.key),
            right1 = ("you %d - they %d"):format(e.f.k or 0, e.f.d or 0),
            text2 = GK.Describe(e.f.l, e.f.c, e.f.r) .. "  -  last met " .. GK.Ago(e.f.last),
            open = PosterOf(e.key, e.f) }
        if (e.f.d or 0) > 0 and not GK.OrderOn(e.key) then
            it.button = { "Post order", PostOn({ key = e.key, c = e.f.c, r = e.f.r, l = e.f.l }) }
        end
        items[#items + 1] = it
    end
    if #c.log > 0 then items[#items + 1] = { header = true, text1 = "Lately" } end
    for _, e in ipairs(c.log) do
        local where = table.concat({ GK.Describe(e.l, e.c, e.r), e.z or "", GK.Ago(e.t) }, "  -  ")
        if e.k == "K" then
            local extra = (e.rv and "revenge" or "") .. (e.av and ((e.rv and ", " or "") .. "for " .. GK.Show(e.av)) or "")
            items[#items + 1] = { class = e.c, text1 = "Killed " .. GK.Show(e.n),
                right1 = (e.p or 0) > 0 and ("+%d%s"):format(e.p, extra ~= "" and ("  " .. extra) or "") or "no points",
                text2 = where, open = PosterOf(e.n, e) }
        else
            items[#items + 1] = { class = e.c, text1 = "Slain by " .. GK.Show(e.n), right1 = e.s or "", text2 = where,
                open = PosterOf(e.n, e) }
        end
    end
    return items, "No kills or deaths yet. Only the open world counts: dungeons and battlegrounds hide who is who."
end

local function NewsItems()
    local items = {}
    for _, e in ipairs(GK.Store().feed) do
        local who, target = GK.Show(e.who), GK.Show(e.n)
        local line, right
        if e.kind == "K" then
            line = ("%s killed %s"):format(who, target)
            right = (e.p or 0) > 0 and ("+%d"):format(e.p) or nil
            if e.av then line = line .. (" for %s"):format(GK.Show(e.av)) end
        elseif e.kind == "D" then
            line = ("%s fell to %s"):format(who, target)
        elseif e.kind == "F" then
            line = ("%s fulfilled the order on %s"):format(who, target)
            right = (e.p or 0) > 0 and GK.MoneyText(e.p) or nil
        elseif e.kind == "C" then
            line = ("%s put a price on %s"):format(who, target)
            right = (e.p or 0) > 0 and GK.MoneyText(e.p) or "for honour"
        elseif e.kind == "T" then
            line = ("%s added to the pot on %s"):format(who, target)
            right = GK.MoneyText(e.p or 0)
        end
        if line then
            items[#items + 1] = { class = e.c, text1 = line, right1 = right,
                text2 = table.concat({ e.z or "", GK.Ago(e.t) }, e.z and "  -  " or ""), open = PosterOf(e.n, e) }
        end
    end
    return items, "Nothing yet. Kills, deaths and kill orders from everyone in your guild who runs Grudgekeeper show up here."
end

local PAGES = { OrderItems, BoardItems, GrudgeItems, NewsItems }

-- ---------------------------------------------------------------------------
-- The list
-- ---------------------------------------------------------------------------
local function BuildRow(row)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", 4, 0)
    row.text1 = row:CreateFontString(nil, "ARTWORK")
    row.text1:SetPoint("TOPLEFT", 44, -6)
    row.text1:SetJustifyH("LEFT")
    row.text1:SetWordWrap(false)
    row.right1 = row:CreateFontString(nil, "ARTWORK")
    row.right1:SetPoint("TOPRIGHT", -8, -8)
    row.right1:SetJustifyH("RIGHT")
    row.text1:SetPoint("RIGHT", row.right1, "LEFT", -8, 0)
    row.text2 = row:CreateFontString(nil, "ARTWORK")
    row.text2:SetPoint("TOPLEFT", row.text1, "BOTTOMLEFT", 0, -5)
    row.text2:SetJustifyH("LEFT")
    row.text2:SetWordWrap(false)
    row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.button:SetSize(84, 20)
    row.button:SetPoint("BOTTOMRIGHT", -6, 4)
    row.button2 = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.button2:SetSize(84, 20)
    row.button2:SetPoint("RIGHT", row.button, "LEFT", -4, 0)
    row.text2:SetPoint("RIGHT", row.button2, "LEFT", -6, 0)
    row.line = row:CreateTexture(nil, "BACKGROUND")
    row.line:SetColorTexture(0.35, 0.22, 0.1, 0.25)
    row.line:SetHeight(1)
    row.line:SetPoint("BOTTOMLEFT", 6, 0)
    row.line:SetPoint("BOTTOMRIGHT", -6, 0)
    row.mine = row:CreateTexture(nil, "BACKGROUND")
    row.mine:SetAllPoints()
    row.mine:SetColorTexture(0.6, 0.12, 0.05, 0.12)
    -- A row about someone opens their card when clicked: a faint wash under the mouse says so. The
    -- row's own buttons are children and take their own clicks first.
    row.hl = row:CreateTexture(nil, "BACKGROUND", nil, 1)
    row.hl:SetAllPoints()
    row.hl:SetColorTexture(0.35, 0.22, 0.1, 0.12)
    row.hl:Hide()
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self) if self.open then self.hl:Show() end end)
    row:SetScript("OnLeave", function(self) self.hl:Hide() end)
    row:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" and self.open and self:IsMouseOver() then self.open() end
    end)
end

local function SetRowButton(b, spec)
    b:SetShown(spec ~= nil)
    if spec then
        b:SetText(spec[1])
        b:SetScript("OnClick", function() spec[2]() end)
    end
end

local function FillRow(row, it)
    row.icon:SetShown(not it.header)
    if not it.header then
        if it.skull then
            row.icon:SetTexture(SKULL)
            row.icon:SetTexCoord(0, 1, 0, 1)
        else
            ClassIcon(row.icon, it.class)
        end
    end
    local colour = it.faded and FADED or INK
    if it.header then
        Ink(row.text1, BLOOD, TITLE_FONT, 18)
        row.text1:SetPoint("TOPLEFT", 8, -16)
    else
        Ink(row.text1, it.mine and BLOOD or colour, TITLE_FONT, 15)
        row.text1:SetPoint("TOPLEFT", 44, -6)
    end
    Ink(row.right1, it.faded and BLOOD or colour, TEXT_FONT, 12)
    Ink(row.text2, FADED, TEXT_FONT, 11)
    row.text1:SetText(it.text1 or "")
    row.right1:SetText(it.right1 or "")
    row.text2:SetText(it.text2 or "")
    row.mine:SetShown(it.mine == true)
    row.line:SetShown(not it.header)
    row.open = it.open
    row.hl:SetShown(it.open ~= nil and row:IsMouseOver())
    SetRowButton(row.button, it.button)
    SetRowButton(row.button2, it.button2)
    -- the second line runs to whichever button is there, or to the edge
    row.text2:ClearAllPoints()
    row.text2:SetPoint("TOPLEFT", row.text1, "BOTTOMLEFT", 0, -5)
    local stop = (it.button2 and row.button2) or (it.button and row.button) or nil
    if stop then row.text2:SetPoint("RIGHT", stop, "LEFT", -6, 0) else row.text2:SetPoint("RIGHT", row, "RIGHT", -8, 0) end
end

local function Refresh()
    if not (win and win:IsShown()) then return end
    local items, empty = PAGES[tab]()
    win.empty:SetText(#items == 0 and empty or "")
    local offset = FauxScrollFrame_GetOffset(win.scroll)
    FauxScrollFrame_Update(win.scroll, #items, ROWS, ROW_H)
    for i, row in ipairs(win.rows) do
        local it = items[i + offset]
        if it then
            row:Show()
            FillRow(row, it)
        else
            row:Hide()
        end
    end
    local open = #GK.OpenOrders()
    local rank, of = GK.MyRank()
    win.status:SetText(("%s  -  %s, #%d of %d  -  %s"):format(Plural(open, "open order"),
        Plural(GK.char.points, "point"), rank, of, GK.Title(GK.char.points)))
    win.post:SetShown(tab == 1)
    win.toggle:SetShown(tab == 2)
    win.toggle:SetText(weekly and "Show all time" or "Show this week")
    win.letters:SetText(("Letters (%d)"):format((GK.Unread())))
end

-- The page tabs: words in ink across the sheet, the chosen one in red and underlined.
local function Tabs(parent, labels)
    local buttons, widths, total = {}, {}, 0
    local function Select(i)
        tab = i
        for j, b in ipairs(buttons) do
            Ink(b.text, j == i and BLOOD or FADED, TITLE_FONT, 17)
            b.line:SetShown(j == i)
        end
    end
    for i, label in ipairs(labels) do
        local b = CreateFrame("Button", nil, parent)
        b.text = b:CreateFontString(nil, "ARTWORK")
        Ink(b.text, FADED, TITLE_FONT, 17)
        b.text:SetText(label)
        b.text:SetPoint("CENTER", 0, 1)
        widths[i] = math.ceil(b.text:GetStringWidth()) + 24
        total = total + widths[i]
        b:SetSize(widths[i], 26)
        b.line = b:CreateTexture(nil, "ARTWORK")
        b.line:SetColorTexture(BLOOD[1], BLOOD[2], BLOOD[3], 0.8)
        b.line:SetHeight(2)
        b.line:SetPoint("BOTTOMLEFT", 10, 0)
        b.line:SetPoint("BOTTOMRIGHT", -10, 0)
        b:SetScript("OnClick", function()
            Select(i)
            if FauxScrollFrame_SetOffset then FauxScrollFrame_SetOffset(win.scroll, 0) end
            win.scroll:SetVerticalScroll(0)
            Refresh()
        end)
        buttons[i] = b
    end
    local x = -total / 2
    for i, b in ipairs(buttons) do
        b:SetPoint("TOPLEFT", parent, "TOP", x, -84)
        x = x + widths[i]
    end
    Select(tab)
    return buttons
end

local function Build()
    -- One big unrolled scroll, like the letters: the order parchment between two rolls. None of the
    -- game's frames - Grudgekeeper has a look of its own.
    win = CreateFrame("Frame", "GrudgekeeperFrame", UIParent)
    win:SetSize(W, H)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetPoint("CENTER", 0, 40)
    local paper = win:CreateTexture(nil, "BACKGROUND")
    paper:SetPoint("TOPLEFT", 10, -ROLL_H / 2)
    paper:SetPoint("BOTTOMRIGHT", -10, ROLL_H / 2)
    paper:SetTexture(MEDIA .. "sheet")

    -- The rolls lie over the paper's ends, above everything on the sheet.
    local rolls = CreateFrame("Frame", nil, win)
    rolls:SetAllPoints()
    rolls:SetFrameLevel(win:GetFrameLevel() + 20)
    local top = GK.MakeRoll(rolls, ROLL_H)
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    local bottom = GK.MakeRoll(rolls, ROLL_H, true)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    local close = CreateFrame("Button", nil, rolls, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -4, 0)
    -- Our own Hide, so closing works in combat too.
    close:SetScript("OnClick", function() win:Hide() end)

    local title = win:CreateFontString(nil, "ARTWORK")
    Ink(title, BLOOD, TITLE_FONT, 30)
    title:SetPoint("TOP", 0, -40)
    title:SetText("Grudgekeeper")
    win.tabs = Tabs(win, { "Kill orders", "Leaderboard", "Grudges", "News" })
    -- Under the tabs: how many orders are out, and where you stand.
    win.status = win:CreateFontString(nil, "ARTWORK")
    Ink(win.status, FADED, TEXT_FONT, 11)
    win.status:SetPoint("TOP", 0, -116)

    local list = CreateFrame("Frame", nil, win)
    list:SetPoint("TOPLEFT", 34, -134)
    list:SetPoint("BOTTOMRIGHT", -34, 74)
    win.scroll = CreateFrame("ScrollFrame", nil, list, "FauxScrollFrameTemplate")
    win.scroll:SetPoint("TOPLEFT")
    win.scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    win.scroll:SetScript("OnVerticalScroll", function(self, value)
        FauxScrollFrame_OnVerticalScroll(self, value, ROW_H, Refresh)
    end)
    win.rows = {}
    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, list)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", win.scroll, "RIGHT", 0, 0)
        BuildRow(row)
        win.rows[i] = row
    end
    win.empty = list:CreateFontString(nil, "ARTWORK")
    Ink(win.empty, FADED, TEXT_FONT, 13)
    win.empty:SetPoint("TOPLEFT", 30, -50)
    win.empty:SetPoint("RIGHT", -30, 0)
    win.empty:SetSpacing(3)

    local function MakeButton(text, w)
        local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetText(text)
        return b
    end
    local settings = MakeButton(SETTINGS or "Settings", 84)
    settings:SetPoint("BOTTOMRIGHT", -34, 40)
    settings:SetScript("OnClick", function() if GK.OpenOptions() then win:Hide() end end)
    win.letters = MakeButton("Letters", 100)
    win.letters:SetPoint("RIGHT", settings, "LEFT", -6, 0)
    win.letters:SetScript("OnClick", function() GK.OpenLetters() end)
    win.post = MakeButton("Post a kill order", 140)
    win.post:SetPoint("BOTTOMLEFT", 34, 40)
    win.post:SetScript("OnClick", function() GK.PostOnTarget() end)
    -- The leaderboard's own switch, in the same corner on its page.
    win.toggle = MakeButton("Show all time", 140)
    win.toggle:SetPoint("BOTTOMLEFT", 34, 40)
    win.toggle:SetScript("OnClick", function()
        weekly = not weekly
        Refresh()
    end)

    win:Hide()
    if LIB.RegisterWindow then LIB.RegisterWindow(win, GK.db, "window") end
    win:HookScript("OnShow", Refresh)
end

function GK.OpenWindow(page)
    if not win then Build() end
    if page and win.tabs[page] then win.tabs[page]:Click() end
    win:Show()
    win:Raise()
    Refresh()
end

function GK.ToggleWindow()
    if win and win:IsShown() then win:Hide() else GK.OpenWindow() end
end

-- Once per burst of changes (GK.Changed gathers them); Refresh returns at once while the window is shut.
LIB.Listen("GRUDGEKEEPER_CHANGED", Refresh)
