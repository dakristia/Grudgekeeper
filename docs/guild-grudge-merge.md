# Guild Grudge merged into Grudgekeeper

This document is for the owner of Grudgekeeper and for any AI agent that reviews or continues this work.
It says what came over from Guild Grudge, every design choice and why, the questions still open, and
exactly where the new code touches Grudgekeeper's own files.

Guild Grudge (github.com/dakristia/GuildGrudge, v0.8.0) was a guild notebook on players: free-text
notes, a Watch list for same-faction players to be careful with, a Kudos list for good players, a list
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
- **D3. Same-faction players are in scope for notes**, Watch, Kudos and Names. Guild Grudge was built
  for same-faction use (ninja looters, scammers, good healers). Kill orders stay enemy-only. See Q1.
- **D4. No kill orders on same-faction players.** Guild Grudge allowed bounties on anyone while there
  were few Horde players to test on. That stops here.
- **D5. Three lists, one mark per author.** A player can be on "Kill on sight", "Watch" or "Kudos". The
  list is each author's own mark: if Kari puts someone on Watch and Edvard gives them Kudos, they show on
  both lists, each with who put them there. Moving a player only moves your own mark.
- **D6. Tags.** A note can carry one tag. Watch has preset tags (Ninja looter, Scammer, Toxic, Griefer,
  Leaver), Kudos has its own (Helpful, Kind, Skilled, Great healer, Great tank, Fair looter, Fun to group
  with), and a player can type a custom one (at most 24 characters).
- **D7. Nice names.** A guild-shared list of funny character names, with no notes, alerts or orders.
  Only the player who added a name can remove it (D2). The guild master and officers can **hide** a name
  for everyone, for cleanup; a hidden name is still in the data and can be shown again. See Q6.
- **D8. Votes.** Notes and nice names can be voted up or down, one vote per player, which they can change
  or take back. You can't vote on your own note or name.
- **D9. Sorting and Mine only.** Newest, oldest, A-Z and most votes, on the pages where an order makes
  sense (kill orders, grudges, news, notes). The leaderboard keeps its rank order. "Mine only" keeps the
  rows you wrote, posted, took, fulfilled or voted on.
- **D10. Noted players are highlighted quietly, and alert only if asked.** A player with notes and no
  kill order gets a small, dim mark on their nameplate and a tooltip line. They raise the "is near"
  warning only when a setting turns that on (off by default).
- **D11. Group-join warnings.** When someone on your Watch list joins your group you get a warning, the
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
  claims are not imported (D4). Afterwards the player disables Guild Grudge.
- **D16. A separate addon-message prefix, `GrudgeNotes`.** The notes travel on their own prefix with
  their own small protocol. Grudgekeeper's protocol and Guild.lua are not touched, and an old
  Grudgekeeper client ignores the new messages completely. See Q3.
- **D17. Tests.** A Lua 5.1 test harness (`tests/`) runs the data layer outside the game. It is not
  packaged (`.pkgmeta` ignores `tests/`). See Q5.

## Questions for the owner

- **Q1. Same-faction players: in scope?** Today: yes, for notes, Watch, Kudos and Names (D3); kill
  orders stay enemy-only. If no: the menu entries and tooltip line on friendly players go, and Watch,
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
- **Q7. The Notes tab.** The ledger has four tabs. This PR adds a fifth, **Notes**, whose page has ink links
  like the leaderboard's week switch: Kill on sight / Watch / Kudos / Names. Is one tab with a switch
  right, or would the owner rather have the lists elsewhere?

## What lives where

| File | New or changed | What |
|---|---|---|
| `Notes.lua` | new | The data and the wire: people, notes, marks, tags, votes, nice names, hides, the `GrudgeNotes` protocol, queries for pages, cards and the tooltip. No frames. |
| `NotesUI.lua` | new | The ledger look for the notes: the Notes page, the note sheet, right-click menu entries, card lines, tooltip lines, nameplate marks, group-join and nearby warnings, settings, slash commands and `/gg`. |
| `Import.lua` | new | The one-time import from `GuildGrudgeDB` (D15). |
| `Classic/*.lua` | new | The Classic look (D12). |
| `tests/` | new | The test harness (D17). |
| `Window.lua`, `Profile.lua`, `Options.lua`, `Core.lua`, `Letters.lua`, `Post.lua`, `Notice.lua` | changed | Small hooks only, listed below. |

## Hooks into existing files

Every hook is small and named here, so a merge conflict is easy to resolve by redoing it.

- **H1. Window.lua: a page registry.** `TABS`, `PAGES` and `HEADINGS` become one list of page
  definitions, `GK.LedgerPages`, each `{ name, items = fn, headings, sub = fn, links = fn, sortable,
  default = fn }`. The four existing pages move into it unchanged in behaviour; the leaderboard's
  This week / All time links become its `links`. `GK.AddLedgerPage(def)` appends a page before the book
  is built. The Classic window reads the same list.
