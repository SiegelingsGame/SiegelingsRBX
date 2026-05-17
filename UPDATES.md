# Update log / Memory — Last updated: 2026-04-25 00:22

Before committing: refresh this file's top timestamp and add an entry below; add or update `-- Last updated: YYYY-MM-DD HH:MM` at the top of each changed script.

---

## 2026-04-25 00:22
- **AchievementsConfig.lua**, **AchievementsSystem.lua** — Added new achievements + tracking for **meeting Eleminions**, **claiming an Eleminion quest reward**, and **interacting with Roc**.
- **EleminionSystem.lua**, **EleminionClient.client.lua**, **GameConfigData.lua** — Added a per-element **affinity “battle pass” milestone track** (25/50/75/100%) with rewards: **1000 Gold**, **Rare Egg**, **250 Diamonds**, and **Legendary Egg** at completion. Rewards are granted server-side and the UI shows claimed milestones.
- **ArenaRocSystem.lua** — Roc interaction now contributes to the new Roc achievement.

## 2026-04-24 22:52
- **WorldMapClient.client.lua** — Fixed “map is still off” by accounting for `ScaleType.Fit` letterboxing: pins and calibration clicks now convert UV↔pixels using the actual drawn image rect (based on `WorldMap.MapAspectRatio`) instead of the full frame.

## 2026-04-24 22:55
- **WorldMapClient.client.lua** — Disabled all map overlay markers/capture/calibration UI (map-only mode) so the map can be used without off-by-offset pins. Flip `MAP_ONLY = false` in the script later to restore markers.

## 2026-04-24 22:37
- **WorldMapClient.client.lua** — Added `[B]` base-UV capture mode: while the map is open, press **B** and click where the base should appear. The client stamps `BasePointAnchors[*].mapUV` for the nearest base anchor and prints a ready-to-paste config snippet.

## 2026-04-24 22:26
- **WorldMapClient.client.lua**, **GameConfigData.lua** — Added nearest-three anchor triangulation for the world map so hand-drawn landmark anchors resolve locally instead of being averaged through one global affine. Added landmark anchors from Studio positions (Cloudtopia, Evergreen, Volcanic, Frozen) and a direct map UV override for the White base pad.

## 2026-04-24 22:13
- **GameConfigData.lua** — Added the Evergreen Forest debug sample as a durable `WorldMap.AnchorCalibration` point and stored literal world XZ values for the Electric/Cave door anchors, so calibration still resolves when only two zone-door parts are present on the client.

## 2026-04-24 21:56
- **WorldMapClient.client.lua**, **GameConfigData.lua** — Added durable `WorldMap.AnchorCalibration` support: map transforms now prefer named world anchors with UVs, report active transform source/fallback reason, and print per-anchor fit errors for debugging. Zone-door capture output now includes a ready-to-paste anchor calibration block.

## 2026-04-24 21:46
- **WorldMapClient.client.lua** — Player map pin now shows calibrated direction: a gold facing arrow and a cyan movement arrow while walking. Direction is computed by projecting the player's world look/velocity through the same map transform used for pins.

## 2026-04-24 21:42
- **GameConfigData.lua**, **WorldMapClient.client.lua** — Added eight measured `WorldMap.BasePointAnchors` (Red/Blue/Green/Yellow/Orange/Purple/Pink/White). The base marker now snaps an owned plot center to the nearest configured anchor before converting to map UV, and debug output reports the matched anchor.

## 2026-04-24 21:10
- **GameConfigData.lua**, **WorldMapClient.client.lua** — Added `WorldMap.DebugPrintPlayerPositionOnOpen`; when enabled, opening the map prints the player's `Vector3`, XZ, current map UV, and owned plot center details for base-to-map calibration.

## 2026-04-23 22:09
- **default.project.json** — Rojo workflow fix: `WorldMapClient.client.lua` now syncs into `StarterPlayerScripts` so the `[M] Map` button can actually open `WorldMapGUI` in live play.

## 2026-04-23 22:21
- **WorldMapClient.client.lua**, **GameConfigData.lua** — Added `WorldMap.RotationDegrees` (0/90/180/270) to calibrate map art orientation so the player pin matches real biomes/landmarks.

## 2026-04-23 22:23
- **WorldMapClient.client.lua** — World map now places a **BASE** marker at the player’s plot `PlotCenter` (resolved from `BasePlots/Plots` and `OwnerUserId` attributes; retries while the map is open until replicated).

## 2026-04-23 22:37
- **WorldMapClient.client.lua**, **GameConfigData.lua** — Added in-game **map calibration mode**: press **[C]** on the world map and click 3 landmarks (A/B/C) while standing on them to print a ready-to-paste `WorldMap.Calibration` block; pins then use the solved transform.

## 2026-04-23 22:54
- **WorldMapClient.client.lua**, **GameConfigData.lua** — Added persistent **auto-calibration from zone doors**: capture the 4 zone-door UV markers once on the map (press **[Z]**, select 1-4, click), then the client auto-resolves door world positions and solves the transform (least squares if all 4 present).

## 2026-04-23 23:12
- **WorldMapClient.client.lua** — Fixed `[Z]` zone-door capture hotkey: no longer blocked by `processed` input, and uses the correct `zdCapture` local (was previously scoped after the key handler).

## 2026-04-23 23:46
- **WorldMapClient.client.lua** — Fixed `[Z]` capture runtime errors: `updateZDHelp` / `printZoneDoorUVBlock` are now properly defined before the input handler calls them.

## 2026-04-24 00:02
- **WorldMapClient.client.lua** — Map no longer closes when clicking the backdrop; it now only closes via **✕** or **Esc**, so calibration clicks work reliably.

## 2026-04-24 00:06
- **GameConfigData.lua** — Persisted `WorldMap.ZoneDoorMapUV` from in-game capture so zone-door auto-calibration works automatically every session.

## 2026-04-23 23:35
- **GameConfigData.lua**, **WorldMapClient.client.lua** (new), **HUDButtonBar.client.lua** — **World map** UI: optional `rbxassetid` image, auto XZ bounds from hub + outer baseplates (or manual `MinWorldXZ`/`MaxWorldXZ`), live **you-are-here** pin from `HumanoidRootPart`. Open with **`[M] Map`** on the HUD (or `M`).

## 2026-04-23 22:45
- **TradeSystem.lua**, **ArenaRocSystem.lua** — After trades, **`BasePlacementSystem.ClearOrbByUid(..., true)`** runs only for each **removed** creature uid (destroys that defense/income/battle model only), instead of **`PlaceCreatures`** rebuilding the whole base.

## 2026-04-23 22:15
- **TradeSystem.lua** — After a completed player trade, **`BasePlacementSystem.PlaceCreatures`** runs for **both** traders so defense/income/battle plot models match inventory (fixes traded-away creatures staying visible on base slots).
- **ArenaRocSystem.lua** — After **Roc** multi-creature trades, **`PlaceCreatures`** refreshes the player’s plot for the same reason.

