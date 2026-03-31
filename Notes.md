# Audit Notes - 2026-03-11

## Scope
- Read-only audit of server gameplay, persistence, trading, capture, combat, raid, shop, and CLI simulation paths.
- No gameplay code modified during this pass.

## What I Ran
- `powershell -ExecutionPolicy Bypass -File .\tools\sim\run.ps1 -Scenario .\tools\sim\scenarios\favorite-base-flow.json`
- `powershell -ExecutionPolicy Bypass -File .\tools\sim\run.ps1 -Scenario .\tools\sim\scenarios\combine-evolve-flow.json`
- `powershell -ExecutionPolicy Bypass -File .\tools\sim\run.ps1 -Scenario .\tools\sim\scenarios\cosmetics-synergy-flow.json`
- `powershell -ExecutionPolicy Bypass -File .\tools\sim\run.ps1 -Scenario .\tools\sim\scenarios\capture-flow.json`
- One-off temp scenario proving duplicate-UID combine succeeds with a single owned creature.

## Confirmed Findings
- `PlayerDataManager.OnPlayerJoin` falls back to default data on DataStore read failure and then immediately saves, which can wipe existing profiles if `GetAsync` fails transiently.
- `PlayerDataManager.CombineCreatures` accepts the same UID three times. Confirmed via CLI: one `breezee` combined into one `Silver breezee`.
- `PlayerDataManager.RecycleDuplicates` has the same repeated-UID issue by inspection.
- `EggShopSystem.BuyEgg` spends coins before `hatchEgg` re-checks inventory capacity, so a failed hatch can still consume currency.
- `TradeSystem.completeTrade` validates once, then performs transfers without checking return values or rolling back on partial failure.
- `RaidSystem` tracks only raider -> victim, so multiple raiders can hit the same victim concurrently before protection starts.
- `PlayerDataManager.DoRebirth` does not clear `eggs`, which looks like a stash path around the intended rebirth reset.

## Operational Notes
- Worktree was already dirty before this audit. Do not mass-revert.
- `git status` in this repo needs `-c safe.directory='A:/New folder/OneDrive/Documents/Roblox Scripts'`.
- Existing docs already capture prior UI/slot regressions:
  - `INVENTORY_REM_FAV_UI_BUG_REPORT.md`
  - `FAVORITE_AND_BASE_SLOTS_CHANGELOG.md`

## Suggested Next Pass
- Fix save-load failure handling first. That is the highest-risk issue because it can destroy player progress.
- Add server-side uniqueness checks for any action that consumes multiple UIDs.
- Extend the CLI with negative-path scenarios:
  - duplicate UID combine
  - duplicate UID recycle
  - egg buy with full inventory
  - concurrent trade capacity change
  - rebirth with eggs present
- Add a short "remote trust model" doc: which remotes rely on client UX only vs enforced on server.

## Targeting Note - 2026-03-11
- Direct tap/click targeting in `CaptureClient.client.lua` was using `highlightTarget` and `getEffectiveTargetRange` before those locals were declared.
- The target bar path worked because it is defined after those helpers.
- Fixed by forward-declaring the shared helpers and assigning the later definitions into those same locals so both direct-touch and menu targeting use the same functions.
