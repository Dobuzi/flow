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
- Status: Completed (2026-03-12)
- Notes: Added `SnapshotActivationStateProjecting` and `DefaultSnapshotActivationStateProjector` with `ProjectedActivationState`/status models. Projection combines activation policy state, history timeline context, version metadata, and rollback evaluation into a stable operator-facing derived snapshot per source.

### M4-3 Guarded Promote/Demote Flow

## P4-007 — Implement activation execution service skeleton
- Priority: P0
- Dependency: P4-001, P4-002, P4-003, P4-005
- Description: Add coordinator/service that executes validated commands, applies guard decisions, and emits typed execution results.
- Short goal: Centralize operator action execution.
- Status: Completed (2026-03-12)
- Notes: Added `SnapshotActivationExecuting` with `DefaultSnapshotActivationExecutor` skeleton wiring command validation, guard evaluation, typed execution results, and history event persistence. Promote/rollback paths use existing activation policy hooks; demote flow remains explicit placeholder-blocked for safety in this skeleton stage.

## P4-008 — Wire guarded promote flow to activation policy + version store
- Priority: P0
- Dependency: P4-007
- Description: Implement explicit promote flow for eligible candidate snapshots, preserving last-known-good before activation state switch.
- Short goal: Safe manual promotion path.
- Status: Completed (2026-03-12)
- Notes: Integrated guarded state-mutation semantics verification through `DefaultSnapshotActivationExecutor` and activation policy hooks. Successful promote/rollback transitions now explicitly preserve/restore last-known-good state while blocked/failed/no-op flows remain mutation-free; added executor-level regression tests for promote, rollback, blocked, failed, no-op, and conservative demote behavior.

## P4-009 — Implement guarded demote/disable flow
- Priority: P1
- Dependency: P4-007
- Description: Add explicit demote action that reverts source from activated candidate to stable fallback without cross-source side effects.
- Short goal: Safe manual deactivation path.
- Status: Completed (2026-03-12)
- Notes: Replaced demote placeholder semantics with guarded safe-fallback behavior. Demote now requires a valid rollback target and confirmation, restores a safe fallback via activation policy rollback semantics, preserves last-known-good state, and remains blocked/no-op without mutation when no safe fallback exists or confirmation is missing.

### M4-4 Rollback Execution Controls

## P4-010 — Implement rollback command execution with no-safe-rollback semantics
- Priority: P0
- Dependency: P4-007, P4-008
- Description: Execute rollback to last-known-good when available; return explicit non-success result when no safe rollback target exists.
- Short goal: Deterministic and safe rollback behavior.
- Status: Completed (2026-03-12)
- Notes: Tightened rollback guard/executor semantics to distinguish no safe target, missing target, incompatible/ineligible fallback, already-satisfied no-op, and successful rollback restoration. Added executor/guard regression coverage for rollback success, blocked, incompatible, no-op, and non-mutation guarantees.

## P4-011 — Confirmation hardening for operator-safe activation flows
- Priority: P1
- Dependency: P4-007, P4-008, P4-009, P4-010
- Description: Strengthen confirmation-required classification for high-impact promote, demote, and rollback transitions while keeping blocked and no-op semantics explicit.
- Short goal: Prevent accidental risky activation state changes.
- Status: Completed (2026-03-12)
- Notes: Promote now requires confirmation when it would replace the current active snapshot, while initial activation with no active snapshot remains allowed. Demote and rollback confirmation paths now carry explicit fallback-transition reasons, and executor coverage verifies blocked invalid/incompatible actions are not mislabeled as confirmation-required.

### M4-5 Minimal Operator UI and Visibility

## P4-012 — Add operator activation metadata to catalog/source enrichment
- Priority: P0
- Dependency: P4-006, P4-008, P4-010
- Description: Surface active snapshot, candidate readiness, last action, and rollback availability in live metadata.
- Short goal: Keep source status truthful and actionable.
- Status: Completed (2026-03-12)
- Notes: Extended `DatasetLiveMetadata` with source-scoped `activationMetadata` and enriched it through `CatalogLiveMetadataEnricher` using activation projection, version-store candidate state, refresh state, and latest activation event context. Added regression coverage for static-source compatibility, truthful live-source activation fields, latest event surfacing, rollback readiness, and confirmation-required metadata.

## P4-013 — Add minimal operator controls UI (Settings or operator-safe panel)
- Priority: P1
- Dependency: P4-012
- Description: Add explicit controls for promote/demote/rollback on live-capable sources with disabled states when blocked.
- Short goal: Provide minimal but usable operator control surface.
- Status: Completed (2026-03-12)
- Notes: Added a compact operator controls section in Settings backed by live catalog metadata and guard evaluation. The panel surfaces active/last-known-good/candidate metadata, action availability, rollback readiness, latest activation event summary, and minimal confirmation handling for risky actions while keeping static sources free of operator controls.

## P4-014 — Add confirmation flows for promote/demote/rollback actions
- Priority: P1
- Dependency: P4-013
- Description: Add non-intrusive confirmations showing source, target snapshot, risk/guard notes, and expected outcome before execution.
- Short goal: Reduce accidental operator errors.
- Status: Completed (2026-03-12)
- Notes: Refined Settings confirmation prompts into action-specific operator confirmations with source, current active snapshot, target/fallback snapshot, effect summary, and action-specific CTA labels. Added view-model regression coverage for promote/demote/rollback confirmation payloads, non-execution before confirmation, confirmed execution routing, and blocked/no-op behavior.

### M4-6 Regression and Rollout Safety

## P4-015 — Add operator timeline/history visibility and final rollout-safety regression coverage
- Priority: P0
- Dependency: P4-008, P4-009, P4-010
- Description: Surface a minimal recent activation timeline in the operator controls UI and lock in regression coverage for mixed command/guard/execution/history/projection/UI behavior.
- Short goal: Make recent operator activation activity visible and keep rollout-safety behavior regression-protected.
- Status: Completed (2026-03-12)
- Notes: Added recent activation history visibility to the Settings operator controls surface using source-scoped history store queries and concise timeline entries. Added regression coverage for newest-first event ordering, source scoping, and operator history state exposure while preserving static-source isolation. Simulator verification confirmed recent promote/demote/rollback history visibility for a live-capable source, action-specific confirmation dialogs still working, and no bogus operator history for `bundledSample`.

## P4-016 — Add cross-source activation safety regression tests
- Priority: P0
- Dependency: P4-015
- Description: Ensure activation actions for one source do not mutate runtime/metadata behavior of unrelated sources.
- Short goal: Preserve mixed-source isolation guarantees.
- Status: Completed (2026-03-12)
- Notes: Added source-isolation regression coverage across executor, history store, activation projection, catalog enrichment, activation-aware query resolution, and Settings operator state. Verified that Seoul live activation remains scoped to Seoul, while `bundledSample` and `koreaNational` retain clean, unaffected runtime and operator metadata behavior.

## P4-017 — Add activation history consistency and audit tests
- Priority: P1
- Dependency: P4-005, P4-015
- Description: Verify event append order, projection correctness, and action-result/history consistency.
- Short goal: Guarantee auditability integrity.
- Status: Completed (2026-03-12)
- Notes: Added audit-focused regression coverage across executor, history store, state projector, and Settings recent activity mapping. Verified requested-to-terminal event sequencing, no-op/blocked/failed audit semantics, source-scoped history isolation, and newest-first operator timeline ordering without changing runtime source behavior.

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
