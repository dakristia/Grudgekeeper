-- Grudgekeeper - the Classic look: the window, the way Guild Grudge's is made. The same pages as the
-- ledger (GK.LedgerPages, so a page another file adds is here too), the same rows (the page's items()
-- through GK.SortItems) and the same card for the chosen row (GK.LedgerCard); only the drawing differs:
-- tabs along the bottom (the pages with side = "right" in a group on the right, the rest on the left), a search
-- box, a sort menu and Mine only for the pages that can be sorted, the rows in a scrolling list and the
-- chosen row's card in a panel on the right.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")
local C = GK.Classic

local NAME = "GrudgekeeperClassicWindow"
local ROW_H = 40
local LIST_W = 340
local TOP = 82                            -- where the list and the detail start, down from the window's top
local SORTS = { { "default", "Default" }, { "newest", "Newest" }, { "oldest", "Oldest" }, { "name", "A-Z" },
    { "votes", "Votes" } }
local COLS_W = 184                        -- what a row with two columns keeps clear on the right
local RIGHT_W = 64                        -- the right-hand text's column

local win
local tab = 1
local selected = {}                       -- [tab] = the key of the row whose card is shown
local chosenKey                           -- the key of the row that is highlighted now
local colHeads = {}                       -- the page's column names, for the rows to label their numbers with

local Refresh

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------
local function InitRow(row, it)
    if not row.created then
        row.created = true
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.face = C.Face(row, 28)
        row.face:SetPoint("LEFT", 6, 0)
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.name:SetPoint("TOPLEFT", 40, -5)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sub:SetPoint("BOTTOMLEFT", 40, 5)
        row.sub:SetJustifyH("LEFT")
        row.sub:SetWordWrap(false)
        row.right = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.right:SetPoint("RIGHT", -8, 0)
        row.right:SetWidth(RIGHT_W)
        row.right:SetJustifyH("RIGHT")
        row.c2 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.c2:SetPoint("RIGHT", -(8 + RIGHT_W + 6), 0)
        row.c2:SetWidth(48)
        row.c2:SetJustifyH("RIGHT")
        row.c1 = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.c1:SetPoint("RIGHT", row.c2, "LEFT", -4, 0)
        row.c1:SetWidth(48)
        row.c1:SetJustifyH("RIGHT")
        row.wide = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        row.wide:SetJustifyH("RIGHT")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row:SetScript("OnClick", function(self)
            if not self.item or self.item.header then return end
            selected[tab] = self.item.key
            Refresh()
        end)
    end
    row.item = it
    if it.header then
        row.face:SetShown(false)
        row.name:ClearAllPoints()
        row.name:SetPoint("LEFT", 10, 0)
        row.name:SetWidth(LIST_W - 60)
        row.name:SetTextColor(1, 0.82, 0)
        row.name:SetText(it.name or "")
        row.sub:SetText("")
        row.c1:SetText("") row.c2:SetText("") row.right:SetText("") row.wide:SetText("")
        row.bg:SetColorTexture(1, 1, 1, 0.08)
        row:UnlockHighlight()
        row:EnableMouse(false)
        return
    end
    row:EnableMouse(true)
    row.face:SetShown(true)
    row.face:Set(it.face or {})
    row.name:ClearAllPoints()
    row.name:SetPoint("TOPLEFT", 40, -5)
    local label = it.rank and (it.rank .. ". " .. (it.name or "")) or (it.name or "")
    if it.mine then row.name:SetTextColor(0.4, 1, 0.4)
    elseif it.faded then row.name:SetTextColor(0.6, 0.6, 0.6)
    else row.name:SetTextColor(C.ClassColor(it.face and it.face.c)) end
    row.name:SetText(label)
    row.sub:SetText(it.sub or "")
    local rc = it.rightColour or (it.faded and { 0.6, 0.6, 0.6 }) or C.GOLD
    row.right:SetTextColor(rc[1], rc[2], rc[3])
    row.right:SetText(it.right or "")
    row.c1:SetText(it.c1 and (colHeads[1] and ("|cff9d9d9d%s|r %s"):format(colHeads[1], it.c1) or it.c1) or "")
    row.c2:SetText(it.c2 and (colHeads[2] and ("|cff9d9d9d%s|r %s"):format(colHeads[2], it.c2) or it.c2) or "")
    -- the name runs to whichever columns are there
    local hasRight = (it.right or "") ~= ""
    local keep = it.c1 and COLS_W or (hasRight and (row.right:GetStringWidth() + 14) or 8)
    row.wide:ClearAllPoints()
    row.wide:SetPoint("RIGHT", row, "RIGHT", -keep, 0)
    row.wide:SetText(it.wide or "")
    if it.wide then keep = keep + (row.wide:GetStringWidth() or 60) + 8 end
    row.name:SetWidth(math.max(40, LIST_W - 40 - 18 - keep))
    row.sub:SetWidth(math.max(40, LIST_W - 40 - 18 - keep))
    row.bg:SetColorTexture(1, 1, 1, it.mine and 0.08 or 0.04)
    row.bg:SetShown(it.mine == true or (it.rank or 0) % 2 == 0)
    if chosenKey and it.key == chosenKey then row:LockHighlight() else row:UnlockHighlight() end
