# Handoff Notes

## Current Auth Reality
- Password-based scripted login may fail with Cloudflare 403.
- Browser cookie import is the reliable fallback.

## Current Repo Policy
- Write scripts must resolve cookie from `.local` cache or explicit override.
- MCP calls should not pass `BGG_COOKIE` as query parameter.

## Next Checks For Any Agent
1. Confirm cookie cache exists at `.local/secrets/bgg-session.json`.
2. Confirm canonical file exists at `data/working/canonical/games.json`.
3. Run parse checks on any edited PowerShell scripts.

## When Editing Skills
- Preserve existing script entrypoints where possible.
- Keep output paths aligned with `data/` structure.
- Avoid introducing new secret storage locations.

## Current Command Surface
- Prefer `mrhinsh-bg-pull` for the end-to-end local rebuild flow.
- Prefer `mrhinsh-bg-push` for syncing queued BGG ratings.
- Older lower-level skills still exist for targeted maintenance work.
