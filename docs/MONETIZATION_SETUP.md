# Relic Empire — Robux Shop & Fly Mode: Setup Tutorial

Everything below uses Roblox's real purchase system. **No step uses a fake purchase as proof.** Until you replace the placeholder IDs, the shop shows "Not available yet" and nothing can be bought.

## What you must fill in (the only code you edit)

File: `src/shared/Monetization.luau`

| Line (search for) | What | Where it comes from |
|---|---|---|
| `Passes.FlyMode.Id = 0` | Fly Mode **Game Pass** ID | Creator Dashboard → Monetization → Passes |
| `Products.LocksmithBundle.Id = 0` | **Developer Product** ID | Monetization → Developer Products |
| `Products.SafecrackerBundle.Id = 0` | **Developer Product** ID | Monetization → Developer Products |

| `Passes.FastWalk.Id = 0` | Fast Walk **Game Pass** ID | Monetization → Passes |
| `Passes.HighJump.Id = 0` | High Jump **Game Pass** ID | Monetization → Passes |
| `CashPacks.CashSmall / CashMedium / CashLarge` `Id = 0` | 3 cash-pack **Developer Product** IDs | Monetization → Developer Products |

Prices are set in the Dashboard, not in code. The store reads the live price from Roblox. Cash amounts per pack (`Cash = ...`) and Fast Walk / High Jump strength (`Monetization.Powers`) are editable in the same file.

**Robux Store:** press the green **+** next to your cash. It lists cash packs, the powers (Fly, Fast Walk, High Jump — owned ones get an ON/OFF switch) and the heist gear bundles. Create the Game Passes (section C) and Developer Products (section B) the same way as described below for each new ID.

---

## A. Publishing and preparation

1. **Back up first.** Copy the whole `MuseumTycoon` folder (e.g. `MuseumTycoon_backup_before_robux`). In Studio also use **File → Save to File As…** to keep a `.rbxl` copy.
2. **Publish the experience** (needed for products/passes to exist): open the project in Studio (Rojo connected), then **File → Publish to Roblox…** → choose your existing Relic Empire experience (or **Create new**). Wait for "Published".
3. **Open it in the Creator Dashboard:** go to `create.roblox.com/dashboard/creations` → click your experience.
4. **Test safely:** do NOT test on the live game. Create a second, unreleased experience (e.g. "Relic Empire TEST"): in Studio **File → Publish to Roblox As…** → Create new, keep it **Private**. Create the passes/products there first. When everything works, repeat the setup on the live experience (IDs differ per experience) and put the live IDs in the code.
   - Also make sure the test experience has **Studio Access to API Services** enabled: Studio → **Home → Game Settings → Security → Enable Studio Access to API Services**, so saving works in tests.

## B. Developer Products (repeatable bundles)

1. Creator Dashboard → your experience → left menu **Monetization → Developer Products** (older UI: **Associated Items → Developer Products**).
2. Click **Create a Developer Product** (once per product):
   - **Locksmith Bundle** — Name `Locksmith Bundle`, description (copy from the shop text), any icon, **Price** e.g. your choice in Robux (the Dashboard shows the minimum). Save.
   - **Safecracker Bundle** — same steps.
3. Open each product → copy the **Product ID** (the number in the URL or "Copy Asset ID").
4. In `src/shared/Monetization.luau` replace the `0` after `Id =` on the matching line (`LocksmithBundle`, `SafecrackerBundle`). Save; Rojo syncs it.
5. Both bundles only grant existing heist gadgets (same charges/security rules as the in-game Black Market). They don't bypass alarms, cameras, cooldowns or level requirements.

## C. Fly Mode Game Pass

1. Dashboard → your experience → **Monetization → Passes** → **Create a Pass**.
2. Upload an icon (512×512), name it `Explorer's Wings — Fly Mode`, paste the description from `Monetization.luau`, **Save**.
3. Open the pass → **Sales** (or "Price") → turn on **Item for Sale** and set the Robux price → **Save**.
4. Copy the pass **ID** (number in the URL: `.../passes/<ID>/...`).
5. Put it in `Monetization.luau` → `Passes.FlyMode.Id`.
6. The purchase prompt is opened by the **server** when the player presses the button in **Shop → Premium**. Ownership is verified by the server with `UserOwnsGamePassAsync` at join and by Roblox's `PromptGamePassPurchaseFinished` event after a purchase.

## D. Testing

**What works locally in Studio (no publish needed):** shop UI layout, tabs, "Not available yet" state, display/ruins visuals, Fly **rejection** for non-owners.

**What needs a published experience with real IDs:** price display, purchase prompts, ownership, Fly activation, receipt handling.

1. **UI:** Play (F5). Open **More → Shop → Premium**. With IDs at 0 you must see "Not available yet" and disabled buttons. Press **F** → toast "Fly Mode is a Game Pass…" and you do NOT fly. (This confirms the server rejects non-owners.)
2. **Purchase prompts:** with real IDs filled and the test experience published, Play in Studio. Click **Buy** → Roblox's prompt opens. In Studio you are the experience owner, so Roblox lets you test; read the prompt carefully. **Cancel it** and confirm nothing was granted (no toast, button still "Buy").
3. **Entitlement & Fly:** complete a real purchase in the test experience (use a small price; Robux spent in Studio testing are real unless your owner account gets tests free of charge — check the prompt text). After success: toast "…unlocked!", the shop shows **OWNED**, a **Fly** button appears, press **F** → indicator "FLYING". Move with WASD, look up to climb, Space up, Ctrl/Q down.
4. **Receipts:** buy a bundle → items appear in **Inventory** (Locksmith: Master Lockpicks + Lockpick Set). Check the Output window for no `[Monetization]` warnings. To test duplicate protection: leave right after buying, rejoin; the items must appear **once**.
5. **Death/respawn/rejoin:** while flying, reset your character → flight ends and you land normally. Rejoin → pass still owned (button visible), flight off until you toggle.
6. **Restrictions:** flight must switch off when you start a heist, during a minigame, or in jail; the server prints no errors.
7. **Common errors**
   - *"Not available yet"*: ID still `0`, or you saved without Rojo syncing.
   - *Prompt shows but nothing arrives*: check Output for `[Monetization] Receipt for unknown ProductId` → wrong ID in config.
   - *Pass owned but no fly after purchase*: wait a few seconds / rejoin once; confirm the Pass ID matches and the pass is **on sale**.
   - *"Your data is still loading"*: wait for the save to load; or API Services is off in Studio.

## E. Publishing

1. In Studio: **File → Publish to Roblox**. (Rojo-synced code is in the place; this uploads it.)
2. Repeat sections B–C on the **live** experience, paste the live IDs, publish again.
3. Verify on the live game with an alt account or your own: shop prices show, pass/product purchase works, items arrive, Fly works, rejoin keeps ownership.
4. **Before releasing, check:**
   - All three IDs are real and belong to *this* experience.
   - Pass is "Item for Sale" and products are saved.
   - A cancelled prompt grants nothing.
   - A bundle bought once appears once (also after rejoin).
   - Fly is off during heists/minigames/jail.
   - Output shows no `[Monetization]` warnings.
   - Locations/artifacts still place and display correctly (stands) and ruins look right.
