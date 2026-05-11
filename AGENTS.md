# Agent Operating Guide

Start here before making changes.

## Read Order

1. Read guardrails first.

- `.agents/guardrails/global-rules.md`
- `.agents/guardrails/auth-and-secrets.md`

1. Read context next.

- `.agents/context/system-map.md`
- `.agents/context/contracts.md`
- `.agents/context/ratting-system.md`
- `.agents/context/tier-ranking-formula.md`
- `.agents/context/ops-runbook.md`
- `.agents/context/handoff.md`

## Intent

- Guardrails define non-negotiable policy.
- Context defines current system facts, contracts, and operator workflow.
- Skills under `.agents/skills` execute the work.

## Core Repository Expectations

- Do not store secrets in tracked files.
- Use `.local` for local secret/cache material.
- Keep data flow order: fetch -> reconcile -> rank/report -> tier/rebalance/publish.
- Preserve script entrypoints unless explicitly asked to change them.

## Auth Expectations

- Scripted password login can be blocked by Cloudflare.
- Use `Login-Bgg.ps1` and cached cookie flow as the primary operator path.
- Write-to-BGG scripts use local cached cookie path.

## Contract Discipline

- Treat `.agents/context/contracts.md` as schema contract source of truth.
- Treat `.agents/context/ratting-system.md` as workflow source of truth for tier/rank process.
- Treat `.agents/context/tier-ranking-formula.md` as ranking conversion source of truth.
- If code behavior changes, update those files in the same change set.
