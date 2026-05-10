# BoardGameGeek Export Scripts (PowerShell + bgg-mcp)

This repo contains PowerShell scripts to export BoardGameGeek data using the [`kkjdaniel/bgg-mcp`](https://github.com/kkjdaniel/bgg-mcp) MCP server.

## What You Get

- `scripts/Start-BggMcpServer.ps1`: starts `kdaniel/bgg-mcp` in HTTP mode using Docker
- `scripts/Export-BggPlayedGames.ps1`: exports all games with recorded plays
- `scripts/Export-BggTop10.ps1`: exports your top rated games (default top 10)

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

## 3) Export top 10 by your ratings

```powershell
./scripts/Export-BggTop10.ps1 -Username "YOUR_BGG_USERNAME" -Top 10
```

Output:

- `output/top-games.json`
- `output/top-games.csv`

## Notes

- Top list is sorted by your personal rating descending, then play count descending.
- By default, scripts filter to base games (`subtype = boardgame`) and exclude expansions.
- Add `-IncludeExpansions` if you want expansions included.