end

-- ---------------------------------------------------------------------------
-- Building the window
-- ---------------------------------------------------------------------------
local function BuildToolbar(f)
    local search = CreateFrame("EditBox", nil, f, "SearchBoxTemplate")
    search:SetSize(150, 20)
    search:SetPoint("TOPLEFT", 72, -32)
    search:SetAutoFocus(false)
    search:HookScript("OnTextChanged", function() Refresh() end)
    f.search = search

    -- One radio per sort mode; the value we pass is what the game hands back to both functions.
    local sort = CreateFrame("DropdownButton", nil, f, "WowStyle1DropdownTemplate")
    sort:SetWidth(110)
    sort:SetPoint("LEFT", search, "RIGHT", 8, 0)
    if sort.SetupMenu then
        sort:SetupMenu(function(_, root)
            for _, s in ipairs(SORTS) do
                root:CreateRadio(s[2], function(mode) return (GK.db.sortMode or "default") == mode end,
                    function(mode)
                        GK.db.sortMode = mode
                        Refresh()
                    end, s[1])
            end
        end)
    end
    f.sort = sort

    local mine = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    mine:SetSize(24, 24)
    mine:SetPoint("LEFT", sort, "RIGHT", 6, 0)
    if mine.Text then
        mine.Text:SetText("Mine only")
    else
        local label = mine:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", mine, "RIGHT", 2, 0)
        label:SetText("Mine only")
    end
    mine:SetScript("OnClick", function(self)
        GK.db.mineOnly = self:GetChecked() and true or false
        Refresh()
    end)
    C.Tip(mine, "Only the rows you wrote, posted, took, fulfilled or voted on")
    f.mine = mine

    -- under the toolbar: what the page says about itself, its own links, and what follows them
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", 14, -62)
    f.sub:SetJustifyH("LEFT")
    f.sub:SetWordWrap(false)
    f.links = {}
    for i = 1, 4 do
        local b = C.Button(f, "", 84)
        b:SetHeight(18)
        b:SetScript("OnClick", function(self)
            if self.click then self.click() end
            Refresh()
        end)
        f.links[i] = b
    end
    f.tail = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
end

local function BuildList(f)
    local inset = f.Inset
    inset:ClearAllPoints()
    inset:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -TOP)
    inset:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 4, 26)
    inset:SetWidth(LIST_W)

    local box = CreateFrame("Frame", nil, inset, "WowScrollBoxList")
    box:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    box:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -14, 4)
    local bar = CreateFrame("EventFrame", nil, inset, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 2, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 2, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(ROW_H)
    view:SetElementInitializer("Button", InitRow)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    if ScrollUtil.AddManagedScrollBarVisibilityBehavior then
        ScrollUtil.AddManagedScrollBarVisibilityBehavior(box, bar)
    end
    f.box = box
    -- on the ScrollBox, because regions of the window itself draw under the Inset
    f.empty = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.empty:SetPoint("CENTER")
    f.empty:SetWidth(260)
    f.empty:SetJustifyH("CENTER")
end

local function BuildDetail(f)
    local d = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
    d:SetPoint("TOPLEFT", f.Inset, "TOPRIGHT", 4, 0)
    d:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 26)
    d.view = C.CardView(d)
    d.view:SetAllPoints()
    d.hint = d:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    d.hint:SetPoint("CENTER")
    d.hint:SetWidth(200)
    f.detail = d
end

--- The buttons along the bottom, on the frame's button bar.
local function BuildButtons(f)
    f.post = C.Button(f, "Post a kill order", 130)
    f.post:SetPoint("BOTTOMLEFT", 8, 3)
    f.post:SetScript("OnClick", function() GK.PostOnTarget() end)
    f.letters = C.Button(f, "Letters", 100)
    f.letters:SetPoint("LEFT", f.post, "RIGHT", 4, 0)
    f.letters:SetScript("OnClick", function() GK.OpenLetters() end)
    f.settings = C.Button(f, SETTINGS or "Settings", 80)
    f.settings:SetPoint("LEFT", f.letters, "RIGHT", 4, 0)
    f.settings:SetScript("OnClick", function() if GK.OpenOptions() then f:Hide() end end)
end

