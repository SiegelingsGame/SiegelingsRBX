# UI Design Standard (SiegelinQ)

This document is the **single source of truth** for UI styling and interaction patterns used in this repo’s Roblox UI scripts.

## Principles
- **Consistency over novelty**: reuse the same spacing, typography, and button styles across screens.
- **Inventory is split-view**: list/grid on the left, details/actions on the right (desktop); adapt for mobile.
- **No secrets in repo**: API keys and private keys must **never** appear in `design.md` or git-tracked files.

## Tokens

### Color tokens
Use these semantic names (do not hardcode random RGB values unless adding a new token):
- **bg**: app background
- **bgLight**: panels / header backgrounds
- **card**: interactive surfaces (tiles, rows, bars)
- **divider**: strokes/dividers
- **text**: primary text
- **textSec**: secondary text
- **textMut**: muted/help text
- **accent**: brand/primary highlight
- **income**: income slot status/actions
- **defense**: defense slot status/actions
- **favorite**: favorite status/actions
- **battle**: battle status

Reference implementation (current): `InventoryUIManager.client.lua` uses a `C = { ... }` table mapping these tokens to `Color3.fromRGB(...)`.

### Typography
- **Titles**: `GothamBlack` @ 14–18
- **Primary buttons**: `GothamBlack`/`GothamBold` @ 11–12
- **Body**: `GothamMedium` @ 10–12
- **Muted**: `GothamMedium` @ 9–11 with `textMut`

### Spacing & radii
- **Gaps**: 6–8px between controls; 10–14px outer padding inside panels.
- **Corner radius**: 7–10px for buttons/tiles; 10–16px for major panels.

## Components (patterns to copy)

### Window shell
- Header with title + close button
- Stats strip (coins, plot, etc.)
- Tab bar
- Content region

### Inventory split view (desktop)
- Left: scroll container with **grid tiles**
- Right: detail panel with large viewport and details
- Bottom (inventory only): **global sell bar** with multi-select actions

### Buttons
- Enabled: token color background + readable text
- Disabled: `divider` background + `textMut` text; `Active=false` and `AutoButtonColor=false`

### Selection stroke
Use a `UIStroke` named `SelectionStroke` on tiles/rows:
- Thickness 2
- Color `favorite`
- Enabled only for selected UID

## Layout rules

### Desktop vs mobile
Use existing `MobileWindowLayout` + breakpoints:
- If in mobile layout, keep the same visual language but reduce cell sizes and spacing.
- If space is constrained, prioritize: selection grid → details → actions.

### Inventory tab isolation
Changes to inventory UI must **not** impact other tabs:
- Bag/Battle/BadBag should keep their own renderers.
- Shared containers must preserve persistent children used by other tabs.

## Auto-sell behavior
- Auto-sell uses **rarity toggles-to-sell**.
- **Favorites are protected** from selling by default.

## Optional: `designmd-mcp` (local-only)
If you use the `designmd` MCP server, configure it **locally** and keep keys out of git:

Example (local settings; do not commit keys):

```json
{
  \"mcpServers\": {
    \"designmd\": {
      \"command\": \"npx\",
      \"args\": [\"designmd-mcp\"],
      \"env\": {
        \"DESIGNMD_API_KEY\": \"<set in your environment, not in repo>\"
      }
    }
  }
}
```

Recommended approach:
- Set `DESIGNMD_API_KEY` in your OS environment variables, or in a **local untracked** config file.
- Add any local config file to `.gitignore` if needed.