## 2026-04-23 21:35
- **MainServer.server.lua** — **`Events.PlayCreatureAnimation`** and **`Events.ShowDamageNumber`** now use **`makeEventTyped(..., "UnreliableRemoteEvent")`** (with existing `RemoteEvent` fallback) so cosmetic replication does not compete with reliable gameplay traffic.
- **CreatureAnimation.lua** — Replaced per-player **`FireClient`** loop with **`FireAllClients`** for animation replication (same payload for every client).
- **PlayerCombatSystem.lua** — **`PlayerAttackFX`** uses **`FireAllClients`** instead of looping **`GetPlayers()`** for ranged and melee cosmetic FX.
- **ArenaSystem.lua**, **WaterGymBattleSystem.lua**, **AIRaidSystem.lua**, **DungeonSpawner.lua** — Same **`FireAllClients`** pattern wherever every player received identical arena/gym/raid/dungeon payloads (**ArenaAnnounce** paths with different text per player stay as targeted **`FireClient`**).

## 2026-04-23 19:45
- **CreatureAI.lua** — Added **distance-based AI LOD scheduling** in the Heartbeat loop: `<40` studs updates every frame, `40–120` studs at **10 Hz**, and `>120` studs at **2 Hz**. The loop now samples active player root positions once per tick and skips far-off creature updates until their next due window, reducing per-frame server AI load while preserving nearby movement fidelity.
- **MainServer.server.lua** — Added typed remote creation helper and switched **`Events.PlayerAttackFX`** to **`UnreliableRemoteEvent`** (with `RemoteEvent` fallback if unsupported) so cosmetic attack FX traffic does not contend with reliable gameplay remotes.
- **PlayerDataManager.lua** — Added coalesced save queue: **`RequestSave(player, delaySeconds?)`** plus a periodic flush loop (`2s` cadence, default `20s` delay). `SavePlayer` / `SaveAll` now clear queued save markers on flush/immediate save.
- **ArenaRocSystem.lua**, **CaptureSystem.lua**, **AchievementsSystem.lua**, **BadlandsSystem.lua**, **CosmeticSystem.lua**, **PremiumCurrencyShop.lua**, **WaterGymBattleSystem.lua**, **MainServer.server.lua** — Replaced several immediate `SavePlayer` calls with **`RequestSave`** (fallbacks preserved) to reduce DataStore burst pressure after frequent inventory/UI/reward mutations while still persisting via short-delay coalescing and normal autosave.
- **GameConfigData.lua**, **CreatureSpawner.lua** — (from prior pass) restored `MaxWorldCreatures = 150` and added spawn-time `SetNetworkOwner(nil)` for unanchored creature roots to reduce replication churn and multiplayer desync.

## 2026-04-23 19:20
- **GameConfigData.lua** — Restored world-spawn cap to **`GameConfig.MaxWorldCreatures = 150`** (was 1000 despite the perf-note comment), so default live load returns to the intended lower creature budget before night bonus.
- **CreatureSpawner.lua** — New spawn-time network ownership pin: after model creation, server attempts **`rootPart:SetNetworkOwner(nil)`** on unanchored creature roots before AI registration. This prevents client auto-ownership from fighting server-driven AI movement and reduces multiplayer rubber-banding/desync.

## 2026-04-23 19:00
- **ArenaRocSystem.lua** — **Fixed server rejecting valid offers with “Roc only trades Siegelings.”** Root cause: `isSiegelingSpecies` only matched `pylook` / ids containing `"siegeling"` / `"siegling"`, so **Squire Bud** (`squirebud`), **Cacty** (`cacty`), **Generoot**, etc. — all actually Siegelings — fell through and were rejected on **Accept**. Since only Siegelings are capturable, the species gate inside `SubmitRocTrade` is redundant; removed it. The server now only requires each offered uid to resolve to a real row in the player’s own inventory. Reward logic unchanged (**≥10 Cactys → CactyJackedty**, else **Cacty**; always exactly 1 creature).
- **ArenaRocClient.client.lua** — Build stamp bumped to **2026-04-23 19:00** so in-game UI confirms this rev.

## 2026-04-23 18:30
- **ArenaRocClient.client.lua** — **Final Roc trade rules.** Inventory row taps are now a plain toggle (no category mutex) — any mix of any Siegelings, any count, up to the full inventory. **THEIR OFFER** on every refresh: `nSel == 0` → empty; `nCacty >= 10` → **`• CactyJackedty Lv.1`**; otherwise `nSel > 0` → **`• Cacty Lv.1`**. Dropping from 10 Cactys to 9 flips the preview back to Cacty on the same click. Accept handler only rejects an empty offer. Build stamp **2026-04-23 18:30**.
- **ArenaRocSystem.lua** — **`SubmitRocTrade`** simplified to the new contract: every offered uid must be a Siegeling species (non-Siegelings rejected since nothing else is capturable). **Reward is always exactly 1 creature** — `CactyJackedty` when the offer contains `nCacty >= 10`, otherwise `Cacty`. The Cacty is tagged `rocSiegelingPact = true` plus `offerCount` / `offerCactyCount` metadata. Inventory-space check uses `rewardsCount = 1`.

## 2026-04-23 17:45
- **ArenaRocClient.client.lua** — **Cacty-only stacks (2–9)** now keep **`• Cacty Lv.1`** in **THEIR OFFER** (same as 1× Cacty) instead of going blank; **10× Cacty** still switches that line to **CactyJackedty**. Build stamp **2026-04-23 17:45**.

## 2026-04-23 17:15
- **ArenaRocClient.client.lua** — **THEIR OFFER syncs on the same tap as YOUR OFFER** for every valid Roc trade shape that was previously blank on the client: **1× Cacty** (fresh swap) and **one non-Siegeling / non-Cacty** creature now immediately show **`• Cacty Lv.1`** in **THEIR OFFER** (same `refreshRocOfferPanels` pass as the inventory click). Siegelings / **10× Cacty → CactyJackedty** behavior unchanged. Empty-state copy is neutral: **“Tap inventory above to add to your offer.”** Build stamp **2026-04-23 17:15**.

## 2026-04-23 16:00
- **ArenaRocClient.client.lua** — **Final THEIR OFFER behavior**: (1) Clearing all Siegelings removes Roc’s Cacty lines because `TheirOfferScroll` is rebuilt each refresh and only Siegelings-only selections paint `• Cacty Lv.1` / `× N`. (2) Adding Siegelings again repaints the same preview. (3) When the offer is **exactly 10× Cacty** and nothing else, **THEIR OFFER** now shows **`• CactyJackedty Lv.1`** (from **CreatureData**) instead of staying blank — matches server **SubmitRocTrade** forge. Empty-offer Accept toast is neutral: **“Add creatures to your offer.”** Build stamp **2026-04-23 16:00**.

## 2026-04-23 15:45
- **CreatureAI.lua** — **`lone`** resumes territorial **`loneHold`** vs **Siegelings**: priorities **favorite companion**, then nearest **world creature** within **`AI_AggroRange * 0.6`**; **never runs toward prey** — faces them and **attacks at range** (projectiles); if prey leaves aggro / line-of-sight drops, drops to **hold** rather than repositioning (except after **DamageCreature**, which clears **`loneHoldGround`** and uses normal **chase** vs the attacker).
- **CreatureData.lua** — **`lone`** behavior blurb aligned with AI.

## 2026-04-23 14:30
- **CreatureAI.lua** — **`lone`** wild creatures no longer **aggro players or companions on sight** (they patrol like before but only enter combat after **DamageCreature** / provocation). **`aggressive`** still hunts in range. When a world creature’s projectile damages the **player’s Humanoid**, the server fires **`ShowNotification`** so **HUDClient** shows a combat toast (**“{displayName} hit you for N damage”**, defense-adjusted).
- **CreatureData.lua** — Behavior doc for **`lone`** updated to match AI.