-- PanelTemplates_SetNumTabs chains every tab to the one before it, so the pages with side = "right" would
-- sit beside the others. This pins that group to the bottom right corner instead; the chained anchors go
-- first, or they would fight the new ones. Guild Grudge's window does the same.
local function AnchorRightTabs(tabs)
    local right = {}
    for _, t in ipairs(tabs) do
        if t.side == "right" then right[#right + 1] = t end
    end
    if #right == 0 then return end
    for _, t in ipairs(right) do t:ClearAllPoints() end
    right[#right]:SetPoint("TOPRIGHT", win, "BOTTOMRIGHT", -5, 2)
    for i = #right - 1, 1, -1 do
        right[i]:SetPoint("TOPRIGHT", right[i + 1], "TOPLEFT", -3, 0)
    end
end

local function SelectTab(i)
    tab = i
    PanelTemplates_SetTab(win, i)
    Refresh()
end

local function BuildTabs(f)
    local tabs = {}
    for i, def in ipairs(GK.LedgerPages) do
        local t = CreateFrame("Button", NAME .. "Tab" .. i, f, "PanelTabButtonTemplate")
        tabs[i] = t
        t:SetID(i)
        t:SetText(def.name)
        t.side = def.side
        if i == 1 then t:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 5, 2) end
        t:SetScript("OnClick", function(self) SelectTab(self:GetID()) end)
    end
    PanelTemplates_SetNumTabs(f, #tabs)
    AnchorRightTabs(tabs)
    f.tabs = tabs
end

local function Build()
    win = C.Frame(NAME, 700, 500, "Grudgekeeper")
    BuildToolbar(win)
    BuildList(win)
    BuildDetail(win)
    BuildButtons(win)
    BuildTabs(win)
    PanelTemplates_SetTab(win, tab)
    win:SetScript("OnShow", function() Refresh() end)
end

-- ---------------------------------------------------------------------------
-- Filling it
-- ---------------------------------------------------------------------------
--- The row whose card shows: the chosen one if it is still there, else the page's own default - the same
--- rule as the ledger's.
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

--- The rows whose name or sub line has the text in it. A search drops the header rows.
local function Matching(items, filter)
    local out = {}
    for _, it in ipairs(items) do
        if not it.header then
            local hay = ((it.name or "") .. " " .. (it.sub or "")):lower()
            if hay:find(filter, 1, true) then out[#out + 1] = it end
        end
    end
    return out
end

--- The names of the page's columns, for the rows to label their numbers with: its centred headings, in order.
local function ColumnHeads(def)
    local heads = {}
    for _, h in ipairs(def.headings or {}) do
        if h[3] == "CENTER" then heads[#heads + 1] = h[1] end
    end
    return heads
end

Refresh = function()
    if not (win and win:IsShown()) then return end
    local def = GK.LedgerPages[tab]
    local all, empty = def.items()
    if def.sortable then all = GK.SortItems(all, def) end
    local chosen = Chosen(all)
    chosenKey = chosen and chosen.key
    local filter = (win.search:GetText() or ""):lower():match("^%s*(.-)%s*$")
    local list = filter == "" and all or Matching(all, filter)

    -- the strip under the toolbar
    win.sub:SetText(def.sub and def.sub(all) or "")
    local links = def.links and def.links() or {}
    local last
    for i, b in ipairs(win.links) do
        local l = links[i]
        b:SetShown(l ~= nil)
        if l then
            b:SetText(l.text)
            b:SetEnabled(not l.on)
            b.click = l.click
            b:ClearAllPoints()
            if last then b:SetPoint("TOPLEFT", last, "TOPRIGHT", 4, 0)
            else b:SetPoint("TOPLEFT", win, "TOPRIGHT", -(14 + 88 * #links - 4), -58) end
            last = b
        end
    end
    win.tail:ClearAllPoints()
    if last then win.tail:SetPoint("RIGHT", win.links[1], "LEFT", -6, 0) end
    win.tail:SetText(last and def.linksTail and def.linksTail() or "")
    local sortable = def.sortable == true
    win.sort:SetShown(sortable)
    win.mine:SetShown(sortable)
    win.mine:SetChecked(GK.db.mineOnly == true)
    if sortable and win.sort.GenerateMenu then win.sort:GenerateMenu() end

    -- the rows
    colHeads = ColumnHeads(def)
    local dp = CreateDataProvider()
    for _, it in ipairs(list) do dp:Insert(it) end
    win.box:SetDataProvider(dp, ScrollBoxConstants.RetainScrollPosition)
    if #list == 0 then
        local text = empty
        if filter ~= "" then text = "No matches."
        elseif sortable and GK.db.mineOnly and #all == 0 then text = "Nothing of yours here." end
        win.empty:SetText(text or "")
        win.empty:Show()
    else
        win.empty:Hide()
    end
    win.letters:SetText(("Letters (%d)"):format((GK.Unread())))

    -- the card
    local d = chosen and GK.LedgerCard(chosen.select)
    win.detail.view:SetShown(d ~= nil)
    win.detail.hint:SetText((d == nil and #all > 0) and "Choose a row on the left." or "")
    if d then win.detail.view:Fill(d, Refresh) end
end

C.Wraps.OpenWindow = function(_, page)
    if not win then Build() end
    if page and GK.LedgerPages[page] then SelectTab(page) end
    win:Show()
    win:Raise()
    Refresh()
end

C.Wraps.ToggleWindow = function()
    if win and win:IsShown() then win:Hide() else GK.OpenWindow() end
end

-- Once per burst of changes (GK.Changed gathers them); Refresh returns at once while the window is shut.
LIB.Listen("GRUDGEKEEPER_CHANGED", function()
    if GK.IsClassic() then Refresh() end
end)
