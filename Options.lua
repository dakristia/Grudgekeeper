-- Grudgekeeper - its settings page, a category of its own in Options -> AddOns -> Grudgekeeper.
-- Grudgekeeper is not one of the YippYapp addons (the user, 2026-11-03): it shares LibForever's
-- plumbing and nothing else, so no YippYapp page, minimap group or footer.
local ADDON, GK = ...
local LIB = LibStub("LibForever-1.0")

local category

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

local HELP = {
    { "What it does",
      "Grudgekeeper keeps score of your world PvP: every enemy player you kill, everyone who kills you, and "
      .. "how often. Your guild sees a leaderboard of points, and who has killed the guild most. Anyone can "
      .. "put a kill order - with a bounty, or for honour - on an enemy player. Take an order and you are "
      .. "warned when the target is near; kill them and the order is yours, a screenshot is taken, and the "
      .. "one who posted it is told what they owe you." },
    { "Letters, not popups",
      "News arrives as a small sealed letter, the way the game shows new mail - but wherever you put it: "
      .. "a kill order from your guild, your points after a kill, who killed you. It fades in, blinks, and "
      .. "waits; click it to read. Drag it anywhere, or use Place the letter icon above. Nothing opens in "
      .. "the middle of your screen. When a target you took is near, the letter glows red and a soft chime "
      .. "sounds." },
    { "How it knows",
      "Forever keeps the combat log from addons, so Grudgekeeper reads what the game does hand over: your "
      .. "killing blows (and your pet's), the death recap when you die, and the players you can see - their "
      .. "nameplates, your target and your mouse. Turn enemy nameplates on (V) to see the most. It counts "
      .. "the open world only: dungeons and battlegrounds hide who is who." },
    { "Points",
      "A kill is worth what their level is to you: green 1, yellow 2, orange 3, red 4, grey nothing. "
      .. "Revenge - they killed you since you last got them - is 1 more, and so is avenging a guildie they "
      .. "killed in the last 15 minutes. The same player is worth points twice a day, then nothing. A kill "
      .. "that fulfils an order is worth 3 more. Points earn titles, from Unblooded to Dread Reaper at 800; "
      .. "the leaderboard shows this week (from the weekly reset) or all time." },
    { "Bounties",
      "No gold is taken when you post an order. If a guildie already has one on the same player, yours goes "
      .. "into their pot instead, so there is one order and one pot. Whoever fulfils it is owed every share, "
      .. "and at a mailbox a Pay bounty button fills in the letter for each one you owe - you press Send. "
      .. "Payment is on your honour: the game doesn't let an addon move gold." },
    { "Orders that post themselves",
      "An enemy who kills three of the guild in two hours, or the same guildie three times in half an hour, "
      .. "gets a kill order without anyone writing one: the death that makes it three posts it, for the "
      .. "guild's honour, for three days. Anyone can take it or put gold in its pot like any other order." },
    { "Profiles",
      "Right-click a player, or click a name in the Grudgekeeper window. An enemy gets a wanted poster: how "
      .. "often they killed the guild and whom, how often the guild got them, your own score with them, where "
      .. "they were last seen and the bounty on them. A guildie gets their record: title and points, this "
      .. "week and all time, kill streak, orders fulfilled, nemesis. It shows what your client has heard: "
      .. "guildies send their numbers as they play." },
}

local PAGE_HEIGHT = 1260