## 2026-04-23 01:00
- **ArenaRocClient.client.lua** — Roc trade now supports **N Siegelings → N Cactys** in a single submit: taps on Siegeling rows multi-select unlimited, Cacty rows still stack (up to 10, silent), and non-siegeling/non-Cacty rows stay single-select. **THEIR OFFER** stays empty until the player drops at least one Siegeling into their side — only then does `• Cacty Lv.1` (or `• Cacty Lv.1 × N`) appear. The empty-state hint is now just `"Offer a Siegeling."` (the **10× Cacty → CactyJackedty** path is an easter egg and is no longer mentioned anywhere in the UI). Accept validates category mutex client-side and toasts never leak the 10-stack count. Build stamp bumped to **"ROC build 2026-04-23 01:00 (N-siegelings, easter-egg hidden)"**.
- **ArenaRocSystem.lua** — `SubmitRocTrade` accepts any `N ≥ 1` Siegelings and grants `N` Cactys (one per Siegeling, each tagged `rocSiegelingPact = true` + `fromSiegelingId`). Legacy single-creature (non-Siegeling, non-Cacty) trades still return 1 Cacty. 1× Cacty still returns a fresh Cacty; 10× Cacty still forges a **CactyJackedty**. Error copy is intentionally generic — no branch mentions the 10-stack. Reward-space check uses a computed `rewardsCount` so Siegeling batches validate inventory room for *N* rewards, not 1.

## 2026-04-23 00:15
- **ArenaRocClient.client.lua** — **Root cause of blank Roc trade panel**: `hubGui.ZIndexBehavior = Global` combined with `tradeView.ZIndex = 20` meant every child with **ZIndex < 20** rendered **behind** tradeView's opaque backdrop. Only `tTitle/tBuildStamp/tradeClose` (all ≥ 25) were visible; partner row, inventory strip, offer columns, and Accept/Cancel were hidden by the backdrop.
- **Fix:** Made `tradeView` transparent (`BackgroundTransparency = 1`, `ZIndex = 1`, `root` already paints PR.bg behind) and bumped all trade-view descendants to **ZIndex 25–28** (partnerRow/rocInvLabel/tradeScroll = 25, offer frames = 25, offer titles/scrolls/rows = 26–27, Accept/Cancel = 28). **THEIR OFFER** now always shows **“• Cacty Lv.1”** by default (Roc always trades a Cacty for a valid Siegeling) with pivot to **CactyJackedty** when you queue 10 Cacty. Build stamp bumped to **“ROC build 2026-04-23 00:15 (ZIndex fix)”**.

## 2026-04-22 23:30
- **ArenaRocClient.client.lua** — Added **`ROC_BUILD_STAMP = "ROC build 2026-04-22 23:30"`** printed on load (`[ArenaRocClient] ROC build …`) and shown as a small gold line under the **TRADE (ROC)** header so it is visible in-game. If the stamp is missing, Studio/Rojo is running an older copy of the script.

## 2026-04-22 23:00
- **ArenaRocClient.client.lua** — **Trade with Roc** aligned to **TradeGUI**: **TRADE (ROC)** header, **Trading with: Roc**, top inventory strip, **YOUR OFFER** / **THEIR OFFER** columns (green/blue titles), **ACCEPT** / **CANCEL**, **refreshRocOfferPanels** on open. **C.green** set to **`(80, 220, 120)`** to match P2P. **THEIR OFFER** label matches player trade (no “(Roc)” suffix).

## 2026-04-22 22:45
- **CodexModelViewer.lua** — Viewport creatures can use configurable **`defaultAnimType`** (with **`playIdleAnimation`**) instead of hardcoded Idle; uses **`PlayAnimation`** when available.
- **LaunchScreen.client.lua** — Starter pick cards enable viewport animation with **`Income`** (matches passive-income showcase; fixes T-pose).

## 2026-04-22 21:00
- **ArenaRocClient.client.lua** — Roc **Trade with Roc** panel mirrors **FriendsListClient** TradeGUI inventory strip (dark **`TRADE_INV_STRIP_BG`**, **2px** list gap, compact **28px** rows, **18×18** element orb, **GothamBold** **Name (Lv.n)** + **★** favorite tint). Sections: **Siegeling → Cacty**, **Cacty** (multi up to 10), **Other**. Selection rules aligned with player trade (single non-Cacty vs multi-Cacty).
- **ArenaRocSystem.lua** — **GetRocTradeInventory** adds **`isSiegeling`** and **`isFavorite`** per row for UI.

## 2026-04-22 20:15
- **ArenaRocClient.client.lua** — Trade list **UIPadding**: replaced invalid **`.Padding`** (not a member of **`UIPadding`**) with **`PaddingLeft` / `PaddingRight` / `PaddingTop` / `PaddingBottom`** (fixes “Roc menu failed: Padding is not a valid member of UIPadding”).

## 2026-04-22 19:30
- **ArenaRocClient.client.lua** — Roc hub **pcall** failures addressed: safe **`AutomaticCanvasSize`** with fallback canvas height; avoid fighting auto-size vs manual **`CanvasSize`** (defer + layout listener only when auto is off); **`Draggable`** in **pcall**; **`styleRocCloseButton`** no longer gates on **`GuiButton`**; **`buildFallbackTeamRows`** sort uses **tonumber**; team rows use **`tostring(row.id)`** for **CreatureData**; trade submit uses **pcall** around **`InvokeServer`**; error toast shows **truncated engine error** (not only “re-talk”).

## 2026-04-22 18:45
- **ArenaRocClient.client.lua** — Close buttons use ASCII **X**, **UIStroke**, solid red fill, higher **ZIndex** (Unicode **✕** was invisible on some devices while still clickable). **TRADE** always switches to the trade overlay; empty inventory shows inline help instead of silently doing nothing; **GetRocTradeInventory** wrapped in **pcall**.
- **ArenaRocSystem.lua** — **GetRocTradeInventory** scans **`pairs(inventory)`** and resolves **uid/id** from **`uid` · `Uid` · `UID` · `id` · `Id`** so legacy rows aren’t skipped.

## 2026-04-19 22:30
- **ArenaRocClient.client.lua** — **`showRocHub`** now calls **`destroyHubGui`** (destroy UI only) instead of **`closeAll`**. **`closeAll`** previously fired **`RocHubRelease`** before rebuilding the hub, clearing the server Roc hub mutex immediately after **`RocOpenHub`** — **`GetRocTradeInventory`** returned `{}` (“no creatures / session expired”) and **`RequestRocNpcBattle`** failed (“Session expired”). **`closeAll`** still releases the lock when the player actually closes the hub.
- **ArenaRocSystem.lua** — **`isSiegelingSpecies`**: treat creature ids containing **`siegeling`** as Siegelings (in addition to **`siegling`**) for pact / counting.

## 2026-04-21 22:10
- **ArenaRocClient.client.lua** — Roc hub UI build is now **pcall-protected** (and `MobileWindowLayout` calls are wrapped) so a runtime error can’t leave a **blank/dead** window; on failure it closes and shows a toast to re-talk to Roc.

