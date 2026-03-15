# Flow Phase 5 Tasks (Operational Maturity and Persistent Rollout Infrastructure)

## 1. Overview
Phase 5 extends the completed Phase 4 operator-safe activation platform into a more durable and operationally mature system.

The focus is persistence, operator visibility, observability, rollout safety, and maintainability, not architectural replacement.

Core lifecycle for Phase 5:
`activation / refresh operations -> persistent storage -> richer operator visibility -> health / telemetry -> safer operational workflows -> maintainable rollout controls`

## 2. Phase 5 Objectives
- Add persistent activation history storage that survives app restarts.
- Add persistent refresh and activation state storage for operator-visible durability.
- Introduce a richer operator dashboard for source health, candidate readiness, and rollout state.
- Add source health indicators and telemetry/metrics primitives.
- Add durable rollout state and approval scaffolding for higher-safety activation workflows.
- Preserve backward compatibility for `bundledSample`, `seoulCapitalSnapshot`, and `koreaNational`.

## 3. In Scope
- Persistent activation history storage.
- Persistent refresh state and activation state storage.
- Operator dashboard UI and supporting view models.
- Dataset/source health summaries and readiness views.
- Activation and refresh telemetry primitives.
- Rollout readiness views and safety status surfacing.
- Activation approval/staged-rollout scaffolding.
- Audit/history browsing and filtering UI.

## 4. Out of Scope
- Large multi-user RBAC or enterprise authorization system.
- Distributed backend control plane.
- Cloud telemetry backend or external observability platform.
- Major app-wide UI redesign.
- Fully automated autonomous rollout policy.
- Machine-learning-based activation decisions.
- Backend-dependent production operations that assume pre-existing infrastructure.

## 5. Architecture Extensions
Existing baseline (preserved):
- ingestion pipeline
- dataset version store
- activation policy
- activation executor
- activation history model/store
- activation state projection
- operator controls UI

Phase 5 additive components:
- **Persistent History Store**: durable replacement path for in-memory audit history.
- **Persistent Operator State Store**: durable refresh and activation state snapshots.
- **Operator Dashboard Layer**: richer visibility over source health, candidates, approvals, and readiness.
- **Telemetry / Metrics Layer**: structured local metrics and event summaries for refresh/activation operations.
- **Approval / Staged Rollout Model**: explicit operator approval state before high-impact activation changes.
- **Operational Health / Status Layer**: source-scoped readiness, degradation, and rollback-health summaries.

Design constraints:
- Extend existing snapshot, metadata, projection, and operator seams rather than replacing them.
- Keep runtime repository/query behavior backward compatible.
- Keep operator state source-scoped and auditable.
- Prefer local-first persistence and observability primitives before any backend assumptions.

## 6. Milestones
- **M5-1 Persistent Audit and History Storage**
- **M5-2 Persistent Refresh and Activation State**
- **M5-3 Operator Dashboard**
- **M5-4 Source Health and Telemetry**
- **M5-5 Approval and Staged Rollout Semantics**
- **M5-6 Operational Regression Hardening**

## 7. Task Breakdown

### M5-1 Persistent Audit and History Storage

## P5-001 — Introduce persistent activation history storage abstraction and first concrete local-backed implementation
- Priority: P0
- Dependency: None
- Description: Add a durable activation history store implementation that persists `SnapshotActivationHistoryEvent` records locally while preserving the current store interface.
- Short goal: Make operator audit history survive app restarts without changing activation semantics.
- Status: Completed (2026-03-13)
- Notes: Added `PersistentSnapshotActivationHistoryStore`, a local file-backed JSON implementation that preserves the existing async query API, deterministic ordering, and source/command/snapshot/type filtering semantics. Wired the shared repository factory to the persistent store and added persistence/reload regression coverage plus recent-activity compatibility tests.

## P5-002 — Add activation history persistence migration and fallback strategy
- Priority: P1
- Dependency: P5-001
- Description: Define load/migration behavior between empty state, legacy in-memory behavior, and persisted event logs, including corruption-safe fallback semantics.
- Short goal: Keep durable history safe and maintainable under upgrade and recovery scenarios.
- Status: Completed (2026-03-13)
- Notes: Added a versioned persistence envelope for activation history files, legacy-format migration from the initial raw-storage JSON shape, partial-entry recovery for malformed files, and corrupted-file backup/fallback behavior. The store now rewrites migrated or recovered history into the current format while preserving the existing query API and deterministic ordering semantics.

