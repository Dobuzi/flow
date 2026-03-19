import Testing
@testable import Flow

struct RolloutOrchestrationPrimitivesTests {
    @Test
    func lifecycleTransitionsAreDeterministicForHappyPath() throws {
        let plan = makePlan(source: .seoulCapitalSnapshot)
        let orchestrator = DefaultRolloutOrchestrator()

        let proposed = try orchestrator.transition(
            RolloutExecutionState.initial(plan: plan),
            using: .submitProposal,
            at: "2026-03-17T01:00:00Z"
        )
        #expect(proposed.lifecycleState == .proposed)

        let approved = try orchestrator.transition(proposed, using: .approve, at: "2026-03-17T01:01:00Z")
        #expect(approved.lifecycleState == .approved)

        let preparing = try orchestrator.transition(approved, using: .prepare, at: "2026-03-17T01:02:00Z")
        #expect(preparing.lifecycleState == .preparing)

        let ready = try orchestrator.transition(preparing, using: .markReady, at: "2026-03-17T01:03:00Z")
        #expect(ready.lifecycleState == .ready)

        let executing = try orchestrator.transition(ready, using: .startStage, at: "2026-03-17T01:04:00Z")
        #expect(executing.lifecycleState == .executingStage)
        #expect(executing.currentStageIndex == 0)

        let evaluating = try orchestrator.transition(executing, using: .finishStageExecution, at: "2026-03-17T01:05:00Z")
        #expect(evaluating.lifecycleState == .evaluatingStage)

        let nextStage = try orchestrator.apply(
            .advance,
            to: evaluating,
            using: plan,
            at: "2026-03-17T01:06:00Z"
        )
        #expect(nextStage.lifecycleState == .ready)
        #expect(nextStage.currentStageIndex == 1)

        let secondExecuting = try orchestrator.transition(nextStage, using: .startStage, at: "2026-03-17T01:07:00Z")
        let secondEvaluating = try orchestrator.transition(secondExecuting, using: .finishStageExecution, at: "2026-03-17T01:08:00Z")
        let completed = try orchestrator.apply(
            .advance,
            to: secondEvaluating,
            using: plan,
            at: "2026-03-17T01:09:00Z"
        )
        #expect(completed.lifecycleState == .completed)
        #expect(completed.currentStageIndex == 1)
        #expect(completed.completedAt == "2026-03-17T01:09:00Z")
    }

    @Test
    func invalidTransitionsAreRejected() {
        let plan = makePlan(source: .seoulCapitalSnapshot)
        let orchestrator = DefaultRolloutOrchestrator()
        let draft = RolloutExecutionState.initial(plan: plan)

        #expect(throws: RolloutTransitionError.self) {
            try orchestrator.transition(draft, using: .startStage, at: "2026-03-17T02:00:00Z")
        }

        let approved = RolloutExecutionState(
            planID: plan.planID,
            source: plan.source,
            lifecycleState: .approved,
            currentStageIndex: nil,
            startedAt: nil,
            updatedAt: "2026-03-17T02:01:00Z",
            latestEvaluation: nil,
            completionReason: nil,
            completedAt: nil,
            rollbackState: nil
        )

