# BoardGameGeek Export Scripts (PowerShell + bgg-mcp)

This repo contains PowerShell scripts to export BoardGameGeek data using the [`kkjdaniel/bgg-mcp`](https://github.com/kkjdaniel/bgg-mcp) MCP server.

## What You Get

- `scripts/Start-BggMcpServer.ps1`: starts `kdaniel/bgg-mcp` in HTTP mode using Docker
- `scripts/Export-BggPlayedGames.ps1`: exports all games with recorded plays
- `scripts/Export-BggStackRank.ps1`: groups played games and generates proposed ratings
- `scripts/Export-BggTop10.ps1`: exports your top rated games (default top 10)
- `scripts/New-BggRatingUploadSheet.ps1`: creates a CSV sheet for applying unrated game ratings in BGG

## Prerequisites

- PowerShell 7+
- Docker
- BoardGameGeek username
- Optional: `BGG_API_KEY` for authenticated access and better reliability

## VS Code MCP Setup

This workspace includes [`.vscode/mcp.json`](.vscode/mcp.json) with a `bgg` MCP server configured for username `MrHinsh`.

Set your API key in your shell before launching VS Code (or before MCP starts):

```powershell
$env:BGG_API_KEY = "YOUR_BGG_API_KEY"
```

Then open/reload this workspace in VS Code and start the `bgg` MCP server from the MCP view.

## 1) Start the MCP server

```powershell
./scripts/Start-BggMcpServer.ps1 -Username "YOUR_BGG_USERNAME" -ApiKey "YOUR_BGG_API_KEY"
```

This starts an MCP endpoint at:

- `http://localhost:8080/mcp`

## 2) Export played games

```powershell
./scripts/Export-BggPlayedGames.ps1 -Username "YOUR_BGG_USERNAME"
```

Output:

- `output/played-games.json`
- `output/played-games.csv`

## 2b) Stackrank and propose ratings

```powershell
./scripts/Export-BggStackRank.ps1 -InputPath ".\output\played-games.json"
```

Output:

- `output/stackranked-games.json`
- `output/stackranked-games.csv`

## Ranking Context

The ranking workflow is designed for large collections where comparing every game to every other game is too costly.

- First export all played games with your current BGG personal rating.
- Then rank inside rating buckets rather than across the whole collection.
- Duplicate game entries are collapsed by BGG ID, keeping the entry with the highest personal rating.

Current rating remap for stackranking:

- 10s are ranked into `9.000` -> `9.999`
- 9s are ranked into `8.000` -> `8.999`
- 6s are ranked into `5.000` -> `5.999`
- In general, bucket `N` maps to `(N-1).000` -> `(N-1).999`

This keeps reranking focused inside each source bucket and avoids immediate cross-bucket churn.

## Goals

- Keep the integer intent of your current ratings while refining order inside each level.
- Use decimal precision (`x.000` -> `x.999`) to represent stackrank position.
- Build a reviewable promotion flow instead of auto-promoting across integer levels.

Recommended promotion policy:

- Do not auto-promote between integer buckets in the same pass.
- Treat top items in each remapped band as promotion candidates only.
- Decide promotions manually after review.
- Treat 10s as a special manual-curation lane (rank in 9.xxx, then set final 10s explicitly).

## 3) Export top 10 by your ratings

```powershell
./scripts/Export-BggTop10.ps1 -Username "YOUR_BGG_USERNAME" -Top 10
```

Output:

- `output/top-games.json`
- `output/top-games.csv`

## 4) Build a rating upload sheet

```powershell
./scripts/New-BggRatingUploadSheet.ps1
```

Output:

- `output/bgg-rating-upload-sheet.csv`

This sheet includes `new_rating` (blank for you to fill) and a direct `bgg_game_url` for each game.

## Notes

- Top list is sorted by your personal rating descending, then play count descending.
- By default, scripts filter to base games (`subtype = boardgame`) and exclude expansions.
- Add `-IncludeExpansions` if you want expansions included.