## 2026-04-21 22:18
- **ArenaRocSystem.lua** — Wrapped `RocInteractPrompt.Triggered` in `pcall` so “interaction failed” doesn’t happen silently; logs the server error and notifies the player.

## 2026-04-20 14:00
- **ArenaRocClient.client.lua** — Roc menu refit to **FriendsListClient** `ProfilePopupGUI` (360×440, blue stroke, **TRADE** + **PvP 1v1** footer, red **✕**). Scroll: greeting, record, **ROC'S TEAM** cards (orb + Cacty / CactyJackedty from **getRocTeamList**), **Challenge nearest player** row, then fixed footer. **PvP 1v1** → **RequestRocNpcBattle**; **TRADE** → existing Roc trade panel. **Not** DataStore — **GameConfig** + **CreatureData** fallback when remotes omit rows.

## 2026-04-19 20:00
- **PvPBattleSystem.lua** — **`StartNpcStylePvp`** + **`startNpcStylePvpBattle`**: 1v1 PvP (same `run1v1Battle`, spawns, rewards, **PvPBattleStart** / **End**, faint/revive) vs a scripted creature anchored at **Roc** (no Water Gym / no Arena main ring).
- **ArenaRocSystem.lua** — **RequestRocNpcBattle** now calls **PvP** NPC path; **`GameConfig.ArenaRoc`**: **NpcPvPChampionIndex**, **NpcPvpMaxRange**; removed arena Blue/Red **gym** requirement.
- **GameConfigData.lua**, **ArenaRocClient** — config + client hint text aligned with PvP-style Roc battle.

## 2026-04-19 19:00
- **LaunchScreen.client.lua** — Larger **starter viewport** (orb) and an **income** row with **UIScale** tween (passive coins/min from **CreatureData**).
- **GameConfigData.lua** — **ArenaRoc** adds **Greeting**, **GymName**, and static **DisplayTeam** (code-driven NPC profile, not DataStore).
- **ArenaRocSystem.lua** — **buildRocSpecRows** merges **DisplayTeam** with **CreatureData**; **RequestRocNpcBattle** (RemoteFunction) → **WaterGymBattleSystem** vs **Workspace.Arena** (Blue/Red) with custom **opponentTeam**.
- **ArenaRocClient.client.lua** — **task.defer** + long **Events** wait (avoids early exit); **header** + **close**; **Trade / PvP / Vs Roc's team**; trade panel restored; **RequestRocNpcBattle** + close on success.

## 2026-04-21 16:00
- **ArenaRocClient.client.lua** — Roc hub + trade: top-right **×** closes the whole window (releases hub lock); removed redundant **Close** text control.

## 2026-04-21 15:00
- **ArenaRocSystem.lua** — Hub **`rocInventory`** always includes **Cacty** + **CactyJackedty** with **`sortOrder`** and display-name fallbacks if **`CreatureData.GetById`** fails.
- **ArenaRocClient.client.lua** — **`normalizeRocInventory`**: build list with **`pairs`** + sort by **`sortOrder`** (fixes empty team list when RemoteEvent stringifies array indices); deferred **`CanvasSize`** for Roc team **`ScrollingFrame`**.

## 2026-04-21 14:00
- **ArenaRocSystem.lua** — Single **`RocInteractPrompt`** opens **`RocOpenHub`** with **display inventory** (Cacty + favorite **CactyJackedty**), **`HubLockSeconds`** mutex, **`GetRocTradeInventory`** / **`SubmitRocTrade`** require lock; **`RocHubRequestBattle`** → **`PvPBattleSystem.ChallengeNearestOpponent`** (stakes **`PvPWinGold`** / **`PvPLoserGoldLoss`**, default 10). Removed Roc NPC gym battle hook; legacy Talk/Trade/Battle prompts cleared on attach.
- **ArenaRocClient.client.lua** — Hub UI: Roc team list, **Trade** / **Battle (PvP)**, trade sub-panel, **`RocHubRelease`** on close.
- **PvPBattleSystem.lua** — **`ChallengeNearestOpponent(requester, maxDistance)`** for Roc (standard **`PvPChallengeInvite`** flow).
- **MainServer.server.lua** — **`PvPBattleSystem.Init`** runs **before** **`ArenaRocSystem.Init`**.
- **GameConfigData.lua** — **`ArenaRoc.HubLockSeconds`**.

## 2026-04-21 13:00
- **ArenaRocSystem.lua** — Roc **faces** players: **nearest** alive character within **`ArenaRoc.AttentionRange`** (default 50), else **last** Talk/Trade/Battle interactor if still in range; otherwise returns to **spawn pivot**. **`Humanoid.AutoRotate = false`**. **`GameConfig.ArenaRoc`**: **`AttentionRange`**, **`FacingUpdateInterval`** (fallbacks match **Eleminion**).
- **GameConfigData.lua** — **`ArenaRoc`** facing defaults.

## 2026-04-21 12:00
- **ArenaRocSystem.lua** — Resolves NPC as **`Workspace.Arena.Roc`** (R15 character rig) or **`Model_Roc`**; wait + **`DescendantAdded`** (incl. **`HumanoidRootPart`** under that model) so prompts attach after streaming.
- **ArenaRocClient.client.lua**, **GameConfigData.lua** — Comments aligned with **`Arena.Roc`**.

## 2026-04-20 23:00
- **ArenaRocSystem.lua** — **`RocTalkPrompt`** (**Talk** / **Roc**) fires **`RocNpcDialog`** with *“Hi ! I'm Roc, Wanna Trade? or Battle!”*; existing worlds get the prompt on next **`attachPrompts`** without duplicating Trade/Battle.
- **ArenaRocClient.client.lua** — **`RocNpcDialog`** opens a small dialog panel (OK + auto-close).

## 2026-04-20 22:00
- **PlayerDataManager.lua** — **`RegisterInventoryPostChangeListener`** + **`fireInventoryPostChange`** after **AddCreature**, **RemoveCreature**, **SellCreature**, **TransferCreature** (both players), **EvolveCreature**, and end of **OnPlayerJoin**. **`AddCreature`** persists **`rocSiegelingPact`** / **`rocSiegelingPactActive`** from context when **`rocSiegelingPact == true`**.
- **ArenaRocSystem.lua** — Siegeling-for-Cacty trades tag the new **Cacty** with a pact: once the player has owned a **Siegeling** again, the pact **arms**; if they later have **no** Siegeling (sell, trade, evolve, etc.), Roc’s **Cacty** is **removed** and a notification is shown.
- **ArenaRocClient.client.lua** — Subtitle explains the recall rule; slightly taller copy + list layout.

## 2026-04-20 21:00
- **ArenaRocSystem.lua** — **`GetRocTradeInventory`** (full inventory with **`displayName`**) replaces **`GetRocCactyInventory`**. **`SubmitRocTrade`**: **1 non-Cacty** creature → **Cacty** (e.g. Siegeling); **1 Cacty** → fresh **Cacty** swap; **10 Cacty** → **CactyJackedty** (unchanged).
- **ArenaRocClient.client.lua** — Lists all tradeable creatures; copy and toasts updated for the three cases.