        #expect(throws: RolloutTransitionError.self) {
            try orchestrator.apply(.rollback, to: approved, using: plan, at: "2026-03-17T02:02:00Z")
        }
    }

    @Test
    func rolloutPlanRetainsSourceTargetAndStageInformation() {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .koreaNational,
                snapshotID: "national-2026.07",
                datasetVersion: "2026.07",
                context: .init(
                    commandID: "cmd-rollout-foundation-001",
                    requestedAt: "2026-03-17T03:00:00Z",
                    trigger: .operatorManual,
                    requestedBy: "operator-a"
                )
            )
        )
        let rolloutCommand = command.proposedRollout(
            proposalID: "proposal-rollout-001",
            state: .approved,
            rolloutMode: .staged,
            executionReadinessSummary: "candidate_ready"
        )
        let plan = RolloutPlan(
            planID: "plan-001",
            source: .koreaNational,
            targetSnapshotID: "national-2026.07",
            targetDatasetVersion: "2026.07",
            rolloutMode: .staged,
            stages: [
                RolloutStage(stageID: "canary", title: "Canary", executionMode: .canary, guardrails: .default, note: "Canary validation"),
                RolloutStage(stageID: "progressive", title: "Progressive", executionMode: .progressive, guardrails: .default, note: nil)
            ],
            createdAt: "2026-03-17T03:00:00Z",
            updatedAt: "2026-03-17T03:00:00Z",
            rolloutCommand: rolloutCommand
        )

        #expect(plan.source == .koreaNational)
        #expect(plan.targetSnapshotID == "national-2026.07")
        #expect(plan.targetDatasetVersion == "2026.07")
        #expect(plan.stages.count == 2)
        #expect(plan.stages[0].executionMode == .canary)
        #expect(plan.rolloutCommand?.command == command)
        #expect(plan.rolloutCommand?.proposal.approvalState == .approved)
    }

    @Test
    func stageEvaluationRecommendationsMapToExpectedLifecycleOutcomes() throws {
        let plan = makePlan(source: .seoulCapitalSnapshot)
        let orchestrator = DefaultRolloutOrchestrator()
        let evaluating = RolloutExecutionState(
            planID: plan.planID,
            source: plan.source,
            lifecycleState: .evaluatingStage,
            currentStageIndex: 0,
            startedAt: "2026-03-17T04:00:00Z",
            updatedAt: "2026-03-17T04:01:00Z",
            latestEvaluation: nil,
            completionReason: nil,
            completedAt: nil,
            rollbackState: nil
        )

        let paused = try orchestrator.apply(.pause, to: evaluating, using: plan, at: "2026-03-17T04:02:00Z")
        #expect(paused.lifecycleState == .paused)
        #expect(paused.latestEvaluation == .pause)

        let halted = try orchestrator.apply(.halt, to: evaluating, using: plan, at: "2026-03-17T04:03:00Z")
        #expect(halted.lifecycleState == .halted)
        #expect(halted.latestEvaluation == .halt)

        let rollingBack = try orchestrator.apply(.rollback, to: evaluating, using: plan, at: "2026-03-17T04:04:00Z")
        #expect(rollingBack.lifecycleState == .rollingBack)
        #expect(rollingBack.rollbackState == .requested)
    }

    @Test
    func compatibilityWithCurrentActivationRolloutCommandsIsPreserved() throws {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: .seoulCapitalSnapshot,
                snapshotID: "seoul-2026.08",
                datasetVersion: nil,
                context: .init(
                    commandID: "cmd-rollout-foundation-002",
                    requestedAt: "2026-03-17T05:00:00Z",
                    trigger: .operatorConfirmed,
                    requestedBy: "lead-1"
                )
            )
        )
        let rolloutCommand = ActivationRolloutCommand.directExecutionCompatible(
            command: command,
            rolloutMode: .immediate,
            executionReadinessSummary: "direct_execution_compatible"
        )
        let plan = RolloutPlan.singleStage(
            planID: "plan-direct-001",
            rolloutCommand: rolloutCommand,
            stageTitle: "Immediate Activation",
            createdAt: "2026-03-17T05:00:00Z"
        )
        let state = RolloutExecutionState.initial(plan: plan)

        #expect(plan.source == .seoulCapitalSnapshot)
        #expect(plan.rolloutCommand?.command == command)
        #expect(plan.rolloutMode == .immediate)
        #expect(plan.stages.count == 1)
        #expect(state.source == .seoulCapitalSnapshot)
        #expect(state.lifecycleState == .draft)
    }

    private func makePlan(source: FlowDatasetSource) -> RolloutPlan {
        RolloutPlan(
            planID: "plan-\(source.rawValue)",
            source: source,
            targetSnapshotID: "\(source.rawValue)-2026.09",
            targetDatasetVersion: "2026.09",
            rolloutMode: .staged,
            stages: [
                RolloutStage(stageID: "canary", title: "Canary", executionMode: .canary, guardrails: .default, note: nil),
                RolloutStage(stageID: "manual-gate", title: "Manual Gate", executionMode: .manualGate, guardrails: .default, note: nil)
            ],
            createdAt: "2026-03-17T00:00:00Z",
            updatedAt: "2026-03-17T00:00:00Z",
            rolloutCommand: nil
        )
    }
}