-- Builds the page's contents on `panel` and returns its Refresh. Called the first time the page is
-- shown, not at login: some twenty boxes with their closures, and the help text, are not worth
-- keeping in memory for every player who never opens the settings.
local function Build(panel)
    local f = CreateFrame("Frame", nil, panel)
    f:SetPoint("TOPLEFT", 10, -10)
    f:SetPoint("BOTTOMRIGHT", -10, 10)

    local head = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    head:SetPoint("TOPLEFT", 8, -6)
    head:SetText("Grudgekeeper")
    local version = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    version:SetPoint("BOTTOMLEFT", head, "BOTTOMRIGHT", 8, 1)
    version:SetText("v" .. GK.version)
    local sub = Note(f, "Keep score of your world PvP, see the guild's leaderboard, and post kill orders with a "
        .. "bounty on the players who keep killing you.")
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
    local letters = Check(h1, "Kill orders from your guild arrive as letters", "letters",
        "On by default. A small sealed letter fades in where you put it and blinks; click it to read. "
        .. "Untick and new orders only show in the Kill orders page.")
    local mine = Check(letters, "A letter for your own kills and deaths", "myLetters",
        "On by default. Your points after a kill and your place in the guild, or who killed you and how "
        .. "often - with a button to put a price on their head.")
    -- Placing the letter icon: it only shows when something came, so it needs a way to be shown now.
    local place = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    place:SetSize(170, 22)
    place:SetPoint("TOPLEFT", mine, "BOTTOMLEFT", 0, -6)
    place:SetText("Place the letter icon")
    place:SetScript("OnClick", function() GK.PlaceNotice() end)
    local placeNote = Note(f, "Shows it now; drag it, then click it. Close this window first if it's behind it.")
    placeNote:SetWidth(380)
    placeNote:SetPoint("LEFT", place, "RIGHT", 10, 0)

    local h2 = Section(place, "Warnings")
    local near = Check(h2, "Warn me when a target I took is near", "alertNear",
        "On by default. The scroll glows red, a soft chime sounds and one line under it says who. Only for "
        .. "orders you took, and at most every 90 seconds per target.")
    local all = Check(near, "Warn me for every open kill order", "alertAll",
        "Off by default. The same warning for every order the guild has out, taken or not.")
    local marks = Check(all, "Mark kill order targets' nameplates", "plateMarks",
        "On by default. A red skull seal over anyone with an open order on them. Needs enemy nameplates on (V).")
    local pins = Check(marks, "Show where targets were last seen on the map", "mapPins",
        "On by default. The same seal on the world map, where a guildie stood when they saw the target of an "
        .. "open order - for 15 minutes after. Click it for the wanted poster.")

    local h3 = Section(pins, "Screenshots")
    local shot = Check(h3, "When you fulfil a kill order", "shotFulfil",
        "On by default. A screenshot the moment the target dies, for the guild's wall of fame. Saved where "
        .. "the game saves screenshots.")
    local every = Check(shot, "At every kill", "shotEveryKill", "Off by default.")

    local h4 = Section(every, "Guild")
    local share = Check(h4, "Share my kills, deaths and points with my guild", "share",
        "On by default. Puts you on the guild's leaderboard, counts who killed you in Most wanted, and tells "
        .. "the hunters where you saw a wanted player - the zone, and your own spot on the map at that moment. "
        .. "Orders you post, take or fulfil are always shared - "
        .. "that is what they are for.")
    local auto = Check(share, "Post a kill order when an enemy keeps killing us", "autoOrders",
        "On by default. When one enemy has killed three of the guild in two hours, or you three times in half "
        .. "an hour, your death posts a kill order on them in your name: no gold, for three days. Not when "
        .. "someone already has an order on them, at most one a day per enemy, and only while you share with "
        .. "the guild. You can withdraw it on the hitlist.")
    local sound = Check(auto, "Sounds", "sound", "On by default: a page turning when a letter comes (not for "
        .. "your own kills), the stamp, the soft chime of a target nearby.")

    local h5 = Section(sound, "Around the game")
    local tip = Check(h5, "One line on enemy players' tooltips", "tooltip",
        "On by default. Only for enemies you have a history with: how often they killed you and you them, "
        .. "how often they killed the guild, and the bounty on them. Everyone else's tooltip is left alone.")
    local menu = Check(tip, "Grudgekeeper profile in the right-click menu", "unitMenu",
        "On by default. Right-click an enemy player for their wanted poster, or a guildie for their record: on "
        .. "the target frame, party and raid frames, a name in chat and the guild roster. One line at the "
        .. "end of the game's menu; nothing of the game's own is changed.")
    local guildBadge = Box(menu, "A badge beside the guild window", "On by default. A small round Grudgekeeper "
        .. "badge on the guild window's right edge; click it for the leaderboard.", function(on)
            GK.db.guildButton = on
            GK.RefreshGuildBadge()
        end)
    local mini = Box(guildBadge, "Show the minimap button", "On by default. Left-click opens Grudgekeeper, "
        .. "right-click these settings. /grudge does the same.", GK.SetMinimapShown)

    local h6 = Section(mini, "Commands")
    local cmds = Note(f, "|cffffd100/grudge|r opens the window: kill orders, the leaderboard, your grudges.\n"
        .. "|cffffd100/grudge post|r writes a kill order on your target.  |cffffd100/grudge letters|r reads your letters.\n"
        .. "|cffffd100/grudge test|r puts four sample letters in your pile, to see what they look like.\n"
        .. "|cffffd100/grudge notice|r shows the letter icon to drag it into place.")
    cmds:SetPoint("TOPLEFT", h6, "BOTTOMLEFT", 0, -8)

    local function Refresh()
        for key, cb in pairs(checks) do cb:SetChecked(GK.db[key] and true or false) end
        mini:SetChecked(not (GK.db.minimap and GK.db.minimap.hide))
        guildBadge:SetChecked(GK.db.guildButton ~= false)
        -- The help text, measured from `cmds` (which never moves): only once the page is laid out.
        if LIB.AddHelp and panel:GetTop() and cmds:GetBottom() then
            local y = -(panel:GetTop() - cmds:GetBottom()) - 24
            local bottom = LIB.AddHelp(panel, HELP, y)
            panel:SetHeight(math.max(PAGE_HEIGHT, -bottom + 40))
        end
    end
    return Refresh
end

function GK.RegisterOptions()
    if category then return end
    local panel = CreateFrame("Frame")
    panel:SetSize(572, PAGE_HEIGHT)
    local Refresh                       -- made with the page, the first time it is shown
    local function OnShow()
        if not Refresh then Refresh = Build(panel) end
        Refresh()
    end
    panel:SetScript("OnShow", OnShow)

    -- Blizzard's own settings frame, in a category of our own; the page scrolls.
    local shown = LIB.PanelScroller and LIB.PanelScroller(panel, PAGE_HEIGHT) or panel
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
