# Grudgekeeper

World PvP score-keeping for WoW: Forever: who you killed, who killed you and how often, a guild
leaderboard, and kill orders with a bounty on them.

- `/grudge` opens the window: kill orders, the leaderboard, your grudges.
- `/grudge post` writes a kill order on your target, or asks who when you have none.
- Each page of the window that you can add to has its action at the top - **Post a kill order**, **Mark
  someone**, **Put someone on Shame**, **Give someone kudos**. It asks who: your target, the enemies you met
  lately, your group and who just left it, or a name you type. Click a column heading to sort by it.
- `/grudge test` puts four sample letters in your pile.
- Right-click a player and pick **Grudgekeeper profile**: a wanted poster for an enemy, the record of a
  guildie. On an enemy, **Post a kill order** is right below it.
- Inspect a guildie and the **Grudgekeeper** tab below the game's own shows their page of the ledger.
- Right-click any player and pick **Grudgekeeper notes**: a note on them, or put them on Marked, Shame or
  Kudos with a tag. `/grudge note`, `/grudge shame` and `/grudge kudos` do the same from chat. The notes
  came from Guild Grudge, by dakristia; `/grudge import` takes over its saved notes.

Forever closes the combat log to addons. Grudgekeeper counts what the client does hand over: your
killing blows (`PARTY_KILL`), the death recap, and the enemy players you can see (nameplates, target,
mouseover). Open world only - instances and battlegrounds hide who is who.

Uses LibForever-1.0 (fetched by the packager, see `.pkgmeta`). MIT licence.