## 2026-04-20 20:00
- **default.project.json** — Rojo tree: **`ArenaRocSystem`** (ServerScriptService), **`ArenaRocClient`** (StarterPlayerScripts).
- **ArenaRocSystem.lua** (new) — **`Workspace.Arena.Model_Roc`**: Trade + Battle **`ProximityPrompt`**s; **1 Cacty** → fresh **Cacty**; **10 Cacty** in one trade → **CactyJackedty**; battle via **`WaterGymBattleSystem`** vs **Lv.25 CactyJackedty**; **global** wins/losses **`DataStore` `ArenaRocStats_v1`** + workspace attributes **`ArenaRocNpcWins` / `ArenaRocNpcLosses`**.
- **ArenaRocClient.client.lua** (new) — **`RocOpenTrade`** UI to pick 1 or 10 Cacty and **`SubmitRocTrade`**.
- **WaterGymBattleSystem.lua** — Optional **`opponentTeam`**, **`skipZoneRewards`**, **`onGymBattleResolved`**; **`placeTeam`** takes **`statsPlayer`** (nil for red AI).
- **GameConfigData.lua** — **`GameConfig.ArenaRoc`** (level / rewards / cooldown).
- **MainServer.server.lua** — **`ArenaRocSystem.Init`**.

## 2026-04-20 19:00
- **CreatureData.lua** — New creatures: **Shadow** — **`voib` → `voiboy` → `voimaw`** (VoiMaw, black-hole theme; distinct id from **`voidmaw`** legendary), **`nightcap`**; **Light** — **`lightbear`**; **Poison** — **`slandy`**; **Undead** — **`embertwins`**.

## 2026-04-20 18:00
- **MainServer.server.lua** — After **`AssignPlot`**, **`resetStalePlotAssignmentsForPlayer`** clears **`OwnerUserId`**, sign, and tagged base objects on **other** plots still marked for that player (fixes ghosts + wrong sign when joining a new random plot after Plot2 / Studio restarts).
- **BasePlacementSystem.lua** — **`DestroyTaggedCreaturesForOwnerUserId`** (public) removes orphaned **BaseDefenseCreature** / **BaseIncomeCreature** / **BaseBattleCreature** models for that owner before **`PlaceCreatures`** on the new plot.

## 2026-04-20 17:00
- **FavoriteCreatureSystem.lua** — **`GetCompanionRespawnRemainingSeconds`** exposes faint-respawn cooldown for UI.
- **MainServer.server.lua** — **`GetInventory`** returns **`companionRespawnRemainingSec`** (seconds remaining, or **0**).
- **InventoryUIManager.client.lua** — Favorite card shows **`Fainted — Xs · [name]`** (muted red text) instead of **`ReCard`** while the companion is on faint cooldown; **`CompanionFainted`** + Heartbeat keep the countdown fresh.

## 2026-04-20 16:00
- **TopRightBadgeTray.lua** (new) — Shared **`ScreenGui`** + right-aligned **`UIListLayout`** row; **`Order`** table assigns **`LayoutOrder`** (higher = closer to the right edge; strip grows left toward center).
- **BuffShopClient**, **ArenaBattleSummaryClient**, **BaseSummaryClient**, **HUDClient** (dungeon), **InventoryUIManager** (base raid), **AchievementUnlockBadge**, **MusicMuteBadge**, **ArenaRewardUI** (watch) — crest/buff/utility icons parent into the tray instead of overlapping manual ticker offsets.
- **NotificationManager.lua** — **`ToastContainer`** anchored **top-right** (`AnchorPoint` 1,0), narrower width, vertical list **right-aligned**; **`KillFeed`** shifted down to reduce overlap with the toast column.

## 2026-04-20 14:00
- **BaseSummaryClient.client.lua** — When **`OwnerUserId`** is cleared or no longer matches the local player (leave / new plot), **destroy** the client **`BaseSummary`** billboard and drop **`summaryGuis`** state. Previously the heartbeat loop **`continue`d** on vacant plots without cleanup, leaving owner name + stat text floating over the old slot.
- **MainServer.server.lua** — **`setPlotSignState`** updates **every** **`BillboardGui`** / **`SurfaceGui`** under **`SignPart`** (not only the first of each type), so **`resetPlotWorldState`** / **`refreshAllPlotSigns`** fully clear duplicated sign templates.

## 2026-04-20 13:00
- **PlayerDataManager.lua** — **`OnPlayerLeave`** defers **`claimedPlotIds`** release, **`plotId = 0`**, save, and **`playerCache`** clear so **`PlayerRemoving`** handlers registered later (**BasePlacementSystem**, **`MainServer`** plot reset) still get **`GetData`** / **`plotId`** for **`resetPlotWorldState`** and creature cleanup. **`Players:GetPlayerByUserId`** guard skips deferred teardown if the player reconnected before the deferred step (avoids wiping an active session).

## 2026-04-20 12:00
- **BasePlacementSystem.lua** — **PlayerRemoving** no longer bails when **`GetData`** / **`plotId`** are cleared before this handler (`PlayerDataManager.OnPlayerLeave` order). **`findPlotModelForLeavingPlayer`** resolves plot by **`plotId`** first, then **`OwnerUserId`** on the plot model. **`destroyTaggedBaseCreaturesForOwnerUserId`** removes defense/income/battle tagged models with matching **`OwnerUserId`** (orphans / wrong parent). Prevents Siegelings staying on the **previous** plot after rejoin.

## 2026-04-19 21:00
- **EleminionSystem.lua** — NPC placement uses **world-space top face** of the EPoint (`CFrame * local half-height`) instead of `Position.Y + Size.Y/2`, so tilted/rotated pads (e.g. **WaterEPoint**) no longer sink under terrain or float with wrong height.

## 2026-04-19 22:00
- **EleminionSystem.lua** — Eleminion NPCs use **upright** placement (`CFrame.lookAt` with horizontal pad forward) instead of inheriting the EPoint’s full tilt. Foot **lift** uses world-down **min Y**; a tilted rig made that step mis-place Moisty while flat pads stayed fine.

## 2026-04-19 19:45
- **BasePlacementSystem.lua** — **`RefreshAllPlotVisibility`** moved to **after** **`normalizeOwnedFloorsForPlacement`** / **`applyOwnedFloorsVisibility`**. Previously it referenced locals **before** their declarations (Lua treats that as **global** → **nil** → `attempt to call a nil value` at line ~327). That threw during **`MainServer.autoAssignAndSetup`** right after **`AssignPlot`**, aborting **`PlaceCreatures`** and **`teleportToBaseReliable`**. Replaced **`continue`** with nested **`if`** for portability.

## 2026-04-19 19:00
- **MainServer.server.lua** — **`nudgeToAssignedBaseXZ`**: **RunService.Heartbeat** for ~**4s** pulls character back to plot if still far from **PlotCenter** (hub **`SpawnLocation`** often wins first frames). **`buyFloor`** dome path uses **`findBasePlotsFolder`** / **`findPlotModelInFolder`**.
- **PlayerDataManager.lua** — **`BuyFloor`** calls **`SavePlayer`** after purchase so **ownedFloors** (e.g. floor 2) persist before next autosave.
- **BasePlacementSystem.lua** — **`floorIndexFromFloorFolderName`** / **`resolveFloorFolder`**: **`Floor 2`**, **`Floor02`**, etc.; **`setFloorVisibility`**, **`getFloorForPart`**, **`getFloorAncestorNum`**, **`getBattlePointMap`**, **`setBattlePointColors`** use it so stairs/Floor2 content toggles match the map.

