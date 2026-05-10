# Global Guardrails

## Purpose
This file defines non-negotiable rules for agents working in this repository.

## Source Of Truth
- Treat files under `data/working/canonical/` as the canonical working dataset.
- Treat files under `data/raw/` as immutable snapshots.
- Never overwrite immutable snapshots in place.

## Workflow Order
- Follow this order for refresh operations:
  1. Fetch raw snapshot
  2. Reconcile into canonical
  3. Rank and report
- Do not skip reconcile when canonical may contain manual edits.

## Safety Rules
- Never commit secrets, cookies, tokens, or credential material.
- Never print full cookie values to logs or terminal output.
- Never write auth material into tracked files under `data/`, `.agents/skills/`, or repo docs.
- Always mask sensitive values in human-facing output.

## Script Change Rules
- Preserve existing script entrypoints and parameter names unless explicitly asked to break them.
- Prefer additive changes and backward-compatible defaults.
- Keep PowerShell scripts strict (`Set-StrictMode -Version Latest`).

## MCP Rules
- MCP calls should not pass cookie values through query parameters.
- MCP authentication should be configured through server environment configuration only.

## Write Operation Rules (BGG web writes)
- Any script performing direct writes to BGG web endpoints must resolve auth cookie from local cache first.
- Default cookie cache location is `.local/secrets/bgg-session.json`.
- Write scripts may accept explicit `-Cookie` override for emergency/manual operations.

## Definition Of Done
- Script parses without syntax errors.
- Behavior matches guardrails in this file.
- Any changed auth path is validated with a non-destructive path or parse check.
