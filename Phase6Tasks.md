# Flow Phase 6 Tasks (Approval Workflow Depth, Staged Rollout Orchestration, and Operational Handoff Maturity)

## 1. Overview
Phase 6 extends the completed Phase 5 operator-readiness platform into a more execution-oriented rollout control layer.

The focus is deeper approval lifecycle semantics, staged rollout orchestration, guarded stage progression, rollback-aware safety automation, and operator handoff/reporting maturity.

Core lifecycle for Phase 6:
`proposal -> approval lifecycle -> staged rollout orchestration -> guarded stage progression -> rollback-aware safety automation -> operator handoff/reporting`

## 2. Phase 6 Objectives
- Deepen the approval workflow from read-model visibility into explicit proposal and decision progression.
- Add durable rollout proposal persistence and audit linkage.
- Introduce staged rollout orchestration primitives and progression state.
- Add guarded execution-phase checkpoints for canary/progressive rollout paths.
- Add halt, pause, resume, and rollback-prepared safety semantics.
- Add operator handoff, summary, and export/reporting primitives.
- Preserve backward compatibility for `bundledSample`, `seoulCapitalSnapshot`, and `koreaNational`.

## 3. In Scope
- Proposal -> approve / reject / cancel -> execute lifecycle modeling.
- Rollout proposal persistence and restore behavior.
- Staged rollout plan and progression semantics.
- Canary/progressive rollout state representation.
- Stage transition preflight gates and halt rules.
- Blocked / paused / halted / completed rollout states.
- Rollback-prepared execution paths and safety checks.
- Rollout execution timeline/history extensions.
- Operator handoff/report/export primitives.
- Incident/rollout summary read models.
- Regression coverage for staged rollout, approval lifecycle, guardrails, and source isolation.

## 4. Out of Scope
- Multi-user RBAC platform.
- Distributed backend control plane.
- External approval service.
- Cloud telemetry backend or external observability platform.
- Fully autonomous rollout AI.
- Global fleet orchestration backend.
- Major dashboard/navigation redesign.
- Non-local production operations that assume server-side coordination.

## 5. Architecture Extensions
Existing baseline (preserved):
- ingestion pipeline
- dataset version store
- activation policy / executor / rollback semantics
- persistent operator state
- operator dashboard / history / audit browser
- health aggregation
- approval/readiness summaries
- rollout preflight evaluation

Phase 6 additive components:
- **Approval Workflow Layer**: explicit proposal lifecycle, decision transitions, and operator review state.
- **Rollout Proposal Persistence Layer**: durable local storage for rollout proposals, decisions, and progression state.
- **Staged Rollout Orchestrator**: service layer coordinating rollout stages without replacing current executor semantics.
- **Stage Progression State Machine**: deterministic state model for canary/progressive rollout stages.
- **Safety Automation / Halt Rules Layer**: local guardrail evaluation for pause/halt/rollback-required suggestions.
- **Operator Handoff / Export Layer**: summary, incident, and export-ready reporting models for operational transfer.

Design constraints:
- Extend current activation, history, persistence, dashboard, approval, and preflight seams rather than replacing them.
- Keep runtime repository/query behavior backward compatible.
- Keep all rollout state source-scoped and auditable.
- Prefer local-first persistence/orchestration assumptions before any backend control plane.
- Preserve direct execution compatibility where staged workflow depth is not required.

## 6. Milestones
- **M6-1 Approval Workflow Depth**
- **M6-2 Rollout Proposal Persistence**
- **M6-3 Staged Rollout Orchestrator**
- **M6-4 Guardrail Automation**
- **M6-5 Handoff / Report / Export**
- **M6-6 Regression Hardening and Closeout**

## 7. Task Breakdown

### M6-1 Approval Workflow Depth

## P6-001 — Define approval workflow state progression and proposal persistence seam
- Priority: P0
- Dependency: None
- Description: Define the canonical proposal lifecycle and the persistence seam that will store rollout proposals and approval transitions.
- Short goal: Create the minimal durable domain boundary for proposal/approval progression.