## 2026-04-19 18:00
- **MainServer.server.lua** — **`findBasePlotsFolder`** + **`findPlotModelInFolder`** (padded names `Plot02`, nested `World/BasePlots`), defined **before** **`refreshAllPlotSigns`** so startup does not index nil. **`teleportToBaseReliable`**: **100× 0.25s** retries + diagnostic **warn** on failure. **`refreshAllPlotSigns`**, **`findPlotModelForPlayer`**, **`setupPlotForPlayer`**, **`teleportToBase`** use shared resolution.
- **LoadingGate.client.lua** — **`findBasePlotsFolderClient`** matches server so **`OwnerUserId`** plots are found when BasePlots is nested.
- **BasePlacementSystem.lua** — Init resolves **Plots** / nested BasePlots; **`findPlotModel`** matches padded names + scan (same as MainServer).

## 2026-04-19 17:00
- **MainServer.server.lua** — **`teleportToBaseReliable`**: retries base teleport for **~8s** (HRP not ready on first frame). Clears **root** linear/angular velocity on move. **`EnsureBaseSpawn`** remote (rate-limited) for client retry pings. Join, death respawn, and home recall use reliable path; **markCriticalReady** still runs after join teleport finishes.
- **LoadingGate.client.lua** — **"Arriving at your base"** no longer gives up at **20s**; uses **`LoadingGateArriveMaxWait`**, **horizontal (XZ) distance** to plot center, **periodic `EnsureBaseSpawn:FireServer()`** while waiting. **MAX_GATE_SECONDS** uses **`LoadingGateAbsoluteMaxSeconds`**. Preload center uses **`getPlotCenterWorldPosition`** (Model PlotCenter).
- **GameConfigData.lua** — **`LoadingGateArriveMaxWait`** (300), **`LoadingGateAbsoluteMaxSeconds`** (330).

## 2026-04-19 16:30
- **MainServer.server.lua** — **`teleportToBase`** (join + death respawn + home recall) required **`PlotCenter`** to be a **`BasePart`**. Maps where **`PlotCenter`** is a **`Model`** (or nested) silently skipped teleport, so players stayed on the hub **`SpawnLocation`**. Added **`getPlotCenterWorldPosition`** aligned with **`LaserDoorSystem`** / **`LoadingGate`** (model pivot, fallbacks).

## 2026-04-19 15:00
- **BasePlacementSystem.lua** — **Floor 2/3/4 visibility after global plot refresh:** `RefreshAllPlotVisibility` (runs on player join/leave) called `setPlotInhabited`, which hides all upper-floor parts; only the owner’s delayed `PlaceCreatures` restored them — other players who owned Floor 2+ lost visibility until rejoin. After the inhabited pass, re-apply each claimed plot’s **`ownedFloors`** via shared **`applyOwnedFloorsVisibility`**. **PlayerDataManager.lua** — **`GetUserIdForPlot(plotId)`** reads `claimedPlotIds` so placement can resolve the online owner.

## 2026-04-19 14:30
- **LaunchScreen.client.lua** — Starter cards: replaced solid-color element orbs with **circular ViewportFrames** via **CodexModelViewer** (`viewportCornerRadius` full circle, themed lighting, no floor) so each starter shows its **3D model** inside the existing rarity-stroked circle.

## 2026-04-19 13:14
- **EleminionData.lua** — Added Eleminion definitions for **dual-zone elements**: Water (Moisty / `WaterEPoint`), Poison (Slimy / `PoisonEPoint`), Metal (Steamy / `MetalEPoint`), Shadow (Umbry / `ShadowEPoint`), Lightning (Zappy / `ElectricEPoint`), Light (Sunny / `LightEPoint`), Psychic (Thinky / `PsychicEPoint`), Undead (Bony / `UndeadEPoint`). Each includes `pointHints` for Studio marker names, biome labels aligned with **CreatureData** zones, and 10-step affinity quests with matching legend-egg rewards.

## 2026-04-19 12:00
- **CreatureAI.lua** — Water-type world creatures treat **Terrain.Material.Water** like Ocean/WaterBlock: **`IsPositionInTerrainWater`**, **`IsPositionInSwimmableWater`**. **`moveTowards`** skips obstacle **raycasts while swimming** (fixes seafloor pinning). Idle snap, flee, wander vertical jitter, swim animation use **swimmable** volume — **only** **`CreatureData.IsWaterType`** uses this path on land vs water.
- **FavoriteCreatureSystem.lua** — Water companion follow also uses **`CreatureAI.IsPositionInTerrainWater`** (with Ocean / WaterBlock / Humanoid Swimming).

## 2026-04-18 23:59
- **AchievementUnlockBadge.client.lua** — New top-left **achievement badge** (same edge pattern as **MusicMuteBadge**): unlocks queue here; **tap** to show **`Notify.RewardPopup`** (same copy/rewards as before). **`DisplayOrder` 49** so **NotificationGUI** popups draw on top. Queue count bubble when **>1**; dedupe by achievement **id**.
- **PlayerProfileClient.client.lua** — Removed immediate unlock popup; profile still refreshes achievement cache/UI on **`AchievementUnlocked`**.
- **default.project.json** — Register **`AchievementUnlockBadge`** under StarterPlayerScripts.

## 2026-04-18 23:58
- **BasePlacementSystem.lua** — **`BattlePointWall`** parts that are **glass safety barriers** (name contains `glass`, **`IsGlass = true`**, or **`Material = Glass`**) stay **`Material.Glass`**, **`Transparency = 1`**, **`CanCollide = true`**. Team-colored **`ForceField`** **`BattlePoint`** / **`BattlePointWall`** shells unchanged. **`setFloorVisibility`** applies full invisibility to those glass barriers instead of **`GLASS_TRANSPARENCY_VISIBLE`**.

## 2026-04-18 23:55
- **FavoriteCreatureSystem.lua** — Steal delivery at base: **`StealHomeRadius`** is now evaluated on **horizontal distance (XZ)** to match walk-back arrival and avoid false “not home” when **PlotCenter** Y differs from the player. **`getPlotCenterPosition`**: if **`PlotCenter`** is missing, fall back to the plot **Model** pivot. Pickup stores victim **XP**; **`AddCreature`** on deliver passes **variant** + **nickname** via **`buildRaidAddContext`**. Companion carry “home” check uses the same **`getPlotCenterPosition` + horizontal** rule.
- **GameConfigData.lua** — Comment on **`StealHomeRadius`** clarified (horizontal XZ).

## 2026-04-18 23:40
- **FavoriteCreatureSystem.lua** — Steal recovery hits: range check uses victim **HumanoidRootPart** vs thief (matches client), melee uses **`PlayerMeleeRange`** (not AoE **`PlayerMeleeRadius`**), slightly wider tolerance for latency.
- **PlayerCombatClient.client.lua** — **`pvpthief_`** melee gate uses **`PlayerMeleeRange`** so “out of range” matches server.

## 2026-04-18 23:25
- **GameConfigData.lua** — Drip Shop: **White Base** / **Black Base** (`exterior_white`, `exterior_black`) and **White Pads** / **Black Pads** (`base_white`, `base_black`); same coin/gem tiers as existing color options.
- **BaseExteriorSystem.lua** — **`THEME_PALETTES`** entries for **`exterior_white`** and **`exterior_black`** (gym points use brighter blues/reds on black foundations).

