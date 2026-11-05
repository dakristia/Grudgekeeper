# Guild Grudge merged into Grudgekeeper

This document is for the owner of Grudgekeeper and for any AI agent that reviews or continues this work.
It says what came over from Guild Grudge, every design choice and why, the questions still open, and
exactly where the new code touches Grudgekeeper's own files.

Guild Grudge (github.com/dakristia/GuildGrudge, v0.8.0) was a guild notebook on players: free-text
notes, a Shame list for same-faction players to be careful with, a Kudos list for good players, a list
of funny character names, votes, tags, sorting, a "mine only" filter and group-join warnings. Its
bounties and bounty hunters are NOT brought over: kill orders and the leaderboard do that better.

## How to read this document

- **Decisions** (D1, D2, ...) are settled between the two authors' sides unless the owner says otherwise.
- **Questions** (Q1, Q2, ...) are for the owner. Each says what this PR does today, so the PR works
  whichever way the answer goes, and what would change if the answer is no.
- **Hooks** (H1, H2, ...) list every edit to a file that existed before this PR. All other code is in
  new files.

## Decisions

- **D1. Grudgekeeper's ledger is the default look.** Nothing about the book, its art or its behaviour
  changes for a player who doesn't touch the new settings.
- **D2. Each player sends only their own things.** This is Grudgekeeper's rule (Guild.lua header) and the
  notes follow it: your notes, your list marks, your votes, your nice names. Nobody edits or deletes
  another player's note. A client never re-sends someone else's data. See Q2 for what this costs.
- **D3. Same-faction players are in scope for notes**, Shame, Kudos and Names. Guild Grudge was built
  for same-faction use (ninja looters, scammers, good healers). Kill orders stay enemy-only. See Q1.
- **D4. No kill orders on same-faction players.** Guild Grudge allowed bounties on anyone while there
  were few Horde players to test on. That stops here.
- **D5. Three lists, one mark per author.** A player can be on "Marked", "Shame" or "Kudos" (the Marked list is stored, sent and named in code as `kos`, and Shame as `watch`; only the words a player sees say Marked and Shame). The
  list is each author's own mark: if Kari puts someone on Shame and Edvard gives them Kudos, they show on
  both lists, each with who put them there. Moving a player only moves your own mark.