## P6-002 — Add durable rollout proposal store with local-backed implementation
- Priority: P0
- Dependency: P6-001
- Description: Implement a persistent local-backed store for rollout proposals, approval decisions, and proposal metadata while preserving source scoping.
- Short goal: Make rollout proposals survive restart and bootstrap.

## P6-003 — Implement approve / reject / cancel transition primitives and audit linkage
- Priority: P1
- Dependency: P6-001, P6-002
- Description: Add explicit transition helpers for proposal approval decisions and link them into durable audit/history semantics.
- Short goal: Make proposal decisions explicit, durable, and auditable.

### M6-2 Rollout Proposal Persistence

## P6-004 — Add proposal bootstrap / recovery flow and degraded fallback behavior
- Priority: P1
- Dependency: P6-002
- Description: Define startup restore behavior for rollout proposals, including missing/corrupt proposal persistence and degraded fallback semantics.
- Short goal: Keep rollout proposal state durable but recoverable.

## P6-005 — Surface proposal summaries in operator dashboard and history read models
- Priority: P1
- Dependency: P6-003, P6-004
- Description: Extend operator-facing summaries so proposal lifecycle state and recent approval decisions are visible without adding a full approval console.
- Short goal: Make proposal state operator-visible using existing dashboard/history seams.

### M6-3 Staged Rollout Orchestrator

## P6-006 — Define staged rollout plan model and stage descriptors
- Priority: P0
- Dependency: P6-001
- Description: Add rollout plan/domain types for immediate, canary, and progressive staged rollout configurations with explicit stage descriptors.
- Short goal: Represent staged rollout plans without changing executor semantics yet.

## P6-007 — Implement rollout stage state machine for proposed / active / paused / halted / completed stages
- Priority: P0
- Dependency: P6-006
- Description: Add a deterministic stage progression model that captures stage lifecycle and execution checkpoints.
- Short goal: Establish a trustworthy orchestration state machine before wiring execution behavior.

## P6-008 — Add rollout orchestration coordinator compatible with current activation executor
- Priority: P1
- Dependency: P6-007, P6-003
- Description: Add a small orchestration service that can translate approved rollout plans into guarded stage-by-stage execution requests while preserving the current activation executor boundary.
- Short goal: Coordinate staged execution without redesigning activation semantics.

## P6-009 — Add pause / resume / halt / rollback-prepared rollout command semantics
- Priority: P1
- Dependency: P6-008
- Description: Extend rollout command scaffolding with pause/resume/halt and rollback-prepared progression controls.
- Short goal: Make staged rollout control explicit and safe.

### M6-4 Guardrail Automation

## P6-010 — Add stage transition preflight gate and progression guardrails
- Priority: P0
- Dependency: P6-007, P6-008
- Description: Reuse Phase 5 preflight and health signals to gate stage transitions and block unsafe progression.
- Short goal: Prevent unsafe stage advancement using existing operator truth sources.

## P6-011 — Add auto-halt suggestion rules and rollback-required blocking semantics
- Priority: P1
- Dependency: P6-010
- Description: Introduce local rules that suggest halting or require rollback when staged rollout state becomes unsafe or degraded.
- Short goal: Add safety automation without autonomous execution.

## P6-012 — Surface staged rollout progression and halt state in operator UI
- Priority: P1
- Dependency: P6-009, P6-010
- Description: Add compact operator-visible rollout stage/progression state to the existing dashboard/read-model surfaces.
- Short goal: Make staged rollout progress and halt reasons visible without a major UI redesign.

### M6-5 Handoff / Report / Export

## P6-013 — Add rollout execution timeline extensions and incident summary model
- Priority: P1
- Dependency: P6-008, P6-009
- Description: Extend rollout history/timeline read models to summarize stage progression, pauses, halts, and rollback-related incidents.
- Short goal: Make rollout execution understandable in audit/history surfaces.

## P6-014 — Add operator handoff summary and export bundle model
- Priority: P1
- Dependency: P6-013
- Description: Create handoff/export-ready summary models that package rollout state, incidents, approvals, and readiness outcomes for operator transfer.
- Short goal: Make rollout state transferable without manual reconstruction.

