-- Grudgekeeper - its settings page, a category of its own in Options -> AddOns -> Grudgekeeper.
-- Grudgekeeper is not one of the YippYapp addons (the user, 2026-11-03): it shares LibForever's
-- plumbing and nothing else, so no YippYapp page, minimap group or footer.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local category

-- Extra sections from other files, each fn(f, anchor, helpers) -> the new bottom anchor. Defined here, at
-- the top, so a file loaded after this one can append to it; Build calls them before Commands.
GK.OptionSections = GK.OptionSections or {}

local function Heading(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetAtlas("Options_HorizontalDivider")
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    return fs
end

local function Note(parent, text)
    local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    fs:SetWidth(560)
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(2)
    fs:SetText(text)
    return fs
end

-- The page is settings only: a short name for each, what it does in its "(i)", nothing else. The help
-- text and the lists of commands that ran on under them were "ALT for mye text" (the owner, 2026-11-06);
-- what the addon does is on its CurseForge page. Long enough for every row; Refresh measures the rest.
local PAGE_HEIGHT = 1600

local function PageHeight() return PAGE_HEIGHT end

-- Builds the page's contents on `panel` and returns its Refresh. Called the first time the page is
-- shown, not at login: some twenty boxes with their closures are not worth keeping in memory for every
-- player who never opens the settings.
local function Build(panel)
    local f = CreateFrame("Frame", nil, panel)
    f:SetPoint("TOPLEFT", 10, -10)
    f:SetPoint("BOTTOMRIGHT", -10, 10)

    local head = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", 8, -6)
    head:SetText("Grudgekeeper")
    local version = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", head, "BOTTOMRIGHT", 8, 1)
    version:SetText("v" .. GK.addonVersion)
    local sub = Note(f, "Open the ledger with |cffffd100/grudge|r or the minimap button. Hover the (i) to see "
        .. "what a setting does.")
    sub:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)

    -- The "(i)" after a label holds the explanation, so the page isn't a wall of text.
    local function Info(after, text)
        local b = CreateFrame("Button", nil, f)
        b:SetSize(18, 16)
        b:SetPoint("LEFT", after, "RIGHT", 5, 0)
        local fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        fs:SetPoint("CENTER")
        fs:SetText("(i)")
        local function Colour(hot) fs:SetTextColor(hot and 1 or 0.5, hot and 1 or 0.7, hot and 1 or 0.95) end
        Colour(false)
        b:SetScript("OnEnter", function(self)
            Colour(true)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(text, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() Colour(false) GameTooltip:Hide() end)
        return b
    end

    local checks = {}
    local function Box(anchor, text, info, onClick)
        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor.isHeading and -4 or 0, -4)
        local l = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        l:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        l:SetText(text)
        if info then Info(l, info) end
        cb:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
        return cb
    end
    local function Check(anchor, text, key, info)
        local cb = Box(anchor, text, info, function(on)
            GK.db[key] = on
            GK.Changed()
            if key == "share" and on then GK.SendBoard() end
            if key == "anyLetters" and GK.NoticeUpdate then GK.NoticeUpdate(false) end   -- the icon at once
            if key == "keepLetters" and not on and GK.FadeLetters then GK.FadeLetters() end  -- what waited fades
        end)
        checks[key] = cb
        return cb
    end

    local function Section(above, title)
        local h = Heading(f, title)
        h:SetPoint("TOPLEFT", above, "BOTTOMLEFT", above.isHeading and 0 or 4, -16)
        h.isHeading = true
        return h
    end

    local h1 = Heading(f, "Letters")
    h1:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", 0, -20)
    h1.isHeading = true
    local any = Check(h1, "Letters", "anyLetters",
        "News as small sealed letters by the letter icon. Off: none at all - the ledger, the warnings and the "
        .. "mailbox still tell you what matters.")
    local letters = Check(any, "Kill orders as letters", "letters",
        "A small sealed letter where you put it; click it to read. Off: orders only show in the ledger.")
    local mine = Check(letters, "Letters for my own kills and deaths", "myLetters",
        "The kill that earns you a new title, and the death that put a kill order on your killer.")
    local keep = Check(mine, "Letters wait until read", "keepLetters",
        "On: a letter waits by the letter icon until you read it. Off: an unread one fades after two minutes - "
        .. "Letters in the ledger still has it.")
    -- Placing the letter icon: it only shows when something came, so it needs a way to be shown now.
    local place = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    place:SetSize(170, 22)
    place:SetPoint("TOPLEFT", keep, "BOTTOMLEFT", 0, -6)
    place:SetText("Move the letter icon")
    place:SetScript("OnClick", function() GK.PlaceNotice() end)
    place:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Shows the letter icon now: drag it where you want it, then click it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    place:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local h2 = Section(place, "Warnings")
    local near = Check(h2, "When a kill order's target is near", "alertNear",
        "Near you: the sound below (once per player in 10 minutes) and a bubble by the letter - click it to "
        .. "target them. Seen by a guildie: who saw them, and where.")
    local nearSound = GK.SoundRow(f, near, function() return GK.db.nearSound end,
        function(key) GK.db.nearSound = key end)
    nearSound.which = "near"
    local marks = Check(nearSound, "Skull over targets' nameplates", "plateMarks",
        "Over anyone with an open order on them, and the eye over those you track. Needs enemy nameplates on (V).")
    local pins = Check(marks, "Last seen on the map", "mapPins",
        "Where a guildie saw an order's target, for 15 minutes. Click it for the poster.")

    local h3 = Section(pins, "Guild")
    local share = Check(h3, "Share my score with the guild", "share",
        "Your kills, deaths and points on the guild's leaderboard. Orders are always shared.")
    local auto = Check(share, "Kill orders on enemies who keep killing us", "autoOrders",
        "Three of the guild in two hours, or you three times in half an hour: your death posts an order on them.")

    local h3b = Section(auto, "Kill sprees")
    local sprNote = Note(f, "A splash in the middle of the screen, or a small toast by the letter icon. /grudge spree "
        .. "shows both.")
    sprNote:SetPoint("TOPLEFT", h3b, "BOTTOMLEFT", 0, -8)
    -- A choice of a few, under a label: the game's own dropdown, as the sound rows use. No dropdown in this
    -- client: no row. The menu reads the setting each time it opens, so Refresh has nothing to do for it.
    local function Choice(above, text, key, default, choices, info)
        local row = CreateFrame("Frame", nil, f)
        row:SetSize(400, 28)
        row:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, above == sprNote and -8 or -2)
        local l = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        l:SetPoint("LEFT", 4, 0)
        l:SetWidth(170)
        l:SetJustifyH("LEFT")
        l:SetText(text)
        local ok, dd = pcall(CreateFrame, "DropdownButton", nil, row, "WowStyle1DropdownTemplate")
        if not (ok and type(dd) == "table" and dd.SetupMenu) then
            l:Hide()
            row:SetHeight(1)
            return row
        end
        dd:SetWidth(240)
        dd:SetPoint("LEFT", l, "RIGHT", 6, 0)
        dd:SetupMenu(function(_, root)
            for _, c in ipairs(choices) do
                local value = c[1]
                root:CreateRadio(c[2], function() return (GK.db[key] or default) == value end, function()
                    GK.db[key] = value
                    GK.Changed()
                end)
            end
        end)
        row.dropdown = dd
        row.key = key
        return row
    end
    local KINDS = { { "off", "Off" }, { "toast", "Toast" }, { "splash", "Splash" } }
    local WHEN = { { "always", "Always" }, { "noCombat", "Not in combat" },
        { "noCombatInInstance", "Not in combat in a dungeon or raid" },
        { "noInstance", "Never in a dungeon or raid" } }
    local sMine = Choice(sprNote, "My sprees", "spreeMine", "splash", KINDS)
    local sGuild = Choice(sMine, "Guildies' sprees", "spreeGuild", "toast", KINDS)
    local sEnded = Choice(sGuild, "A spree ended", "spreeEnded", "toast", KINDS)
    local sTorm = Choice(sEnded, "A tormentor put down", "spreeTormentor", "toast", KINDS)
    local wMine = Choice(sTorm, "Show mine", "announceWhenMine", "always", WHEN)
    local wGuild = Choice(wMine, "Show guildies'", "announceWhenGuild", "noCombat", WHEN)
    -- One sound for each kind, the tiers rising; the play button is picking (or picking again).
    local soundAbove = wGuild
    local soundKeys = {}
    for _, t in ipairs(GK.SPREE_TIERS) do soundKeys[#soundKeys + 1] = { t.key, t.name } end
    soundKeys[#soundKeys + 1] = { "ended", "Spree ended" }
    soundKeys[#soundKeys + 1] = { "tormentor", "Tormentor" }
    for _, k in ipairs(soundKeys) do
        local key = k[1]
        local row = GK.SoundRow(f, soundAbove, function()
            return (GK.db.spreeSounds or {})[key] or GK.SPREE_DEFAULT_SOUNDS[key]
        end, function(picked)
            GK.db.spreeSounds = GK.db.spreeSounds or {}
            GK.db.spreeSounds[key] = picked
        end, k[2])
        row.which = key
        soundAbove = row
    end

    local h4 = Section(soundAbove, "Around the game")
    local tip = Check(h4, "A line on enemy tooltips", "tooltip", "Only for enemies you have a history with.")
    local menu = Check(tip, "In the right-click menu", "unitMenu", "A player's poster, record, notes or a kill order.")
    local inspect = Check(menu, "A tab on the Inspect window", "inspectTab", "A guildie's record, right there.")
    local guildBadge = Box(inspect, "A badge on the guild window", "Click it for the leaderboard.", function(on)
            GK.db.guildButton = on
            GK.RefreshGuildBadge()
        end)
    local mini = Box(guildBadge, "Minimap button", "Left-click opens Grudgekeeper, right-click these settings.",
        GK.SetMinimapShown)
    local sound = Check(mini, "Sounds", "sound", "A page turning, the stamp, the horn of a target near.")
    local h5 = Section(sound, "Screenshots")
    local shot = Check(h5, "When I fulfil a kill order", "shotFulfil", "Saved where the game saves screenshots.")
    local every = Check(shot, "At every kill", "shotEveryKill")
    -- The skin: two of the game's radio buttons (Core.lua, GK.SetLook). It dresses the ledger, the note and
    -- the who-picker; the letters and the kill order's scroll are the Grudgekeeper's paper in both.
    local hSkin = Section(every, "Skin")
    local skins = {}
    local function SkinChoice(anchor, name, text, info)
        local rb = CreateFrame("CheckButton", nil, f, "UIRadioButtonTemplate")
        rb:SetSize(16, 16)
        rb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", anchor.isHeading and 2 or 0, -10)
        local l = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        l:SetPoint("LEFT", rb, "RIGHT", 8, 0)
        l:SetText(text)
        Info(l, info)
        rb:SetScript("OnClick", function()
            GK.SetLook(name)
            for n, b in pairs(skins) do b:SetChecked(n == (GK.db.look or "parchment")) end
        end)
        skins[name] = rb
        return rb
    end
    local parchment = SkinChoice(hSkin, "parchment", "Parchment", "The Grudgekeeper's own ledger, on parchment.")
    local classic = SkinChoice(parchment, "classic", "Classic", "The game's own dark panels, in gold and white.")
    -- A section of its own: the faces go with neither skin ("classic portraits no matter what ... en egen
    -- settings uavhengig av classic/parchment settings", the owner, 2026-11-11), and they are the default.
    local hFaces = Section(classic, "Portraits")
    local faces = Check(hFaces, "Old race portraits", "oldPortraits",
        "The faces from the old character-creation screen. Off, today's race icons. Races added later always "
        .. "have today's.")

    local bottom = faces
    local helpers = { Section = Section, Check = Check, Box = Box, Note = Note, Info = Info }
    for _, fn in ipairs(GK.OptionSections) do bottom = fn(f, bottom, helpers) or bottom end

    local function Refresh()
        for key, cb in pairs(checks) do cb:SetChecked(GK.db[key] and true or false) end
        mini:SetChecked(not (GK.db.minimap and GK.db.minimap.hide))
        guildBadge:SetChecked(GK.db.guildButton ~= false)
        for n, b in pairs(skins) do b:SetChecked(n == (GK.db.look or "parchment")) end
        -- as long as its last row, once the page is laid out, so the scroll ends where the settings do
        if panel:GetTop() and bottom:GetBottom() then
            panel:SetHeight(math.max(400, panel:GetTop() - bottom:GetBottom() + 30))
        end
    end
    return Refresh
end

function GK.RegisterOptions()
    if category then return end
    local panel = CreateFrame("Frame")
    panel:SetSize(572, PageHeight())
    local Refresh                       -- made with the page, the first time it is shown
    local function OnShow()
        if not Refresh then Refresh = Build(panel) end
        Refresh()
    end
    panel:SetScript("OnShow", OnShow)

    -- Blizzard's own settings frame, in a category of our own; the page scrolls.
    local shown = LIB.PanelScroller and LIB.PanelScroller(panel, PageHeight()) or panel
    shown.OnRefresh = OnShow
    if Settings and Settings.RegisterCanvasLayoutCategory then
        category = Settings.RegisterCanvasLayoutCategory(shown, "Grudgekeeper")
        Settings.RegisterAddOnCategory(category)
    end
end

--- Returns true when the settings opened; says why in chat when they can't.
function GK.OpenOptions()
    if not (category and category.GetID and category:GetID()) then
        print(GK.TAG .. ": the settings page isn't available.")
        return false
    end
    -- Blizzard's settings frame is protected in combat.
    if InCombatLockdown() then
        print(GK.TAG .. ": settings can't open in combat.")
        return false
    end
    Settings.OpenToCategory(category:GetID())
    return true
end