## 2026-04-18 23:10
- **BaseExteriorSystem.lua** — On first cosmetic pass, store each part’s **original `Enum.Material` value** on attribute **`BaseCosmeticOriginMaterial`**. Unequipping base exterior or base pad tint **restores** that material (premium themes no longer leave Neon/etc. permanently). **`ClearCosmeticOriginSnapshots`** after plot reset for the next owner.
- **MainServer.server.lua** — **`resetPlotWorldState`**: call **`ClearCosmeticOriginSnapshots`** after resetting themes/colors.

## 2026-04-18 22:50
- **LaserDoorSystem.lua** — Shield generator **ProximityPrompt**: set **`KeyboardKeyCode = E`** and **`Exclusivity = AlwaysShow`** so the **[E]** hint appears (matches Knight Base / base orb prompts).

## 2026-04-18 22:35
- **NpcSpawnMarkers.lua** — **`HideSpawnMarkers`**: **BrokerSpawn**, **CookSpawn**, **SiegeSpawn**, **CuratorSpawn** parts (or Models) set to **Transparency = 1** at server start.
- **MainServer.server.lua** — call **`HideSpawnMarkers`** after hub defer, before hub NPC systems init.

## 2026-04-18 22:15
- **NpcSpawnMarkers.lua** — **`ResolvePlacementRelativeToHubSpawn`**: marker position & facing expressed in **HubArea.SpawnLocation** space so slots track the default hub spawn after layout settles.
- **MainServer.server.lua** — one **`HubNpcPlacementDeferSeconds`** wait (with **`GameConfig.HubNpcPlacementDeferSeconds`**) before hub NPC systems init.
- **BadlandsSystem.lua**, **IngredientSpawnSystem.lua**, **SiegeMasterSystem.lua**, **ArenaTraderSystem.lua** — use resolve when **`SpawnLocation`** exists; **fallback** to raw marker if not.

## 2026-04-18 22:10
- **PlayerProfileClient.client.lua** — Profile tab header: purple **LEVEL** pill sits **immediately to the right of the player name** (horizontal row + centered group), not pinned to the panel’s top-right.

## 2026-04-18 21:35
- **ArenaTraderSystem.lua**, **GameConfigData.lua** — **CuratorSpawn**: Y from marker **top + `ArenaTrader.CuratorSpawnRiseStuds`** (default **8** = two 4-stud blocks), not terrain raycast. Tune in config if you want a different lift.

## 2026-04-18 21:20
- **NpcSpawnMarkers.lua** (ReplicatedStorage) — resolve optional hub spawn **BaseParts** by name.
- **BadlandsSystem.lua** — **The Broker** spawns at **BrokerSpawn** when present (moves existing **BrokerNPC** too).
- **IngredientSpawnSystem.lua** — **Cook** uses **CookSpawn**.
- **SiegeMasterSystem.lua** — **Siege Master** uses **SiegeSpawn**.
- **ArenaTraderSystem.lua** — **The Curator** (trader) uses **CuratorSpawn**.
- **default.project.json** — sync **NpcSpawnMarkers** module path.

## 2026-04-18 21:05
- **BaseExteriorSystem.lua** — **Base Plots** palette: **ramp** parts (name contains `ramp`) tint with the same **income** / **defense** colors as carpets and pads (under **Floor2** → defense; otherwise income). Theme still applies first when clearing the palette.

## 2026-04-18 21:00
- **Shop hub** — New **SCoins** and **Gems** entries; taller hub panel. **SCoins shop** (`ScoinsShopClient`): six tiers (**Handful**→**Bank**) buy **SCoins** with **Diamonds** (gems); config `GameConfig.ScoinsGemPacks`. **Gems shop** (`GemsShopClient`): same tier names, **Robux** only via Developer Products (`GameConfig.GemsRobuxPacks`; `EggShopSystem` **ProcessReceipt** grants gems).
- **PlayerDataManager** — **`scoins`** persisted currency; **GetInventory** returns `scoins`; **PremiumCurrencyShop** module + **`BuyScoinsPack`** remote + **`SCoinsUpdate`**.
- **DiamondNeedHint.lua** — Center **RewardPopup** when diamond gem purchases fail: Achievements, Eleminion quests, Shop → Gems. Wired from **Cosmetic**, **Egg** (gems), **Buff** (gems), **SCoins** shop.

## 2026-04-18 20:20
- **CreatureSpawner.lua**, **CreatureData.lua**, **GameConfigData.lua** — Wild spawns: **fill empty SpawnPoint / SpawnPoint2** parts (weighted by element + rarity), **diversity bias** so species already present in the world are less likely to roll again; tunables `SpawnPointCoverageRadius`, `SpawnPointFillPerCycle`, `SpawnPointBurstFillMax`, `SpawnDiversityStrength`.

## 2026-04-18 19:30
- **GameConfigData.lua** — Hub shops: every **Buff**, **Cosmetic**, **Base exterior**, **Base color**, and **Egg** listing now has both **coin** and **diamond (gem)** prices so players can pay with earned gold or premium currency.
- **EggShopSystem.lua**, **EggShopClient.client.lua** — Egg purchases accept **gems** (`InvokeServer(..., "gems")`); UI shows split **Coins | Diamonds** row plus optional Robux when configured.
- **CosmeticShopClient.client.lua**, **CosmeticSystem.lua**, **MainServer.server.lua** — Drip Shop rows show side-by-side coin and diamond buy buttons where both apply; **GemsUpdate** + clearer “diamonds” copy; exterior/base purchases refresh gem balance after diamond spends.

## 2026-04-18 18:45
- **MainServer.server.lua** — Drip Shop: buying a **base exterior** or **base color** now auto-equips it and applies theme/pad colors to the player’s plot immediately (cosmetic trails/auras/name colors already auto-equipped via `CosmeticSystem`).

## 2026-04-18 18:15
- **BaseExteriorSystem.lua** — Four premium base themes: **JungleHut**, **IceFortress**, **VolcanicCavern**, **FloatingPalace** (full palettes + materials, exterior shell). Registered in `PREMIUM_FULL_THEME_IDS`.
- **GameConfigData.lua** — `BaseExteriorItems` shop entries (500 coins each) with names/descriptions.

## 2026-04-18 17:30
- **BaseExteriorSystem.lua** — Only **HauntedHouse** and **RetroArcade** apply palette materials to plot parts. Default theme, **exterior_*** paint themes, Base Plots pad/carpet tinting, gym BattlePoint tint, and pad grey reset change **Color** only so DiamondPlate (and other Studio materials) stay. Removed Grass/Concrete/SmoothPlastic/Fabric overrides from those paths. **GameConfigData.lua** — comment reflects behavior.

## 2026-04-18 17:00
- **BaseExteriorSystem.lua** — With no Base Plots palette equipped, **Carpet1/Carpet2** parts are no longer recolored to green/red defaults; they keep their Studio starter colors. Shop palette still tints carpets when equipped. **GameConfigData.lua** — comment aligned.

