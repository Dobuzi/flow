# Flow Phase 4 Tasks (Operator-Safe Live Activation Rollout)

## 1. Overview
Phase 4 extends the completed Phase 3 live-ingestion platform into an **operator-safe activation rollout layer**.

The focus is explicit control and auditable state transitions, not automation.

Core lifecycle for Phase 4:
`candidate snapshot -> operator-visible state -> guarded promote/demote decision -> explicit activation action -> last-known-good preservation -> guarded rollback -> audit-friendly history`

## 2. Phase 4 Objectives
- Add manual activation controls for eligible snapshot candidates.
- Add explicit demote/disable controls that do not silently mutate runtime behavior.
- Add guarded rollback execution with clear no-safe-rollback outcomes.
- Surface activation history and current activation state for operators.
- Keep source-level visibility truthful (`active`, `candidate`, `ineligible`, `rolled_back`).
- Preserve backward compatibility for `bundledSample`, `seoulCapitalSnapshot`, and `koreaNational`.

## 3. In Scope
- Activation command models and execution result/error semantics.
- Promote/demote/rollback command execution service.
- Activation history event model and lightweight store.
- Activation-state metadata enrichment into dataset catalog/source state.
- Minimal operator-safe UI controls (Settings/operator panel level).
- Confirmation/guardrail semantics for risky actions.
- Regression and integration tests for activation safety and source isolation.

## 4. Out of Scope
- Fully automated production activation rollout.
- Distributed control plane or multi-region orchestration.
- RBAC/authorization system for multi-user operations.
- Production telemetry backend or external observability platform.
- Major UI redesign or broad ops dashboard.
- ML-based activation scoring/decisioning.

## 5. Architecture Extensions
Existing baseline (preserved):
- `DatasetVersionStore` + `DatasetManifestIndex`
- `SnapshotActivationPolicy` + rollback primitives
- refresh state reporting and catalog live metadata enrichment
- activation-aware query resolution

Phase 4 additive components:
- **Activation Command Layer**: typed promote/demote/rollback commands.
- **Activation Execution Service**: guarded command handling and state transitions.
- **Activation History/Audit Store**: append-only event record for operator actions.
- **Operator-Safe Control Surface**: minimal UI for explicit activation actions.
- **Guarded Runtime Activation Integration**: controlled handoff to activation-aware query consumption.

Design constraints:
- Reuse current version store, policy, resolver, and metadata seams.
- Keep runtime reads snapshot-first and explicit.
- No implicit auto-activation side effects.

## 6. Milestones
- **M4-1 Activation Command Primitives**
- **M4-2 Activation History and Audit State**
- **M4-3 Guarded Promote/Demote Flow**
- **M4-4 Rollback Execution Controls**
- **M4-5 Minimal Operator UI and Visibility**
- **M4-6 Regression and Rollout Safety**

## 7. Task Breakdown

### M4-1 Activation Command Primitives

## P4-001 — Define activation command and execution result primitives
- Priority: P0
- Dependency: None
- Description: Add command models for `promote`, `demote`, `rollback`, plus typed execution results and error categories.
- Short goal: Standardize operator actions with explicit, testable semantics.
- Status: Completed (2026-03-10)
- Notes: Added command primitives (`SnapshotActivationCommand`, `PromoteSnapshotCommand`, `DemoteSnapshotCommand`, `RollbackSnapshotCommand`) with shared context/trigger metadata and validation semantics; added typed execution primitives (`SnapshotActivationExecutionResult`, execution statuses, block/failure reasons) and compatibility mapping helpers from existing activation/rollback decision models.

## P4-002 — Define activation guard policy inputs and decision model
- Priority: P0
- Dependency: P4-001
- Description: Model preconditions (eligibility, compatibility, source match, LKG presence) and decision outcomes (`allowed`, `blocked`, `requiresConfirmation`).
- Short goal: Make risky activation conditions explicit before execution.
- Status: Completed (2026-03-10)
- Notes: Added `SnapshotActivationGuardInput` and `SnapshotActivationGuardDecision` primitives with typed status (`allowed`, `blocked`, `noOp`, `requiresConfirmation`) and structured reasons. Included baseline guard evaluation semantics for promote/demote/rollback using current activation state, live-capability, candidate metadata, and existing activation/rollback policy outputs.

