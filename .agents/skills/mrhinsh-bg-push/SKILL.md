# mrhinsh-bg-push

Purpose:
- Push pending personal ratings from the local publish queue to BoardGameGeek.
- Provide a single user-facing command surface for the write side of the workflow.

Inputs:
- `$Username` - BGG username used to resolve collection and auth context.
- `$QueuePath` - optional path to the pending rating queue.
- `$Limit` - optional cap for partial sync runs.

Outputs:
- Queue sync summary object from `Sync-BggRatingQueue.ps1`.
- Updated queue file with successfully synced entries removed.

Preconditions:
- Valid BGG cookie cache or environment auth is available.
- Internet access to boardgamegeek.com.
- Pending rating queue exists.

Postconditions:
- Queued personal rating updates are submitted to BGG using the existing sync implementation.

Idempotency:
- Safe to re-run. Items already removed from the queue are not retried.

Failure Modes:
- Missing queue file, auth failure, HTTP non-200 response, or games that cannot be matched to a writable BGG item.

Examples:
```powershell
./.agents/skills/mrhinsh-bg-push/scripts/run.ps1 -Username "MrHinsh"
./.agents/skills/mrhinsh-bg-push/scripts/run.ps1 -Username "MrHinsh" -WhatIf
```