# Museum Tycoon: Lost Treasures — Design & Technical Plan

## 1. Honest assessment

**Strengths.** The concept fuses three proven Roblox loops — plot tycoon (visible growth), collect-a-thon (rarity, sets, journal) and social show-off (visiting, trading) — under a theme with real identity. The key insight is that *items are both currency and decoration*: a find can be sold, displayed for income, traded, or kept for a set. That one decision gives every search a meaningful choice.

**Biggest opportunities.**
- *The museum is the profile.* Visiting someone's museum is a richer status signal than a number on a leaderboard. Make museums easy to browse (directory board, Visit menu — both done).
- *Exploration secrets.* Puzzles and hidden rooms (the glyph puzzle and hidden chamber are in) create word-of-mouth ("did you find the secret door?").
- *Trading economy.* Unique item instances + collection sets create organic demand for specific items — the strongest long-term retention driver, if it's secure.

**Biggest risks.** (1) Item duplication through trading/persistence bugs — fatal for an economy game. (2) A thin content treadmill after the first zone. (3) Players overwhelmed on minute one. The architecture below is designed around these three.

## 2. Core loop (as built)

1. Spawn in your front yard → GOAL banner tells you the next step.
2. Place exhibits (press E on a display) → income accumulates at the Ticket Desk.
3. Collect earnings → build upgrades on green pads (visible construction).
4. Travel to the Forgotten Ruins → search sites (server-timed progress bar).
5. Discover items (or scrap cash) → journal + collection progress.
6. Return → display, sell (60% of value), lock, or keep for sets.
7. Better displays + variety → more income → bigger museum → higher level → better tools and future zones.

Every search pays something; every display raises prestige; every new item type fills the journal — so the loop is rewarding even without a rare drop.

## 3. Progression

| Level | Name | Unlocked by | Cost |
|---|---|---|---|
| 1 | Small Collector's Museum | start (3 slots) | — |
| 2 | Expanded Exhibition Hall | East Gallery | $1,200 |
| 3 | Natural History Museum | Fossil Hall | $4,000 |
| 4 | Historical Museum | Ancient History Wing | $9,000 |
| 5 | Grand Art Gallery | Grand Gallery | $25,000 |
| 6 | World-Class Treasure Museum | Treasure Vault (+Security) | $60,000 |

Side upgrades: Grand Entrance (+5%), Glass Cases (+2 slots), Benches & Greenery (+10%), Chandeliers (+10%), Security System (unlocks Legendary/Mythic display), Golden Facade & Fountain (+15%).

Tools: Trowel (4.0s) → Brush Kit $500 (3.2s, ×1.15 luck) → Field Detector $3,000, Lv2 (2.5s, ×1.3, reveals Buried Caches) → Archaeo-Scanner $15,000, Lv3 (1.8s, ×1.5).

Prestige = Σ rarity points of every *distinct* item discovered + displayed item points + set bonuses + 10 per level. Titles from "Hobby Collector" to "Legendary Collector".

## 4. Economy

**Sources:** ticket desk income, NPC selling (60% of value), scrap from searches, set rewards (one-time).
**Sinks:** upgrades ($149,550 total), tools ($18.5k total), future: listing fees, travel costs.

**Income per minute** = Σ item income (2nd+ copy of the same item ×0.5) × (1 + variety) × (1 + decor) × (1 + 0.1·(level−1)) × (1 + min(0.5, prestige/1000)).
Variety = +8% per extra category (cap +80%), so a diverse collection beats duplicates.

**Desk cap** = 30 minutes of income (min $250): rewards coming back, doesn't punish short sessions, prevents AFK farming forever.

**Discovery weights:** Common 55 / Uncommon 27 / Rare 12 / Epic 4.5 / Legendary 1.2 / Mythic 0.3. Rare+ weights are multiplied by site type (Rubble 0.9 … Hidden Alcove 2.6) and tool luck. About 1 in 6 dig-site searches with the starter trowel is Rare or better (more in chests and the hidden chamber) — exciting without absurd odds.