## P5-003 — Add activation history query/filter model for durable browsing
- Priority: P1
- Dependency: P5-001
- Description: Extend history retrieval with paging/filter/query primitives suitable for operator browsing by source, event type, result status, and time range.
- Short goal: Support durable history inspection without overloading the Settings timeline surface.
- Status: Complete
- Notes: Extended `SnapshotActivationHistoryQuery` with command-action, result-status, time-range, sort-order, offset, and limit semantics while preserving the existing store protocol and recent-activity consumers. Added persisted-history regression coverage for durable browsing after reload.

### M5-2 Persistent Refresh and Activation State

## P5-004 — Persist refresh state store across launches
- Priority: P0
- Dependency: None
- Description: Replace or augment the current refresh-state store with a persistent local-backed implementation while preserving source-scoped semantics.
- Short goal: Keep refresh attempts, outcomes, and candidate readiness visible after restart.
- Status: Completed (2026-03-14)
- Notes: Added `PersistentDatasetRefreshStateStore`, a file-backed JSON refresh-state store with a versioned envelope, safe empty-state fallback, corrupted-file backup behavior, and source-scoped persistence of attempt/success/failure/trigger/candidate metadata. Wired the shared repository factory to the persistent store and added persistence plus metadata-enrichment compatibility coverage.

## P5-005 — Persist activation state snapshots and last-known-good pointers
- Priority: P0
- Dependency: P5-001
- Description: Add durable storage for active snapshot, last-known-good, and related source-scoped activation state used by policy/projection layers.
- Short goal: Preserve guarded rollout state across launches without changing runtime resolution contracts.
- Status: Completed (2026-03-15)
- Notes: Added `PersistentSnapshotActivationStateStore`, moved `DefaultSnapshotActivationPolicy` onto an injected activation-state store seam, and wired the shared factory to the persistent implementation. Activation state now restores active snapshot and last-known-good pointers across launches with corrupted-file fallback and policy/projector/catalog compatibility coverage.

## P5-006 — Add persistent operator state bootstrap and recovery flow
- Priority: P1
- Dependency: P5-004, P5-005
- Description: Define startup loading, validation, and recovery behavior for persisted refresh and activation state, including stale/corrupt-state handling.
- Short goal: Ensure operator-visible state is durable but never trusted blindly.
- Status: Completed (2026-03-15)
- Notes: Added `PersistentOperatorStateBootstrap` to restore persistent activation state, refresh state, and activation history in a deterministic startup order before wiring policy/projector consumers. Shared factory bootstrap now exposes explicit restore dispositions and preserves degraded recovery when one persisted store is missing or corrupt.

### M5-3 Operator Dashboard

## P5-007 — Add operator dashboard view model and source summary model
- Priority: P0
- Dependency: P5-003, P5-004, P5-005, P5-006
- Description: Build a dashboard-focused projection/view-model layer that summarizes source health, candidates, active state, rollback readiness, and recent operations.
- Short goal: Provide a single operator-facing summary model without duplicating source-state logic in the UI.
- Status: Completed (2026-03-15)
- Notes: Added `OperatorSourceSummary`, `OperatorDashboardSummary`, and `OperatorDashboardViewModel` as a read-only summary layer over the enriched catalog and bootstrap status. The new view model preserves catalog ordering, keeps static sources free of bogus live/operator state, and surfaces live-capable activation/refresh/readiness semantics without changing existing settings/operator-control flows.

## P5-008 — Add minimal operator dashboard UI for source status and candidate readiness
- Priority: P1
- Dependency: P5-007
- Description: Introduce a compact dashboard surface showing per-source status, active/candidate state, refresh health, and readiness summaries.
- Short goal: Make operator visibility broader than the Settings control panel without broad UI redesign.
- Status: Completed (2026-03-15)
- Notes: Added a low-risk Settings-integrated operator dashboard entry point plus a dedicated `OperatorDashboardView` with compact per-source cards. The UI is backed directly by `OperatorDashboardViewModel`, preserves source-scoped catalog ordering, keeps static sources truthful, and surfaces live-capable candidate readiness, refresh health, rollback availability, and activation status without altering operator workflows.