## P4-003 — Add activation command validation layer
- Priority: P1
- Dependency: P4-001, P4-002
- Description: Validate commands against source identity, candidate existence, and current activation state.
- Short goal: Reject invalid commands before state mutation.
- Status: Completed (2026-03-10)
- Notes: Added `SnapshotActivationCommandValidating` with `DefaultSnapshotActivationCommandValidator`, typed validation result/issues, and context-aware checks for malformed command context, contradictory command inputs, source mismatch, and static-source rollback misuse. Wired guard baseline decision to use validator output before guard-policy evaluation.

### M4-2 Activation History and Audit State

## P4-004 — Define activation history event model
- Priority: P0
- Dependency: P4-001
- Description: Add event schema for `promoted`, `demoted`, `rollback_started`, `rollback_succeeded`, `rollback_failed`, including actor/reason/timestamp metadata.
- Short goal: Ensure every operator action is auditable.
- Status: Completed (2026-03-10)
- Notes: Added `SnapshotActivationHistoryEvent` schema with typed event classification across promote/demote/rollback request/blocked/failed/succeeded outcomes, plus structured metadata and summaries for command context, validation, guard decision, and execution result compatibility.

## P4-005 — Implement activation history store (in-memory + extensible interface)
- Priority: P0
- Dependency: P4-004
- Description: Add append/read APIs for per-source activation history with deterministic ordering.
- Short goal: Provide reliable audit retrieval for UI and tests.
- Status: Completed (2026-03-12)
- Notes: Added `SnapshotActivationHistoryStoring` and `InMemorySnapshotActivationHistoryStore` with deterministic timeline ordering and typed query support (source, commandID, snapshotID, event type, limit, sort order). Added regression tests for append/list/filter/latest/ordering behavior.

## P4-006 — Add activation state projection from history + current policy state
- Priority: P1
- Dependency: P4-004, P4-005
- Description: Build projection model for operator-facing state (`active`, `candidate`, `lastKnownGood`, recent outcome).
- Short goal: Present concise activation status without reading raw events.

### M4-3 Guarded Promote/Demote Flow

## P4-007 — Implement activation execution service skeleton
- Priority: P0
- Dependency: P4-001, P4-002, P4-003, P4-005
- Description: Add coordinator/service that executes validated commands, applies guard decisions, and emits typed execution results.
- Short goal: Centralize operator action execution.

## P4-008 — Wire guarded promote flow to activation policy + version store
- Priority: P0
- Dependency: P4-007
- Description: Implement explicit promote flow for eligible candidate snapshots, preserving last-known-good before activation state switch.
- Short goal: Safe manual promotion path.

## P4-009 — Implement guarded demote/disable flow
- Priority: P1
- Dependency: P4-007
- Description: Add explicit demote action that reverts source from activated candidate to stable fallback without cross-source side effects.
- Short goal: Safe manual deactivation path.

### M4-4 Rollback Execution Controls

## P4-010 — Implement rollback command execution with no-safe-rollback semantics
- Priority: P0
- Dependency: P4-007, P4-008
- Description: Execute rollback to last-known-good when available; return explicit non-success result when no safe rollback target exists.
- Short goal: Deterministic and safe rollback behavior.

## P4-011 — Add rollback guard confirmations for high-risk transitions
- Priority: P1
- Dependency: P4-010
- Description: Add confirmation-required classification for rollback paths that can reduce data coverage/quality.
- Short goal: Prevent accidental risky rollbacks.

### M4-5 Minimal Operator UI and Visibility

