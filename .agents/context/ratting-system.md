# Ratting System

This document defines how this repository rates games and converts tier plus rank-in-tier into BGG-compatible decimal ordering.

## What We Are Doing

1. Refresh canonical data:
- Fetch snapshot from BGG
- Reconcile snapshot into canonical data

2. Build ranking artifacts:
- Generate stackrank output from canonical ratings
- Generate unrated intake list for operator scoring

3. Rate unrated games:
- Operator assigns integer ratings (1..10) using intake sheet/workflow
- Import ratings back into canonical dataset

4. Rebuild outputs:
- Re-run stackrank and top report after rating updates

## Tier Mapping

- S tier -> 10
- A tier -> 9
- B tier -> 8
- C tier -> 7
- D tier -> 6
- F tier -> 1..5
- U tier -> 0 (unrated)
- X tier -> exit collection marker, excluded from ranked conversion

Notes:
- U is not converted to ranked decimal score; it stays 0.
- F tier spans multiple integer buckets, so the source bucket must be explicit when converting.

## Variables

- t: tier label in {S, A, B, C, D, F, U, X}
- b: integer source bucket in 1..10
- r: rank in tier bucket (1-based, 1 is best)
- n: number of games in that same tier bucket

## Bucket Selection

For S/A/B/C/D:
- b = 10/9/8/7/6 respectively

For F:
- b must be explicitly selected in 1..5

For U:
- no conversion, keep rating 0

For X:
- no conversion, keep current canonical rating unchanged

## Conversion Formula

Base band:

base = max(b - 1, 1)

If n = 1:

proposed = base + 0.999

If n > 1:

proposed = round(base + ((n - r) / (n - 1)) * 0.999, 3)

## Band Examples

- b = 10 -> band 9.000..9.999
- b = 9  -> band 8.000..8.999
- b = 1  -> band 1.000..1.999

## Worked Examples

Example A (A-tier, rank 1 of 5):
- b = 9, base = 8, r = 1, n = 5
- proposed = round(8 + (4/4)*0.999, 3) = 8.999

Example B (A-tier, rank 5 of 5):
- b = 9, base = 8, r = 5, n = 5
- proposed = round(8 + (0/4)*0.999, 3) = 8.000

Example C (S-tier singleton):
- b = 10, n = 1
- proposed = 9.999

## Validation Rules

- n must be >= 1
- r must satisfy 1 <= r <= n
- tier U cannot be converted
- tier X cannot be converted
- tier F requires explicit source bucket b in 1..5

## Source Of Truth

- Contracts: .agents/context/contracts.md
- Formula spec: .agents/context/tier-ranking-formula.md
