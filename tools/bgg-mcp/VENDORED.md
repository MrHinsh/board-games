# Vendored: bgg-mcp

This directory is a vendored copy of the upstream BGG MCP server, not a submodule.

- Upstream: <https://github.com/kkjdaniel/bgg-mcp>
- Vendored at upstream commit: `efb395d` (2026)
- Local modifications: `tools/collection.go` — raw collection XML fallback (see `LOCAL-CHANGES.patch` for the exact diff against upstream)

## Updating from upstream

Clone upstream fresh, re-apply `LOCAL-CHANGES.patch`, and replace this directory.
Regenerate the patch if the local modification changes.

## Build

```powershell
cd tools/bgg-mcp
go build -o bgg-mcp.exe .
```

`bgg-mcp.exe` and `build/` are gitignored build artifacts.
