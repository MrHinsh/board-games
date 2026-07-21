# mrhinsh-bg-shared

Shared function library dot-sourced by other skills. Not runnable on its own —
`scripts/run.ps1` intentionally throws.

## Contents

- `scripts/Invoke-BggMcp.ps1` — MCP JSON-RPC helpers for the local bgg-mcp server:
  `Invoke-McpRequest` (POST a tool call to the endpoint) and `Get-McpTextFromResponse`
  (extract/validate the text payload from an MCP result).
- `scripts/BggTierHelpers.ps1` — data-file helpers used by the tier/rank skills:
  JSON read/write with defaults (`Read-JsonFile` etc.) and tier conversion utilities
  implementing the rules in `.agents/context/rating-system.md`.

## Usage

```powershell
. "$PSScriptRoot\..\..\mrhinsh-bg-shared\scripts\Invoke-BggMcp.ps1"
. "$PSScriptRoot\..\..\mrhinsh-bg-shared\scripts\BggTierHelpers.ps1"
```

## Rules

- Changes here affect every consuming skill — run `./scripts/Test-Repo.ps1` after edits.
- Keep functions side-effect free except for explicit file read/write helpers.
- MCP auth material must never be passed via query parameters (see guardrails).