## P5-009 — Add audit/history browsing UI with filtering and source scoping
- Priority: P1
- Dependency: P5-003, P5-008
- Description: Add a focused history browsing interface that allows operators to inspect persisted activation events by source and filter criteria.
- Short goal: Turn the timeline from a recent-activity snippet into a usable audit surface.
- Status: Completed (2026-03-15)
- Notes: Added `OperatorHistoryBrowserView` as a dedicated activation audit surface reachable from the operator dashboard. The browser is backed directly by `SnapshotActivationHistoryStore` query semantics with source/action/status filters, newest-first query-backed paging, shared event-to-row presentation mapping, and safe empty-state behavior for static or history-free sources.

## P5-019 — Dataset activation timeline view
- Priority: P1
- Dependency: Phase 4 activation history primitives
- Complexity: Medium
- Description: Introduce an operator-facing dataset activation timeline view that surfaces activation history events in a clearer chronological list.
- Short goal: Make recent activation lifecycle history easier to inspect than the compact recent-activity panel.
- Status: Completed (2026-03-14)
- Deliverable: `ActivationTimelineView` integrated with operator controls and backed by `SnapshotActivationHistoryStore`.
- Definition of Done:
  - Timeline displays activation history events newest-first.
  - Source-scoped activation history is respected.
  - Static/non-live sources do not show timeline UI.
  - Promote / demote / rollback / failed / blocked events are visible.
  - Existing Recent Activity compact panel remains intact.
  - No architecture changes are introduced.
- Notes: Added `ActivationTimelineView` plus `SettingsViewModel` `timelineHistory` integration and operator-controls navigation into the full source timeline.

## P5-020 — Activation timeline filtering and browsing refinements
- Priority: P1
- Dependency: P5-003, P5-019
- Complexity: Medium
- Description: Refine the activation timeline with lightweight filtering and browsing controls so operators can inspect persisted source-scoped history more effectively.
- Short goal: Make the timeline usable for day-to-day operator browsing without expanding into a full dashboard.
- Status: Completed (2026-03-14)
- Deliverable: Filterable `ActivationTimelineView` with deterministic load-more browsing backed by existing history query semantics.
- Definition of Done:
  - Timeline keeps newest-first ordering under filters.
  - Source-scoped activation history remains intact.
  - Static/non-live sources do not show timeline UI.
  - Operators can narrow timeline entries by action and status.
  - Operators can browse beyond the default visible window with deterministic expansion.
  - Existing Recent Activity compact panel remains intact.
- Notes: Added action/status filters and load-more browsing in `ActivationTimelineView`, expanded the bounded timeline history window fetched for operator controls, and added pure regression coverage for filtering/order/load-more behavior.

### M5-4 Source Health and Telemetry

## P5-010 — Introduce activation and refresh telemetry/metrics primitives
- Priority: P0
- Dependency: P5-004, P5-005
- Description: Add structured local telemetry events/metrics for refresh attempts, activation actions, failures, blocked actions, and rollback usage.
- Short goal: Create a consistent operational metrics vocabulary before adding richer health UI.
- Status: Completed (2026-03-15)
- Notes: Added `OperatorActivationMetrics`, `OperatorRefreshMetrics`, `OperatorSourceMetrics`, and `OperatorMetricsCollector` as deterministic local read models derived from persisted activation history and refresh state. The operator dashboard summary layer now carries source-scoped metrics for activation result counts, rollback request usage, latest activation timestamp, latest refresh outcome counts, latest refresh timestamp, and latest refresh latency when the retained refresh state makes it derivable.

## P5-011 — Add source health state model and operational status aggregation
- Priority: P0
- Dependency: P5-010
- Description: Derive source-scoped health summaries from refresh state, activation outcomes, compatibility/readiness state, and telemetry signals.
- Short goal: Expose trustworthy health/readiness status for each dataset source.

## P5-012 — Surface telemetry-backed health indicators in operator UI
- Priority: P1
- Dependency: P5-008, P5-011
- Description: Show concise health indicators, degraded-state warnings, and operational hints in the operator dashboard and source metadata surfaces.
- Short goal: Give operators earlier warning of unhealthy refresh/activation conditions.

### M5-5 Approval and Staged Rollout Semantics

## P5-013 — Define activation approval state and staged rollout command scaffolding
- Priority: P0
- Dependency: P5-005, P5-007
- Description: Add models for approval-needed, approved, rejected, staged, and completed rollout states without redesigning current executor semantics.
- Short goal: Introduce a safer pre-execution workflow for future production-style rollout control.