## P4-012 — Add operator activation metadata to catalog/source enrichment
- Priority: P0
- Dependency: P4-006, P4-008, P4-010
- Description: Surface active snapshot, candidate readiness, last action, and rollback availability in live metadata.
- Short goal: Keep source status truthful and actionable.

## P4-013 — Add minimal operator controls UI (Settings or operator-safe panel)
- Priority: P1
- Dependency: P4-012
- Description: Add explicit controls for promote/demote/rollback on live-capable sources with disabled states when blocked.
- Short goal: Provide minimal but usable operator control surface.

## P4-014 — Add confirmation flows for promote/demote/rollback actions
- Priority: P1
- Dependency: P4-013
- Description: Add non-intrusive confirmations showing source, target snapshot, risk/guard notes, and expected outcome before execution.
- Short goal: Reduce accidental operator errors.

### M4-6 Regression and Rollout Safety

## P4-015 — Add activation execution integration tests
- Priority: P0
- Dependency: P4-008, P4-009, P4-010
- Description: Cover successful promote, blocked promote, demote, rollback success, and no-safe-rollback outcomes.
- Short goal: Lock activation/rollback lifecycle correctness.

## P4-016 — Add cross-source activation safety regression tests
- Priority: P0
- Dependency: P4-015
- Description: Ensure activation actions for one source do not mutate runtime/metadata behavior of unrelated sources.
- Short goal: Preserve mixed-source isolation guarantees.

## P4-017 — Add activation history consistency and audit tests
- Priority: P1
- Dependency: P4-005, P4-015
- Description: Verify event append order, projection correctness, and action-result/history consistency.
- Short goal: Guarantee auditability integrity.

## P4-018 — Phase 4 status sync and rollout readiness checklist
- Priority: P1
- Dependency: P4-012, P4-015, P4-016, P4-017
- Description: Synchronize docs and produce activation rollout checklist with operator runbook-style validation items.
- Short goal: Close Phase 4 with clear rollout confidence.

## 8. Execution Order
1. P4-001
2. P4-002
3. P4-003
4. P4-004
5. P4-005
6. P4-007
7. P4-008
8. P4-009
9. P4-010
10. P4-006
11. P4-011
12. P4-012
13. P4-013
14. P4-014
15. P4-015
16. P4-016
17. P4-017
18. P4-018

## 9. Parallelization Opportunities
- Track A (command contracts): P4-001/P4-002 can start immediately.
- Track B (audit model): P4-004/P4-005 can run in parallel with P4-003 after command model freeze.
- Track C (execution core): P4-007 can begin once A+B minimum contracts are ready.
- Track D (UI visibility): P4-012 can progress with P4-010; P4-013/P4-014 follow.
- Track E (hardening): P4-015 and P4-017 can run in parallel after execution core stabilizes.

## 10. Risks
- **Accidental unsafe activation**: wrong source/snapshot activated by operator mistake.
- **Last-known-good loss risk**: incorrect state mutation can remove rollback target.
- **Mixed-source confusion risk**: operators may misread candidate/active state across sources.
- **Rollback inconsistency risk**: rollback action and runtime query resolution may diverge.
- **UI ambiguity risk**: unclear active vs candidate labels could trigger wrong actions.

Mitigations:
- Typed command + guard decision model before execution.
- Mandatory LKG preservation before promote.
- Explicit no-safe-rollback results.
- Source-scoped action validation and cross-source regression suite.
- Clear operator confirmations and status labels.

## 11. Recommended First Implementation Slice
1. **P4-001 — Define activation command and execution result primitives**
2. **P4-002 — Define activation guard policy inputs and decision model**
3. **P4-004 — Define activation history event model**

This slice establishes safe contracts first, enabling incremental execution without changing existing runtime dataset behavior.

---

- Total tasks: 18
- P0 tasks: P4-001, P4-002, P4-004, P4-005, P4-007, P4-008, P4-010, P4-012, P4-015, P4-016
- Recommended starting task: P4-001 — Define activation command and execution result primitives
