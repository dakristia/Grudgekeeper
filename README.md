# Grudgekeeper

World PvP score-keeping for WoW: Forever: who you killed, who killed you and how often, a guild
leaderboard, and kill orders with a bounty on them.

- `/grudge` opens the window: kill orders, the leaderboard, your grudges.
- `/grudge post` writes a kill order on your target.
- `/grudge test` puts four sample letters in your pile.
- Right-click a player and pick **Grudgekeeper profile**: a wanted poster for an enemy, the record of a
  guildie.

Forever closes the combat log to addons. Grudgekeeper counts what the client does hand over: your
killing blows (`PARTY_KILL`), the death recap, and the enemy players you can see (nameplates, target,
mouseover). Open world only - instances and battlegrounds hide who is who.

Uses LibForever-1.0 (fetched by the packager, see `.pkgmeta`). MIT licence.
