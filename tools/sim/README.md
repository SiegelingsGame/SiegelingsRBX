# Simulation CLI

Run headless feature simulations from PowerShell without opening Roblox Studio.

## Usage

List the included scenarios:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\sim\run.ps1 -ListScenarios
```

Run a scenario:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\sim\run.ps1 -Scenario .\tools\sim\scenarios\favorite-base-flow.json
```

Print the final player snapshot too:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\sim\run.ps1 -Scenario .\tools\sim\scenarios\combine-evolve-flow.json -ShowState
```

## What It Covers

This first pass simulates rule-heavy systems that are useful to test outside Studio:

- inventory state
- income and defense slot assignment
- favorite exclusivity
- floor unlock gating
- battle team assignment
- creature capture economy and XP flow
- combine and evolve flows
- cosmetic purchases and auto-equip behavior
- effective stat calculations
- battle synergy summaries
- invariant checks that catch duplicate or impossible assignments

## Scenario Shape

Each scenario is a JSON file with:

- `players`: starting state for one or more players
- `steps`: ordered actions and assertions
- `configOverrides`: optional balance overrides
- `catalog`: optional creature definitions to extend or replace the built-in sample catalog

Supported step actions:

- `add_creature`
- `grant_coins`
- `grant_gems`
- `grant_player_xp`
- `capture`
- `assign_base`
- `assign_defense`
- `set_favorite`
- `clear_favorite`
- `buy_floor`
- `assign_battle`
- `remove_battle`
- `combine`
- `evolve`
- `buy_cosmetic`
- `effective_stats`
- `battle_synergies`
- `expect`
- `expect_creature`
- `assert_invariants`

## Current Boundary

This CLI is intentionally state-focused. It does not emulate Roblox instances, workspace placement, AI movement, remotes, or rendering. For new features, the easiest path is to keep extracting rule logic into scenario-friendly state transitions and test those here first.
