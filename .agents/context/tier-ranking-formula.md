# Tier And Ranking Formula

This spec defines conversion from tier plus rank-in-tier to BGG-compatible decimal ranking bands used by stackrank outputs.

## Tier Definitions

Primary tier mapping:
- S -> 10
- A -> 9
- B -> 8
- C -> 7
- D -> 6
- F -> merged single tier spanning 1.000..4.999
- U -> 0 (unrated)

Interpretation:
- U is excluded from ranked scoring.
- F is one logical ranking group even if items originated from integer ratings 1..5.
- Source bucket may be retained as provenance, but F rebalance ignores it for grouping.

## Variables

- t: tier label in {S, A, B, C, D, F, U}
- b: source integer bucket in 1..10
- r: rank in tier bucket, 1-based (1 is best)
- n: total items in that same tier bucket

## Bucket Selection

For S/A/B/C/D:
- b = {10, 9, 8, 7, 6} respectively

For F:
- use a merged F band from 1.000 to 4.999.

For U:
- no bucket conversion; keep rating 0.

## Target Band Base

Base band value is:

$$
base = \max(b - 1, 1)
$$

Examples:
- b=10 -> base=9 (range 9.000 to 9.999)
- b=9 -> base=8 (range 8.000 to 8.999)
- b=1 -> base=1 (range 1.000 to 1.999)

Merged F uses a different band:

$$
F_{min} = 1.000, \quad F_{max} = 4.999
$$

## Rank-In-Tier To Decimal

If n = 1:

$$
proposed = base + 0.999
$$

If n > 1:

$$
proposed = \mathrm{round}\left(base + \frac{(n-r)}{(n-1)} \times 0.999,\ 3\right)
$$

For F tier, use the merged band instead:

If n = 1:

$$
proposed_F = 4.999
$$

If n > 1:

$$
proposed_F = \mathrm{round}\left(1 + \frac{(n-r)}{(n-1)} \times 3.999,\ 3\right)
$$

Properties:
- r=1 maps to highest value in band (near base+0.999).
- r=n maps to lowest value in band (base+0.000).
- Values are monotonic by rank.

## Worked Examples

Example 1: A tier game, rank 1 of 5
- b=9, base=8, r=1, n=5
- proposed = round(8 + (4/4)*0.999, 3) = 8.999

Example 2: A tier game, rank 5 of 5
- b=9, base=8, r=5, n=5
- proposed = round(8 + (0/4)*0.999, 3) = 8.000

Example 3: S tier singleton
- b=10, n=1
- proposed = 9.999

Example 4: merged F tier, rank 1 of 10
- proposed_F = round(1 + (9/9)*3.999, 3) = 4.999

Example 5: merged F tier, rank 10 of 10
- proposed_F = round(1 + (0/9)*3.999, 3) = 1.000

## Validation Rules

- Reject n < 1.
- Reject r < 1 or r > n.
- Reject tier U for conversion; U remains 0.
- F no longer requires grouping by source bucket.
