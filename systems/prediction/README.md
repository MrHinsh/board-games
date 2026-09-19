# Prediction System

Owns advisory enjoyment predictions, model evidence, club nomination guidance and conference-preview ranking. Predictions do not become personal ratings.

## Implementation

`model/`, `club-nominations/` (including its config and name overrides), and
`conference-previews/`. Conference previews are another candidate source for the
same taste model; they do not maintain a separate preference model.

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