## 2026-04-18 16:30
- **BaseExteriorSystem.lua** — Default (no exterior theme): foundations use grass material/color instead of painting the whole plot grey on spawn/reset. Carpet folders excluded from theme passes; shop tints carpets when a Base Plots palette is equipped (see 17:00 for nil palette behavior).
- **BasePlacementSystem.lua**, **MainServer.server.lua** — Always call `ApplyBaseColorToPlot` (including `nil`) after theme so pads refresh when no Base Plots color is equipped.
- **GameConfigData.lua** — Comment updated for Base Color shop scope.

## 2026-04-18 16:05
- **Steal victim vs thief** – Remotes `StealVictimMarkThief` / `StealVictimClearMark`. Victim sees thief highlighted red + overhead “Target to Free (nickname or species name)”; thief slots into the combat target bar (`pvpthief_<userId>`). Victim hits route through **PlayerCombatSystem** (`HandleStealVictimHit`) with `GameConfig.StealVictimHitDamageCap`; **FavoriteCreatureSystem** restores inventory + income/defense slot + `PlaceCreatureInSlot`. **PlayerDataManager.AddCreature** applies optional nickname from context. **MainServer**, **FavoriteCreatureSystem**, **PlayerCombatSystem**, **PlayerCombatClient**, **CaptureClient**, **PlayerDataManager**, **GameConfigData**.

## 2026-04-18 15:45
- **BiomeSkyboxClient.client.lua** — CaveSky is chosen in the cave baseplate vertical column before hub/roads/inner wedges so cave music/sky is not replaced by spoke wedges (e.g. FireSky). Inner-wedge radius now follows `GameConfig.BiomeZone.InnerWedgeMaxRadius`.
- **GameplayMusic.client.lua** — Same cave-column rule for track selection (beats arena proximity and inner-sky mappings); arena position poll also reacts when entering/leaving the cave column.
- **MusicMuteBadge.client.lua** — New top-right badge toggles mute for the gameplay **Music** `SoundGroup` (all Sieglings theme tracks using that group).

## 2026-04-18 14:00
- **CaptureClient.client.lua** – Clicking an enemy’s fainted base (income/defense) creature now sends `StealInteractRequest` like `[E]` instead of `CaptureRequest` (capture only allows `WorldCreature`, which caused “Invalid target”). Tooltip text for stealables updated. **HUDClient.client.lua** – Removed duplicate `CaptureFail` toast; `CaptureClient` already notifies and resets capture UI.

## 2026-04-18 12:00
- **CreatureModelLoader.lua** – `IntegrateTemplate` no longer calls `IsA` on a `Model` template after `Destroy()`; use a `templateWasModel` flag so rigged model loads do not error inside `pcall` and fall back to placeholder orbs.

## 2026-03-28 19:00
- **MainServer.server.lua**, **IngredientsMenuClient.client.lua** – Cooking mix: new `CraftingMixPlaceAt` RemoteFunction wired server-side; chef slots 1–4 accept **tap after selecting an ingredient** (empty slot places, filled slot replaces/stacks when something is selected, otherwise removes). Non–cook-mode mix list Remove uses real slot indices.

## 2026-03-28 17:30
- **IngredientSpawnSystem.lua** – CookNPC gets a green `Highlight` (`CookNPCHighlight`) so the chef reads clearly in the hub.

## 2026-03-28 17:00
- **IngredientSpawnSystem.lua**, **GameConfigData.lua**, **IngredientsMenuClient.client.lua** – Replaced arena `Campfire` part with hub **CookNPC**: clone `ReplicatedStorage.CookNPC`, place at `Broker + Cooking.CookNPC.OffsetFromBrokerStuds` (raycast Y, `pitch=90` upright, broker-facing), ProximityPrompt “Cook”; retries until Broker exists; client listens for `CookNPC` (+ legacy `ArenaCampfire`) tags.

## 2026-03-28 16:15
- **GameConfigData.lua** – `SiegeMaster.ExtraRotationDegrees` set to `pitch = 90` (same as Curator/Broker) so the Siege Master mesh stands upright instead of lying flat; reset yaw to 0 so facing follows the Broker’s orientation.

## 2026-03-28 15:00
- **SiegeMasterSystem.lua**, **GameConfigData.lua** – Siege Master spawns opposite The Curator: `Broker − ArenaTrader.OffsetFromBrokerStuds` (mirror of Curator’s `Broker + offset`); fallback mirrors spawn-offset when Broker is absent; pre-placed `SiegeMasterNPC` is re-pivoted on init when a spawn frame resolves.

## 2026-03-28 14:30
- **IngredientsMenuClient.client.lua**, **GameConfigData.lua**, **PlayerDataManager.lua**, **IngredientData.lua** – Campfire mix capped at four ingredients: diamond UI shows four slots only; `GameConfig.Cooking.MaxMixIngredients` set to 4 with matching server/normalize defaults and mix header text “3–4 items”.

## 2026-03-28 12:00
- **IngredientsMenuClient.client.lua** – Rebuilt campfire cooking UI: “Master Chef” layout with teal-framed panel, ingredient cards with icon tiles, diamond mix slots (up to five), gold-rimmed rotating “Combine Results” hub, recipe log strip, and responsive larger window in cook mode; ingredient-only (`I`) view keeps the classic bank + mix columns.

## 2026-03-27 14:45
- **CreatureSpawner.lua**, **BadlandsClient.client.lua**, **BadlandsSystem.lua** – Resolved git merge conflicts: kept cave terrain fallback + `CreatureData` outer-biome pairing for dungeon/boss/zone spawns; BadBag HUD uses favorite-card vertical alignment with panel anchored below the button; sacrifice queue rejects both `favoriteUid` and legacy `favoriteCreature`.

## 2026-03-27 12:00
- **BadlandsClient.client.lua** – Moved the BadBag HUD button down by one full control height so it lines up with the favorite card row and stays on-screen; clicking it now opens Sieglinq on the BadBag tab via `HUDToggleMenu` instead of the legacy floating bag panel.

## 2026-03-21 00:59
- **BadlandsSystem.lua** – Restored direct queue-join compatibility after the stricter Broker-only gate likely blocked the existing Badlands teleport path during testing.

## 2026-03-21 00:45
- **BadlandsSystem.lua** – Locked direct `BadlandsQueueJoin` calls behind the Broker contract flow so players now need a validated sacrifice before the server will queue or teleport them.

## 2026-03-21 00:41
- **BadlandsClient.client.lua** – Wired `BadlandsBagUpdate` into the active HUD so the bag button and panel refresh outside extraction, including on run start and when bag state changes.
- **BadlandsSystem.lua** – Added server-side bag serialization/update helpers plus APIs for capturing Badlands creatures directly into the run bag and switching the active bag slot.
- **CaptureSystem.lua** – Routed Badlands captures away from the normal inventory/cost flow and into the Badlands bag pipeline while preserving the regular world capture behavior elsewhere.
- **CaptureClient.client.lua** – Added a Badlands-specific capture success toast so captured creatures no longer open the normal assignment prompt when they are stored in the Badlands bag.

## 2025-03-05 12:05
- **.cursor/rules/update-logging.mdc** – Added Cursor rule: when editing Lua scripts, update UPDATES.md (top timestamp + new entry) and per-file `-- Last updated: YYYY-MM-DD HH:MM` comment.

## 2025-03-05 12:00
- **UPDATES.md** – Created update log (memory file) per Memory File and Update-Tracking Plan. Top timestamp and reverse-chronological entries for codebase integrity.
