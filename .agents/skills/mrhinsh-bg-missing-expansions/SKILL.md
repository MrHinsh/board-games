# mrhinsh-bg-missing-expansions

For every base game you own, list the expansions that exist on BGG but that
you do not own. Read-only against BGG; writes a report under
`data/reports/expansions/` and caches per-game XML at `data/raw/bgg/details/`.

Requires the local bgg-mcp server running (for the owned-expansions lookup)
and `$env:BGG_API_KEY` (for the direct XML API calls that carry expansion
links — the MCP `bgg-details` tool does not expose them).

## Run

```powershell
./.agents/skills/mrhinsh-bg-missing-expansions/scripts/run.ps1 `
    -Username 'MrHinsh' -ApiKey $env:BGG_API_KEY
```

## Options

- `-CanonicalPath` — canonical games JSON. Default `.\data\working\canonical\games.json`.
- `-CacheDir` — per-game XML cache. Default `.\data\raw\bgg\details`.
- `-OutDir` — report output directory. Default `.\data\reports\expansions`.
- `-CacheMaxAgeDays` — reuse cached XML younger than this. Default 30.
- `-RequestDelayMs` — polite delay between BGG calls. Default 800.
- `-IncludeFanExpansions` — include fan/community expansions (default: excluded).
- `-IncludePromos` — include promos, merchandise, playmats, dice trays, mini
  card packs, convention exclusives, etc. (default: excluded).
- `-Tiers S,A` — restrict base games to the given tier codes (from
  `data/working/ranking/tier-membership.json`). Adds a `tier` column to CSV
  output and appends the tier suffix to output filenames.
- `-MembershipPath` — path to tier-membership JSON. Default
  `.\data\working\ranking\tier-membership.json`.

## Outputs

- `data/raw/bgg/details/<id>.xml` — cached XML per base game (immutable per fetch).
- `data/reports/expansions/missing-expansions.json` — grouped by base game.
- `data/reports/expansions/missing-expansions.csv` — one row per missing expansion.
- `data/reports/expansions/summary.md` — narrative summary.

## Rules

- Reports only. Never proposes adding expansions to the wishlist — that is
  operator judgment.
- BGG throttles: honour `-RequestDelayMs`, retry on 202/429, back off on repeat.
- Cache is authoritative when younger than `-CacheMaxAgeDays`. Delete the cache
  file to force a refresh for one game.

## System ownership

Implementation: `systems\what-am-i-missing\expansions/`. See `.agents/context/system-map.md`.