**Why NPC sale is only 60%:** keeps the future player marketplace attractive — sellers get more from players, buyers pay less than NPC-acquisition would cost in time.

All numbers live in `Config.luau`, `ItemCatalog.luau`, `Upgrades.luau`, `Equipment.luau`.

## 5. Architecture & how systems talk

```
Client (LocalScript + UI modules)            Server (authoritative)
  buttons / ProximityPrompts                   Net.Handle (rate limit, ready check, pcall)
        │  RemoteFunction (request only)  ──►    MuseumService / InventoryService / ...
        │                                          │ validates ownership, distance, cash
        │                                          ▼
        │                                     EconomyService (only cash writer)
        │                                     InventoryService (only item writer)
        │                                     PlayerDataService (only DataStore user)
        ◄── StateUpdated (snapshot, batched) ── StateSync (+ providers: income, prestige…)
        ◄── Notify / Discovery / SearchStarted / OpenPlacement / ZoneChanged
```

Rules that keep it safe and maintainable:
- One writer per kind of data (cash, items, saves). No duplicate systems.
- Clients never send amounts, prices, rarities or results — only *intent* ("buy upgrade X", "place item U in slot S").
- ProximityPrompt `Triggered` and part `Touched` fire on the server, so searches and pads can't be faked; the server re-checks distance anyway.
- Searches are server-timed (`task.delay`) and re-check distance at the end.
- Item **definitions** (ItemCatalog) vs item **instances** (`{Uid=GUID, Id, Found, Zone, Locked}` in the owner's Inventory). Displays store only Uids → placing/removing can never duplicate.

## 6. Persistence design

Document per player: `{ Data, Lock = {JobId, Time}, SavedAt }` in `MuseumTycoon_PlayerData_v1`.

- **Load:** `UpdateAsync` takes the lock if it's free, ours, or stale (>180 s). If another live server holds it, wait 5 s and retry (8 attempts), then kick with "rejoin" — never load a blank profile.
- **Failure:** DataStore errors → retries with backoff → kick. A blank template is created **only** when the key genuinely has no data.
- **Save:** `UpdateAsync` refuses to write if another server now owns the lock (the player is kicked from this server instead of overwriting newer data).
- **Autosave** every 60 s (also refreshes the lock), save+release on leave, `BindToClose` saves everyone (25 s budget).
- **Same-server rejoin** waits for the release to finish before loading.
- **Versioning:** `Version` field + `migrations[n]` functions; data from a *newer* game version is never touched.

## 7. Trading & marketplace design (next stages)

**Direct trade (same server).** Both profiles are session-locked in this server, so the swap itself is an in-memory operation:
1. `TradeService` session: `Pending → Open → Locked(A,B) → Confirmed(A,B) → Executing → Done/Cancelled`.
2. Items offered are **reserved** (`item.ReservedBy = tradeId`), blocking sell/display/other trades.
3. Any offer change clears both locks/confirmations. Leaving, timeout (2 min) or ineligibility cancels and releases reservations.
4. Execute: re-validate everything, move instances (same Uid, new owner), move cash, append `tradeId` to both profiles' `RecentTrades`, then `SaveNow` both.
**Remaining risk:** a server crash *between* the two saves can leave one side saved and the other not. Mitigation: write a `TradeLog` entry (tradeId → full transfer) to a separate DataStore *before* saving profiles; on next load, any profile whose `RecentTrades` lacks a logged tradeId has the transfer replayed or rolled back idempotently. This is documented as a known limitation until implemented.

**Marketplace (cross-server).** Listing moves the item into an **escrow** record in a `Marketplace` DataStore (item leaves the seller's inventory → can't be double-sold), indexed via MemoryStoreService sorted maps for browsing. Purchase = `UpdateAsync` on the escrow record to atomically flip `Status: Listed → Sold(buyerId)` *before* moving money/items; the buyer's server credits the item; the seller is paid on their next load via a `PendingPayouts` record (claimed idempotently by listing id). Buying your own listing is refused. 5% listing fee as a sink.

## 8. Explorer hierarchy (runtime)

```
Workspace
  World/Hub (island, plaza, portal, directory board, HubSpawn)
  World/ForgottenRuins (ground, pillars, Temple, HiddenChamber, Cave, sites, ArrivalPoint, ReturnPortal)
  Plots/Plot_1..8 (Ground, OwnerSign, Museum/{Base, Upgrades, Slots, Barriers, Pads, Visitors})
ReplicatedStorage/Shared (modules), ReplicatedStorage/Remotes (created at runtime), [optional] ReplicatedStorage/ItemModels
ServerScriptService/Server (Main, Services, Util, World)
StarterPlayer/StarterPlayerScripts/Client (Main, ClientState, ClientNet, UI, Controllers)
```

## 9. Roadmap (dependency order)

1. ✅ **MVP** — plots, upgrades, ruins, searching, inventory, displays, revenue, saving.
2. ✅ **Depth** — journal & sets, prestige, tools, visiting, directory, leaderboard.
3. **Play-test & balance pass** (you: run Part 4 tests, report errors and how the pacing feels).
4. **Real art** — replace placeholder item models (`ReplicatedStorage/ItemModels`), museum facade, sounds, animations for searching.
5. **Direct trading** — needs reservations (`ReservedBy`) added to items first; then TradeService + trade UI + TradeLog recovery.
6. **Marketplace** — needs escrow + MemoryStore indexing; built after trading so reservation logic is shared.
7. **Zone 2: Ancient Egyptian Tombs** (Level 3) — new items in ItemCatalog, a ZoneBuilder, new puzzle type.
8. Daily objectives, more sets, cosmetics.
9. **Monetization** (cosmetic only, idempotent `ProcessReceipt` with a receipts DataStore).

## 10. Early decisions already locked in (to avoid rebuilds)

- Item instances with GUIDs from day one (required for trading).
- One cash writer, one item writer, one save writer.
- All content as data tables (items, upgrades, zones, sets) — new content = new rows.
- Session-locked UpdateAsync saves (not SetAsync).
- Map generated from code: identical plots, easy to re-layout; swap any builder for a Studio-made model later.
- Snapshot-based UI sync: simple, impossible for the client to desync authority.

## 11. Performance limits in place

Visitors ≤ 6 per plot and only spawn when a player is within 260 studs; no Humanoids or physics (anchored tweened parts). One search per player at a time; per-site cooldowns. Remote rate limit 6/s (burst 10). State snapshots batched per 0.1 s. Revenue tick every 5 s. 24 display slots max per museum. No per-frame server loops.

## 12. Update 2 status (implemented)

- Stages 1–4 of the update brief are implemented: improved Forgotten Ruins, the Jungle Temple, scanner + skill-based excavation with condition, clue-chain puzzles, museum security, core heists (lock → cameras → steal → escape / jail), the Collectors' Market (durable escrow with crash recovery) and direct trades (via the ledger).
- Transfers between players go through `LedgerService` (prepare → index → commit, replayed on load). Market listings are single-key compare-and-set documents (see `src/server/Core/MarketCore.luau`).
- Pure logic is covered by `tests/run_tests.luau` (19 tests).
- Deferred: heist recon/routes/guards/lasers/motion/panels, monetization, final polish pass.

## 13. Graphics & UI overhaul (implemented, not yet play-tested)

- Shared vegetation library `World/Trees.luau` (templates in ServerStorage, cloned).
- Cream/navy museum style, restrained lighting (no bloom), navy/blue UI theme with tokens, a minimal HUD with a rail and a More popover, a Settings window, and de-duplicated notifications.
- Start-up is crash-proofed (pcall per service, panel and zone).
