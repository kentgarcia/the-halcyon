# tools/mcp — local MCP server installs

This folder holds the local install of the Blockbench MCP server. Both servers are registered for Claude Code in a project-root `.mcp.json`. That file holds machine-specific absolute paths, so it is not committed; recreate it locally (see the table below for the commands).

`.gdignore` is here on purpose: it stops the Godot editor from scanning and importing `node_modules`. Don't delete it.

| `.mcp.json` name | What | How it runs | Pinned to |
|---|---|---|---|
| `bbmodel` | Blockbench MCP (`blockbench-mcp-headless`) — create/edit/validate/render `.bbmodel` files, no Blockbench app needed | `node tools/mcp/blockbench/node_modules/blockbench-mcp/bin/blockbench-mcp-headless.mjs --root art/models` | commit `97a8a80d3a37bf95c5e136d93d2c7da399fff753` (v1.10.1), recorded in `blockbench/package.json` + `package-lock.json` |
| `godot` | Godot runtime MCP (`godot-mcp-runtime`) — run/inspect/edit the project with the Godot binary, headless-capable | `npx -y godot-mcp-runtime@4.0.1` with `GODOT_PATH` → Godot 4.7.2 stable (Godots Flatpak) | npm `4.0.1` |

The separate **godot-ai** MCP (editor-plugin based, `mcp__godot-ai__*`) is registered per-user, not here, and needs the Godot AI plugin in `addons/` — not installed in this project yet.

## Why Blockbench is installed locally instead of via `npx`

`npx github:jasonjgardner/blockbench-mcp-plugin` only works while an old npx cache entry exists. On a cold cache, npm 10.9 fails (`GitFetcher requires an Arborist constructor…`), and a plain install fails because a dev dependency (`electron`) crashes in its postinstall (SIGILL on this machine). A local, pinned install avoids both and starts instantly (Claude Code times out slow MCP starts).

## Reinstall

```bash
cd tools/mcp/blockbench
ELECTRON_SKIP_BINARY_DOWNLOAD=1 npm ci --no-audit --no-fund
```

`ELECTRON_SKIP_BINARY_DOWNLOAD=1` is required here — the headless server doesn't need the Electron binary.

## Notes

- **Paths are absolute** in `.mcp.json` (`--root`, the server path, `GODOT_PATH`). Update them if the project moves or Godot is upgraded.
- **`bbmodel_render` / `bbmodel_contact_sheet` download and install a render engine on their first call** (per the tool description). Expect a delay and network access the first time.
- **Licence:** `blockbench-mcp` is GPL-3.0-only. It is a dev tool, not part of the game — don't bundle it into exports (the `.gdignore` keeps it out of Godot exports too).
- Claude Code asks you to **approve project-scoped MCP servers** from `.mcp.json` the first time a session starts here. Restart the session (or use `/mcp`) after changing this file.
- Don't edit one `.bbmodel` in the Blockbench app and via the MCP at the same time; pass `expected_revision` on MCP writes.