- **H2. Window.lua: a generic card.** `DetailCard` also accepts `{ kind = "card", make = fn }`, where `make`
  returns a card table in Profile.lua's shape.
- **H3. Window.lua: sort and mine only.** `Refresh` passes each page's items through `GK.SortItems(items,
  page)`, which applies the sort mode and Mine only for pages with `sortable = true`. Item tables gain two
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
  `GK.Warn` (alert style, D13), `SlashCmdList.GRUDGEKEEPER` (the new subcommands). The Classic look wraps, at
  `PLAYER_LOGIN` so that its wrappers are the outermost: `GK.OpenWindow`, `GK.ToggleWindow`, `GK.ShowPoster`,
  `GK.ShowRecord`, `GK.ShowCard`, `GK.OpenLetters`, `GK.ShowLetter`, `GK.CloseLetters`, `GK.NoticeUpdate`,
  `GK.PlaceNotice`, `GK.Warn`, `GK.OpenPost`, `GK.OpenNoteSheet` (only if it exists then), and
  `SlashCmdList.GRUDGEKEEPER` (for `/grudge classic`). `GK.BuildCardPage` and `GK.FillCardPage` (the Inspect
  tab's page) are wrapped to serve both looks. Each wrapper calls the original whenever `GK.db.look` is
  `"ledger"`; with `GK.db.alertStyle == "raid"` the classic `GK.Warn` leaves the warning to the original chain.

## The Classic look (D12, Q4)

`GK.db.look` is `"ledger"` (default) or `"classic"`; Options has a "Look" section with the checkbox, and
`/grudge classic` toggles it. Changing it hides every open frame of the look that goes. The only edits
outside `Classic/` are H6 above, `look = "ledger"` in the defaults in `Core.lua`, and the six TOC lines
after `Options.lua`.

| File | What |
|---|---|
| `Classic/Classic.lua` | The setting, `GK.IsClassic()`, the wrapping (`C.Wraps`, `C.Always`), `/grudge classic`, and the shared pieces: `C.Frame` (a `ButtonFrameTemplate` frame), `C.Face` (a round portrait with a class badge), `C.Button`, `C.Tip`, `C.FormatLines`. |
| `Classic/Cards.lua` | `C.CardView`, which draws any card table (title, name, info, big and caption, lines, up to two buttons); the small card that `GK.ShowPoster`, `GK.ShowRecord` and `GK.ShowCard` open; the Inspect tab's page. |
| `Classic/Window.lua` | The window as Guild Grudge's is made: tabs from `GK.LedgerPages` (the first four on the left, any added after them on the right), search box (name and sub line), a sort menu and Mine only on the sortable pages (`GK.db.sortMode`, `GK.db.mineOnly`), the page's links and sub line in a strip under the toolbar, a scrolling list and the chosen row's card in a panel. It reads each page's `items()`, passes them through `GK.SortItems`, and gets the card from `GK.LedgerCard`, with the ledger's rule for which row is chosen (`page.default`). |
| `Classic/Letters.lua` | The pile in one standard frame, drawn from `GK.LetterContent`, with a pager. |
| `Classic/Notice.lua` | The letter icon: an envelope button with the unread count, draggable (`GK.db.classicNotice`), blinking when a letter lands. A warning is a red glow and a line of chat. The parchment notice stays hidden. |
| `Classic/Sheets.lua` | The kill order sheet (from `GK.PostPlan`, sealing through `GK.PostSubmit`) and the note sheet (`GK.OpenNoteSheet(t, list)`: a tag box with a menu of `GK.KnownTags(list)`, a note, saved with `GK.AddNote`). |

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
  open takes effect at its next update.

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
  "kos" for its author.
- Limits: 200 characters per note, 24 per tag, 20 live notes per author per player, 500 people, 300 names.

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

- On Q, a client answers after 2-6 seconds, at most once per 30 seconds, with its own records only,
  newest first, at most 150, paced to 2 messages a second so it stays inside LibForever's receive budget
  (30 per sender per 10 seconds).
- Live changes go out at once. Nothing is sent while `GK.testMode` is on, or outside a guild.

## Testing

- `tests/run.lua` runs with Lua 5.1: `lua5.1 tests/run.lua` from the repo root. It loads `Notes.lua` and
  `Import.lua` against a small mock of the WoW API and LibForever (`tests/wow_mock.lua`). It also loads
  `Letters.lua` and `Post.lua` to test `GK.LetterContent`, `GK.PostPlan` and `GK.PostSubmit`, and the
  `Classic/` files against permissive stand-in frames (`tests/frames_mock.lua`), which build and click
  through the window, cards, letters, icon and sheets.
- In game, the PR was tried as a renamed copy (own saved variables, own prefixes, own slash command) so
  nothing reached the guild's real clients.