## P5-014 — Add operator-visible approval and rollout readiness state
- Priority: P1
- Dependency: P5-013, P5-008
- Description: Surface approval state, pending actions, rollout readiness, and unresolved blockers in operator-facing dashboard metadata.
- Short goal: Make approval and readiness visible before any future broader rollout controls are added.

## P5-015 — Add rollout checklist model and preflight evaluation service
- Priority: P1
- Dependency: P5-011, P5-013
- Description: Create a source-scoped rollout checklist/preflight model that summarizes persistence, candidate readiness, rollback safety, and health signals before promote execution.
- Short goal: Make rollout decisions more systematic and less ad hoc.

### M5-6 Operational Regression Hardening

## P5-016 — Add persistence regression tests for activation and refresh state
- Priority: P0
- Dependency: P5-001, P5-004, P5-005, P5-006
- Description: Add regression coverage for restart durability, persistence corruption handling, and source-scoped state restoration.
- Short goal: Prove local durability without breaking existing static or live-capable behavior.

## P5-017 — Add dashboard, telemetry, and approval-state regression suite
- Priority: P1
- Dependency: P5-008, P5-009, P5-010, P5-011, P5-014, P5-015
- Description: Add cross-layer regression tests covering operator dashboard state, audit browsing, health indicators, and approval/readiness semantics.
- Short goal: Protect operator-facing operational maturity features from drift.

## P5-018 — Phase 5 closeout, readiness review, and operational handoff checklist
- Priority: P1
- Dependency: P5-016, P5-017
- Description: Synchronize Phase 5 docs/status and produce an operational readiness checklist summarizing persistence, health, approval, and regression outcomes.
- Short goal: Close Phase 5 with a clear durability and rollout-readiness baseline.

## 8. Execution Order
1. P5-001
2. P5-004
3. P5-005
4. P5-002
5. P5-006
6. P5-003
7. P5-007
8. P5-008
9. P5-010
10. P5-011
11. P5-012
12. P5-013
13. P5-014
14. P5-015
15. P5-009
16. P5-019
17. P5-020
18. P5-016
19. P5-017
20. P5-018

## 9. Parallelization Opportunities
- Track A (durability foundation): P5-001, P5-004, and early P5-005 design can begin in parallel once storage conventions are aligned.
- Track B (queryability): P5-003 can progress alongside P5-002 after the persistent history interface is stable.
- Track C (dashboard visibility): P5-007 and design prep for P5-008 can start once persistent state seams are clear.
- Track D (telemetry and health): P5-010 and P5-011 can run in parallel with dashboard work after persistence primitives exist.
- Track E (approval safety): P5-013 and P5-015 can progress together once health and persistent activation state are available.
- Track F (hardening): P5-016 and P5-017 can overlap after the major persistence/dashboard/approval slices stabilize.

## 10. Risks
- **Persistence model drift**: durable stored state may diverge from current in-memory contracts over time.
- **Stale operator state**: persisted refresh or activation state may appear trustworthy when it should be invalidated or recomputed.
- **Audit/history inconsistency after restart**: ordering or linkage may drift if persistence and projection semantics are not aligned.
- **Telemetry noise risk**: metrics without stable semantics may create false confidence or operator confusion.
- **Dashboard complexity creep**: operator UI may become broad and brittle if too many concepts are surfaced at once.
- **Mixed-source confusion risk**: persisted operational state could leak between Seoul live-capable sources, `bundledSample`, and `koreaNational` if source scoping is weakened.

Mitigations:
- Keep persistence interfaces aligned to existing domain/store contracts.
- Validate persisted state at bootstrap and prefer safe fallback over silent trust.
- Preserve source-scoped identifiers and deterministic ordering in durable history.
- Define telemetry semantics before surfacing metrics in UI.
- Keep dashboard additions compact and projection-driven.
- Maintain cross-source regression coverage for all persistence and operator-state changes.

## 11. Recommended First Implementation Slice
`P5-001 — Introduce persistent activation history storage abstraction and first concrete local-backed implementation.`

Rationale:
- It adds durability at a well-bounded seam that already exists.
- It improves audit trust immediately without changing runtime repository behavior.
- It unlocks later dashboard, audit browsing, restart durability, and approval-readiness work.