- **D6. Tags.** A note can carry one tag. Shame has preset tags (Ninja looter, Scammer, Toxic, Griefer,
  Leaver), Kudos has its own (Helpful, Kind, Skilled, Great healer, Great tank, Fair looter, Fun to group
  with), and a player can type a custom one (at most 24 characters). Every preset has an icon (Ninja looter a
  rogue's stealth, Scammer a coin, Helpful a renew, and so on) and a custom tag gets a note. The data is in
  `Notes.lua`; `GK.TagIcon(tag)` gives the texture path and `GK.TagText(tag, size)` the `|T...|t Tag` text
  that every place a tag is shown uses (rows, cards, tooltip, warnings, menus, the note sheet's tag links).
- **D7. Nice names.** A guild-shared list of funny character names, with no notes, alerts or orders.
  Only the player who added a name can remove it (D2). The guild master and officers can **hide** a name
  for everyone, for cleanup; a hidden name is still in the data and can be shown again. See Q6.
- **D8. Votes.** Notes and nice names can be voted up or down, one vote per player, which they can change
  or take back. You can't vote on your own note or name.
- **D9. Sorting and Mine only.** Newest, oldest, A-Z and most votes, on the pages where an order makes
  sense (kill orders, grudges, news and the four list pages). The leaderboard keeps its rank order. "Mine only" keeps the
  rows you wrote, posted, took, fulfilled or voted on.
- **D10. Noted players are highlighted quietly, and alert only if asked.** A player with notes and no
  kill order gets a small, dim mark on their nameplate (left of where a kill order's seal sits: a cross
  for Marked, an exclamation for Shame, a tick for Kudos) and a tooltip line. An enemy's existing
  Grudge line gets the list and the note count added; anyone else gets a line of their own. They raise
  the "is near" warning only when a setting turns that on (off by default); a Shame player nearby is one
  chat line, also off by default; Kudos is never announced. At most one warning per player every 90 seconds.
- **D11. Group-join warnings.** When someone on your Shame list joins your group you get a warning, the
  same way Grudgekeeper warns about a target nearby. A Kudos player joining gets one friendly chat line.
  Both are settings.
- **D12. Two looks, Ledger and Classic.** The Classic look is Guild Grudge's own: Blizzard's standard
  frames, tabs, a search box, the sort menu and a detail panel. It covers every surface: the window,
  the cards, the letters, the letter icon, the order and note sheets. It is a setting; the ledger stays
  the default (D1). See Q4.
- **D13. Alert style is its own setting**: the scroll's red glow (Grudgekeeper's, the default) or a
  raid warning in the middle of the screen (Guild Grudge's). It applies to every warning, Grudgekeeper's
  own "is near" included.
- **D14. `/gg` is an alias of `/grudge`**, kept for Guild Grudge players' habits. It is registered only
  when Guild Grudge itself is not loaded, so the two never fight over it.
- **D15. A one-time import from Guild Grudge.** When both addons are enabled, Grudgekeeper reads
  `GuildGrudgeDB` once per guild and takes over its notes, lists, tags, nice names and votes. Bounties and
  claims are not imported (D4). Afterwards the player disables Guild Grudge. The import waits while the
  test panel is open, and in a guild until the client has said which one (a few tries, then it gives up
  quietly and tries again at the next login); the guildless store is used only without a guild. An imported
  note's id comes from the note itself (`ts * 100` plus a number from its own id, else from its text), so
  every client gives the same note the same id.
- **D16. A separate addon-message prefix, `GrudgeNotes`.** The notes travel on their own prefix with
  their own small protocol. Grudgekeeper's protocol and Guild.lua are not touched, and an old
  Grudgekeeper client ignores the new messages completely. See Q3.
- **D17. Tests.** A Lua 5.1 test harness (`tests/`) runs the data layer outside the game. It is not
  packaged (`.pkgmeta` ignores `tests/`). See Q5.
- **D18. The four lists are four tabs, in two groups.** The enemy's pages sit over the left page in the
  open book - the owner's three, **Marked**, and News: Kill orders, Leaderboard, Grudges, Marked, News - and
  the friendly ones (**Shame**, **Kudos**, **Names**) over the right page. Marked is for an enemy you want to mark without a bounty or a
  history, e.g. a colleague on Horde. (This was Q7, "one Notes tab with a switch, or elsewhere?"; the
  owner tried it in the game and asked for tabs.) Folded, the row shows the active page's group plus a last tab, Friends or Enemies, that switches to the other group.

## Questions for the owner

- **Q1. Same-faction players: in scope?** Today: yes, for notes, Shame, Kudos and Names (D3); kill
  orders stay enemy-only. If no: the menu entries and tooltip line on friendly players go, and Shame,
  Kudos and Names become enemy-only or are removed.
- **Q2. Notes from players who are offline or left the guild.** Under D2 a guildie who installs the addon
  next week never sees a note whose author has stopped playing, because nobody else re-sends it. Today:
  D2 as is. The alternative is that any client answers a sync with everything it knows, as Guild Grudge
  did, trusting relayed data.
- **Q3. One prefix or two?** Today the notes use `GrudgeNotes` (D16). They could move onto `Grudgekeeper`
  with new message letters (N, L, V, M, G, H and Q are free there except Q, which would need a sub-type).
  Two prefixes means two receive budgets of 30 messages per 10 seconds per sender.
- **Q4. The Classic look: accept it?** Today it is a setting that replaces every surface (D12). If no:
  delete the `Classic/` folder and its TOC lines, and the `look` setting in Options. Nothing else depends
  on it.
- **Q5. The test harness: wanted in this repo?** If no: delete `tests/`.
- **Q6. Who counts as an officer** for hiding names? Today: the guild master, and any rank that can listen
  to officer chat (`C_GuildInfo.GuildControlGetRankFlags`, flag 3), checked against the sender's rank in
  the roster when the message arrives. If that call isn't there, only the guild master.

## What lives where

| File | New or changed | What |
|---|---|---|
| `Notes.lua` | new | The data and the wire: people, notes, marks, tags, votes, nice names, hides, the `GrudgeNotes` protocol, queries for pages, cards and the tooltip. No frames. |
| `NotesUI.lua` | new | The ledger look for the notes: the four list pages, the note sheet, right-click menu entries, card lines, tooltip lines, nameplate marks, group-join and nearby warnings, settings, slash commands and `/gg`. |
| `Import.lua` | new | The one-time import from `GuildGrudgeDB` (D15). |
| `Classic/*.lua` | new | The Classic look (D12). |
| `tests/` | new | The test harness (D17). |
| `Window.lua`, `Profile.lua`, `Options.lua`, `Core.lua`, `Letters.lua`, `Post.lua`, `Notice.lua` | changed | Small hooks only, listed below. |

## Hooks into existing files

Every hook is small and named here, so a merge conflict is easy to resolve by redoing it.

- **H1. Window.lua: a page registry.** `TABS`, `PAGES` and `HEADINGS` become one list of page
  definitions, `GK.LedgerPages`, each `{ name, items = fn, headings, sub = fn, links = fn, sortable,
  side, default = fn }`. `side = "right"` puts the page's tab over the right page in the open book (D18);
  `Layout` fits each of the two groups of tabs to its own span (the left group to the left page, the
  right group from the right page's left edge to the top-right iron), one font size per group. A page
  with both `links` and `sub` shows the sub text after the links, on their line. The four existing pages move into it unchanged in behaviour; the leaderboard's
  This week / All time links become its `links`. `GK.AddLedgerPage(def)` adds a page before the book
  is built: after the others, or in front of the page named by `def.before` (Marked uses `before = "News"`).
  Only `GK.OpenWindow(1)` and `(2)` are used by number, so a page at 4 moves nothing; `GK.OpenNotes(list)`
  finds its page by the def's `list` field. The Classic window reads the same list.
- **H2. Window.lua: a generic card.** `DetailCard` also accepts `{ kind = "card", make = fn }`, where `make`
  returns a card table in Profile.lua's shape.
- **H3. Window.lua: sort and mine only.** `Refresh` passes each page's items through `GK.SortItems(items,
  page)`, which applies the sort mode and Mine only for pages with `sortable = true`. The control is
  Blizzard's own, so it looks clickable: one `WowStyle1DropdownTemplate` dropdown on the title row,
  right-aligned with the column headings (radios for Default, Newest, Oldest, A-Z and Votes, then a divider
  and a "Mine only" checkbox; its text "Sort: Newest", or "Sort: Newest, mine" while Mine only is on). It is
  hidden on pages that are not sortable. Item tables gain two
  optional fields, `ts` (a time to sort by) and `votes` (a score), and `mine` is set on more rows.
- **H4. Profile.lua: show any card.** `GK.ShowCard(make)` opens the small card for a card table that
  `make()` builds, and refills it the same way as the poster and the record.
- **H5. Options.lua: extra sections.** `GK.OptionSections` is a list of functions; `Build` calls each one
  before the Commands section, passing its own `Section`, `Check` and `Box` helpers and the anchor to
  build under.
- **H6. Letters.lua and Post.lua: content apart from drawing**, so the Classic look can show the same
  letter and the same sheet. As built:
  - `Letters.lua`: `GK.LetterContent(L)` sits right after `NoteContent` and returns `{ note (a small letter,
    else the scroll), title, name, info, lines, foot, seal, stamp, blood, buttons = { { text, fn } }, c,
    rf, sx, key, sample }`. It calls the existing `ScrollContent` and `NoteContent`, which are untouched, and
    takes over from `FillNote` the closing line (after a blank line, only on a letter of four paragraphs or
    fewer). `FillScroll` and `FillNote` now draw from it; the text they set is the same, character for
    character.
  - `Post.lua`: `GK.PostPlan(t)` returns `{ case = "new" | "change" | "pot", pot, mine, title, bounty,
    small, button, amount, note, asksWhy }`, and `GK.PostSubmit(t, copper, note, plan)` adds to the pot or
    posts the order, plays the sound and answers true (false, with the reason in chat, when the order was
    refused). `GK.OpenPost` fills the parchment sheet from the plan, and `Seal` calls `GK.PostSubmit` with the
    plan the sheet was opened with, so an order that appeared after the sheet opened changes nothing, as
    before. The module-local `pot` became `plan.pot`.
  - `Window.lua`: one line, `GK.LedgerCard = DetailCard`, so the Classic window shows the same card the book
    does for a row (record, poster or card).
- **H7. Wrapped functions.** Some features wrap a `GK.*` function at load time rather than editing it:
  `GK.PosterCard` and `GK.RecordCard` (notes on the card), `GK.TooltipLine` (notes on an enemy's tooltip),
  `GK.Warn` (alert style, D13), `SlashCmdList.GRUDGEKEEPER` (the new subcommands; anything it does not know
  goes to the original, whose help gets our lines below it), `GK.ImportGuildGrudge` (tells the guild what the
  import made, through `GK.NotesBroadcast`). The Classic look wraps, at
  `PLAYER_LOGIN` so that its wrappers are the outermost: `GK.OpenWindow`, `GK.ToggleWindow`, `GK.ShowPoster`,
  `GK.ShowRecord`, `GK.ShowCard`, `GK.OpenLetters`, `GK.ShowLetter`, `GK.CloseLetters`, `GK.NoticeUpdate`,
  `GK.PlaceNotice`, `GK.Warn`, `GK.OpenPost`, `GK.OpenNoteSheet` (only if it exists then), and
  `SlashCmdList.GRUDGEKEEPER` (for `/grudge classic`). `GK.BuildCardPage` and `GK.FillCardPage` (the Inspect
  tab's page) are wrapped to serve both looks. Each wrapper calls the original whenever `GK.db.look` is
  `"ledger"`; with `GK.db.alertStyle == "raid"` the classic `GK.Warn` leaves the warning to the original chain.

- **H8. Core.lua: defaults.** Six new settings in `defaults` (`noteAlerts`, `watchNearby`,
  `watchGroup`, `kudosGroup`, `plateNotes`, `alertStyle`), and `Grudgekeeper.toc` lists `NotesUI.lua`
  after `Profile.lua`. Their checkboxes are one section in the settings page, added through H5.

## The Classic look (D12, Q4)

`GK.db.look` is `"ledger"` (default) or `"classic"`; Options has a "Look" section with the checkbox, and
`/grudge classic` toggles it. Changing it hides every open frame of the look that goes. The only edits
outside `Classic/` are H6 above, `look = "ledger"` in the defaults in `Core.lua`, and the six TOC lines
after `Options.lua`.

| File | What |
|---|---|
| `Classic/Classic.lua` | The setting, `GK.IsClassic()`, the wrapping (`C.Wraps`, `C.Always`), `/grudge classic`, and the shared pieces: `C.Frame` (a `ButtonFrameTemplate` frame), `C.Face` (a round portrait with a class badge), `C.Button`, `C.Tip`, `C.FormatLines`. |
| `Classic/Cards.lua` | `C.CardView`, which draws any card table (title, name, info, big and caption, lines, up to two buttons); the small card that `GK.ShowPoster`, `GK.ShowRecord` and `GK.ShowCard` open; the Inspect tab's page. |
| `Classic/Window.lua` | The window as Guild Grudge's is made: tabs from `GK.LedgerPages` (the pages with `side = "right"` in a group on the right, the rest on the left), search box (name and sub line), a sort menu and Mine only on the sortable pages (`GK.db.sortMode`, `GK.db.mineOnly`), the page's links and sub line in a strip under the toolbar, a scrolling list and the chosen row's card in a panel. It reads each page's `items()`, passes them through `GK.SortItems`, and gets the card from `GK.LedgerCard`, with the ledger's rule for which row is chosen (`page.default`), applied to the rows the search leaves: the chosen row stays only while it matches, and with no match there is no card. |
| `Classic/Letters.lua` | The pile in one standard frame, drawn from `GK.LetterContent`, with a pager. The letter on show is tracked by its id; if it drops out of the pile, the one in its place is shown the ordinary way (and so read). |
| `Classic/Notice.lua` | The letter icon: an envelope button with the unread count, draggable (`GK.db.classicNotice`), blinking when a letter lands. A warning is a red glow and a line of chat. The parchment notice stays hidden. |
| `Classic/Sheets.lua` | The kill order sheet (from `GK.PostPlan`, sealing through `GK.PostSubmit`) and the note sheet (`GK.OpenNoteSheet(t, list)`: a tag box with a menu of `GK.KnownTags(list)`, a note, saved with `GK.WriteNote` like the ledger's sheet, so a list alone is a mark too). |

Known gaps:

- **What it looks like has not been seen in the game.** The code is written against Blizzard's templates as
  they are in retail (`ButtonFrameTemplate`, `PanelTabButtonTemplate`, `SearchBoxTemplate`,
  `WowStyle1DropdownTemplate`, `WowScrollBoxList`) and built in the tests against stand-in frames. Sizes and
  spacing will want a pass in the game.
- **No vote arrows on the Classic cards.** Guild Grudge's vote control (arrows and score) is not drawn: a
  card table is plain lines of text and has no field for a vote, so notes show as text on the card. Votes
  still work wherever the notes page offers them; a field on the card for a vote would let `C.CardView` draw the arrows.
- **The ledger's own frames are named from a list**, `C.LedgerFrames` in `Classic/Classic.lua`, to hide them
  when the look changes. The note sheet of the ledger is listed as `GrudgekeeperNoteSheet`; a ledger frame
  with another name is not hidden until it is added there.
- **A letter read through the Classic pager does not clear its minute's hold** (the ledger's `ShowLetter`
  does `holding[L] = nil`, which is local to Letters.lua). When the minute ends, the icon blinks once for a
  letter that is already read; nothing else is affected.
- **Position and size of the Classic frames are not remembered**, apart from the letter icon. The ledger
  uses `LIB.RegisterWindow` for that; the Classic frames open at the middle of the screen.
- **The Inspect page is covered, not rebuilt.** The ledger's page is built as ever and hidden under a
  Classic card with its own background while the look is classic; switching the look with the Inspect window
  open takes effect at its next update. A page that was built before the wrappers went on gets its cover
  the first time it is filled.
- **`C.Apply` runs once.** A second call does nothing, so the wrappers never stack.

## What the list pages show

- Four pages, one per list (D18): Marked, Shame, Kudos and Names. `GK.OpenNotes(list)` opens the
  right one, and `/grudge notes` (Marked), `/grudge shame`, `/grudge kudos` and `/grudge names`
  with no name do the same. A row is a player (or a name) with their face, tags and newest note, and the
  score on the right. Every page is sortable and has its own headings and empty text, but no links: the
  list is the tab. The count line is the page's `sub`.
- A click opens a card on the right page: for a player, who put them on which list (with tags), up to five
  notes as `"text" - Author, 3 days ago (+2)`, the score, and Add a note / More... (move or remove my mark,
  vote on a note, delete one of mine, open the wanted poster for an enemy; every note can be reached: past
  ten they are split into submenus "Notes 1-10", "Notes 11-20" and so on). For a nice name, who added it
  and the score, with Vote up (Take back once voted) and More... (Vote down, Remove for my own, and Hide /
  Show for everyone for officers).
- The wanted poster and the record get up to two lines of their own about notes, never past nine lines.
- The note sheet (`GK.OpenNoteSheet`) is one parchment: the list as three ink links, the tags of that list
  as ink links, a box for your own tag, and a box for up to 200 letters. A list alone, or a tag alone, is
  enough to write.

## Data

Kept in the guild's store (`GK.Store()`), next to the orders, so each guild has its own:

```
store.people[key] = {
  n = key, c = classFile, r = race, rf = raceFile, sx = sex, l = level,   -- learned from a unit, or sent
  marks = { [author] = { list = "kos" | "watch" | "kudos", ts, del } },
  notes = { [author] = { [id] = { text, tag, ts, del } } },
  votes = { [author .. "#" .. id] = { [voter] = { v = 1 | -1 | 0, ts } } },
}
store.names[key] = { by, ts, del, c, r, rf, sx, l, hidden = { by, ts, on } }
store.nameVotes[key] = { [voter] = { v, ts } }
```

- `key` is Grudgekeeper's player key (`LIB.UnitKey`, `GK.KeyOf`): "First Surname-Realm".
- `author` and `voter` are always the sender of the message, never a field in it (D2).
- Every record is last-writer-wins by `ts` (the author's `time()`), per author and id. A delete is a
  record with `del = true`, kept 30 days so a late sync can't bring the note back, then pruned.
- A player is on a list when any author's live mark puts them there. A note without a mark counts as
  "kos" for its author. A removed mark is kept past its 30 days for as long as its author has a live note
  on the player, so the player does not fall back onto Marked; it is pruned once no live note remains.
- Limits: 200 characters per note, 24 per tag, 20 live notes per author per player, 40 note ids per author
  per player (deleted ones count), 5000 note ids in the whole store, 500 people, 300 names. A new note id
  that doesn't fit makes room by dropping the oldest deletion record older than 30 days; if there is none
  it is refused. The same goes for a new person at 500: only someone whose every record (mark, note, vote)
  is a deletion or vote older than 30 days is forgotten, otherwise the new person is refused.
- A nice name belongs to whoever added it first. When two players added the same name before hearing of
  each other, the earliest `ts` is the owner and, at the same second, the lower key; every client
  settles on the same one whatever order the messages came in. A later `M` from the other player is
  ignored, and only the owner's removal counts.
- Hide and show are ordered by `ts`, then by the officer's key (the higher key wins a tie).
- A vote that arrives before the player or the nice name it is about is held (at most 200, for 10
  minutes, in memory only) and applied when that player or name arrives.

## Wire: the `GrudgeNotes` prefix

Fields are separated by `;`; every text goes through `GK.Clean`, which turns `;` into `,`. As in
Guild.lua, a field added later goes on the end, so an older client reads what it knows and ignores the
rest. The second field is the protocol version, `1`.

```
N;1;key;id;ts;del;tag;c;r;l;text        my note (del: 1 or empty)
L;1;key;list;ts;del;c;r;l               my mark: which list I put them on
V;1;key;author;id;v;ts                  my vote on author's note id (v: 1, -1 or 0 to take it back)
M;1;key;ts;del;c;r;rf;sx;l              my nice name
G;1;key;v;ts                            my vote on a nice name
H;1;key;on;ts                           I hide (1) or show (0) a nice name - officers only (Q6)
Q;1                                     tell me yours (at login)
```

- Note ids run from 1 to 2^40: a note written here uses the time, an imported one `ts * 100` plus a small
  number (see Import.lua).
- On Q, a client answers after 2-6 seconds, at most once per 30 seconds, with its own records only,
  newest first, at most 150.
- Everything sent on the prefix - live changes, the answer to a Q, the broadcast after an import - goes
  through one outbound queue, at most 2 messages a second in total, so we stay inside LibForever's
  receive budget (30 per sender per 10 seconds) however many things are going on. A broadcast asked for
  while another is still waiting is merged into it. Each entry remembers `LIB.GuildKey()` from when it was
  queued and is dropped at send time if the guild is another by then; the queue is also cleared on
  `GUILD_ROSTER_UPDATE` / `PLAYER_GUILD_UPDATE` when the guild key changed. Nothing is sent while
  `GK.testMode` is on, or outside a guild; both are checked again at send time.
- A vote on an imported note is never sent, live or in a reply (that id is only ours).
- After the import (D15) the same reply goes out unasked, once (`GK.NotesBroadcast`): the notes it made as
  mine are news to everyone else.

## Testing

- `tests/run.lua` runs with Lua 5.1: `lua5.1 tests/run.lua` from the repo root. It loads `Notes.lua` and
  `Import.lua` against a small mock of the WoW API and LibForever (`tests/wow_mock.lua`). It also loads
  `Letters.lua` and `Post.lua` to test `GK.LetterContent`, `GK.PostPlan` and `GK.PostSubmit`, and the
  `Classic/` files against permissive stand-in frames (`tests/frames_mock.lua`), which build and click
  through the window, cards, letters, icon and sheets.
  With
  `boot({ ui = true })` it also loads `NotesUI.lua`, against stand-ins for the files that one builds on
  (`tests/ui_mock.lua`); the code that makes frames (the note sheet, the nameplate marks, the settings
  section) is not run there, only what it calls.
- In game, the PR was tried as a renamed copy (own saved variables, own prefixes, own slash command) so
  nothing reached the guild's real clients.
