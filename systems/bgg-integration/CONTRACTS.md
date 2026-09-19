# BGG Integration System contracts

Collection snapshots; canonical collection fields; reconciliation and duplicate-copy reports; pending rating updates. The queue writer still lives in Ranking until the state-ownership refactor.

The existing persisted shapes remain defined in the
[data contracts](../../.agents/context/contracts.md). This migration does not
split or rewrite stored data. Ownership above records the intended responsibility;
the system map explicitly lists implementation differences.