## P6-015 — Add report-ready rollout summary generation and closeout checklist view-model support
- Priority: P1
- Dependency: P6-014
- Description: Add a concise reporting/read-model layer that can generate rollout closeout summaries and checklist-ready operational handoff content.
- Short goal: Establish a report baseline for handoff and future export surfaces.

### M6-6 Regression Hardening and Closeout

## P6-016 — Add approval workflow and proposal persistence regression coverage
- Priority: P0
- Dependency: P6-003, P6-004
- Description: Add regression coverage for proposal persistence, approval transitions, degraded recovery, and source-scoped proposal isolation.
- Short goal: Protect the new approval workflow foundation from drift.

## P6-017 — Add staged rollout state-machine and guardrail regression suite
- Priority: P0
- Dependency: P6-010, P6-011, P6-012
- Description: Add cross-layer regression coverage for stage progression, pause/halt/resume semantics, guardrail gating, and rollback-required blocking behavior.
- Short goal: Prove staged rollout orchestration remains deterministic and safe.

## P6-018 — Phase 6 closeout, readiness review, and operational handoff checklist
- Priority: P1
- Dependency: P6-016, P6-017
- Description: Synchronize Phase 6 docs/status and produce a rollout-control-plane readiness review covering approval depth, orchestration safety, and handoff/report maturity.
- Short goal: Close Phase 6 with a clear execution-oriented rollout baseline.

## 8. Execution Order
1. P6-001
2. P6-002
3. P6-003
4. P6-004
5. P6-006
6. P6-007
7. P6-005
8. P6-008
9. P6-009
10. P6-010
11. P6-011
12. P6-012
13. P6-013
14. P6-014
15. P6-015
16. P6-016
17. P6-017
18. P6-018

## 9. Parallelization Opportunities
- Track A (proposal durability): P6-001, P6-002, and early P6-004 design can progress together once persistence conventions are aligned.
- Track B (orchestration modeling): P6-006 and P6-007 can progress alongside proposal-surface work after the core proposal seam exists.
- Track C (operator surfacing): P6-005 and P6-012 can progress in parallel once proposal and rollout read-models stabilize.
- Track D (guardrails): P6-010 and P6-011 can progress together after the stage state machine is defined.
- Track E (handoff/reporting): P6-013, P6-014, and P6-015 can overlap once rollout execution summaries are available.
- Track F (hardening): P6-016 and P6-017 can overlap after the major proposal/orchestration/guardrail slices stabilize.

## 10. Risks
- **Approval/direct-execution divergence**: new approval workflow paths may drift from the current direct activation flow and create inconsistent operator semantics.
- **Staged rollout state explosion**: too many rollout states or transitions may make orchestration brittle and hard to reason about.
- **Unsafe partial rollout semantics**: canary/progressive rollout modeling may imply safety guarantees that are not actually enforced.
- **Rollback inconsistency risk**: staged rollout control may drift from the current activation policy and last-known-good semantics.
- **Cross-source contamination risk**: rollout proposals, execution summaries, or handoff reports may leak between Seoul, bundled, and national sources if scoping weakens.
- **Report/history drift risk**: handoff/export summaries may diverge from the actual execution timeline if read-model mapping is not kept deterministic.

Mitigations:
- Keep proposal/orchestration boundaries layered on top of the current activation policy/executor seams.
- Prefer a small deterministic state machine over flexible but ambiguous rollout state.
- Gate every stage transition through existing health/readiness/preflight truth sources.
- Preserve rollback and last-known-good invariants as source-scoped first-class concerns.
- Maintain cross-source regression coverage for proposals, stage transitions, guardrails, and handoff/reporting.
- Keep handoff/export summaries derived from durable timeline/history primitives rather than separate ad hoc state.

## 11. Recommended First Implementation Slice
`P6-001 — Define approval workflow state progression and proposal persistence seam`

Rationale:
- It is the smallest safe extension of the current Phase 5 approval/readiness foundation.
- It creates the durable boundary required for every later staged rollout, guardrail, and handoff/reporting task.
- It strengthens execution-oriented workflow depth without changing current runtime or activation executor semantics.
