# Grudgekeeper

World PvP score-keeping for WoW: Forever: who you killed, who killed you and how often, a guild
leaderboard, and kill orders with a bounty on them.

- `/grudge` opens the window: kill orders, the leaderboard, who has killed the guild most, your grudges.
- `/grudge post` writes a kill order on your target, or asks who when you have none.
- Each page of the window that you can add to has its action at the top - **Post a kill order**, **Put
  someone on Shame**, **Give someone kudos** - and the kill orders page's Marked heading has **mark someone**
  beside it. It asks who: your target, the enemies you met lately, your group and who just left it, or a
  name you type. Click a column heading to sort by it.
- **Track someone** at the top of your Grudges, or **Track** in the right-click menu on an enemy: your own
  list of enemies to keep an eye on, never shared. One of them near warns you and wears an eye over their
  nameplate.
- `/grudge test` puts five sample letters in your pile.
- Right-click a player and pick **Grudgekeeper profile**: a wanted poster for an enemy, the record of a
  guildie. On an enemy, **Post a kill order** is right below it, and for an officer **Watch their guild**
  when they are in one: the guild watches one enemy guild at a time, and anyone from it warns whoever
  comes across them. `/grudge guild` puts a guild on watch by its name, for one nobody has met lately.
- A grudge that is wrong goes with **Forget grudge** on that player's card (two clicks): your record of
  them, here and in the guild's lists. Your score stays.
- Inspect a guildie and the **Grudgekeeper** tab below the game's own shows their page of the ledger.
- Right-click any player and pick **Grudgekeeper notes**: a note on them, or put them on Marked, Shame or
  Kudos with a tag. `/grudge note`, `/grudge shame` and `/grudge kudos` do the same from chat. The notes
  came from Guild Grudge, by dakristia; `/grudge import` takes over its saved notes.

Forever closes the combat log to addons. Grudgekeeper counts what the client does hand over: your
group's killing blows (`PARTY_KILL`), the game's damage meter once a fight is over (for assists), the
death recap, and the enemy players you can see (nameplates, target, mouseover). Open world only - instances and battlegrounds hide who is who.

Uses LibForever-1.0 (fetched by the packager, see `.pkgmeta`). MIT licence.

The Grudgekeeper's voice calling out each kill spree tier (`Media/voice_*.mp3`) was made with
[ElevenLabs](https://elevenlabs.io).
