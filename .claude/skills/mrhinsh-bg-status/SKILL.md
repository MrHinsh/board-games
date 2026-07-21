---
name: mrhinsh-bg-status
description: Brief the operator on the board-games pipeline - collection counts, unrated games, pending rating pushes, anomalies. Read-only and cheap; use for "what's the state of my games data" or before deciding to pull/rate/push.
---

Run the status script and narrate the result for the user — do not read data files directly:

```powershell
./scripts/Get-BgStatus.ps1
```

Briefing guidance:

- Lead with actionable items: unrated games with plays (rating session candidates),
  queue entries with changes (push candidates), and any `queue_large_deltas` (flag these
  for the user's review — never judge them yourself).
- Mention data freshness via `last_snapshot`; suggest `/mrhinsh-bg-pull` if stale.
- Never propose ratings or orderings — those are the operator's judgment alone.
