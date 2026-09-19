# What Am I Missing System

Owns discovery of overlooked games and expansions. Candidate discovery is separate from predicting enjoyment.

## Implementation

`expansions/`. Designer-based candidate discovery is not implemented.

Existing skill script paths remain compatibility entrypoints. Run commands from
the repository root; default data paths retain that convention.

## Boundaries

See the [agreed system map](../../.agents/context/system-map.md) for responsibilities,
cross-system workflows and the explicitly unfinished hexagonal refactor.
Each system owns its operations; workflows coordinate them. No predictions or
discovery results authorize changes to the operator's personal preferences.

## Contracts and verification

- [Current contracts](CONTRACTS.md)
- Regression checks live in this system's tests directory and run through
  the repository check. They use local fixtures, not live BGG writes.
