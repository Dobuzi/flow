import Foundation

enum RolloutLifecycleState: String, Codable, Hashable {
    case draft
    case proposed
    case approved
    case preparing
    case ready
    case executingStage
    case evaluatingStage
    case paused
    case halted
    case rollingBack
    case completed
    case failed
}

enum RolloutStageExecutionMode: String, Codable, Hashable {
    case immediate
    case canary
    case progressive
    case manualGate
}

struct RolloutStageGuardrails: Codable, Hashable {
    let requiresPreflightPass: Bool
    let supportsPause: Bool
    let supportsRollback: Bool

    static let `default` = RolloutStageGuardrails(
        requiresPreflightPass: true,
        supportsPause: true,
        supportsRollback: true
    )
}

struct RolloutStage: Codable, Hashable {
    let stageID: String
    let title: String
    let executionMode: RolloutStageExecutionMode
    let guardrails: RolloutStageGuardrails
    let note: String?
}

enum RolloutStageEvaluationRecommendation: String, Codable, Hashable {
    case advance
    case pause
    case halt
    case rollback
}

enum RolloutTransitionAction: Hashable {
    case submitProposal
    case approve
    case reject
    case cancel
    case prepare
    case markReady
    case startStage
    case finishStageExecution
    case fail(reason: String?)
}

enum RolloutRollbackState: String, Codable, Hashable {
    case requested
    case completed
    case failed
}

struct RolloutPlan: Codable, Hashable {
    let planID: String
    let source: FlowDatasetSource
    let targetSnapshotID: String?
    let targetDatasetVersion: String?
    let rolloutMode: StagedRolloutMode
    let stages: [RolloutStage]
    let createdAt: String
    let updatedAt: String
    let rolloutCommand: ActivationRolloutCommand?

    static func singleStage(
        planID: String,
        rolloutCommand: ActivationRolloutCommand,
        stageTitle: String,
        createdAt: String
    ) -> RolloutPlan {
        RolloutPlan(
            planID: planID,
            source: rolloutCommand.source,
            targetSnapshotID: rolloutCommand.proposal.targetSnapshotID,
            targetDatasetVersion: rolloutCommand.proposal.targetDatasetVersion,
            rolloutMode: rolloutCommand.rolloutMode,
            stages: [
                RolloutStage(
                    stageID: "stage-0",
                    title: stageTitle,
                    executionMode: .immediate,
                    guardrails: .default,
                    note: nil
                )
            ],
            createdAt: createdAt,
            updatedAt: createdAt,
            rolloutCommand: rolloutCommand
        )
    }
}

struct RolloutExecutionState: Codable, Hashable {
    let planID: String
    let source: FlowDatasetSource
    let lifecycleState: RolloutLifecycleState
    let currentStageIndex: Int?
    let startedAt: String?
    let updatedAt: String
    let latestEvaluation: RolloutStageEvaluationRecommendation?
    let completionReason: String?
    let completedAt: String?
    let rollbackState: RolloutRollbackState?

    static func initial(
        plan: RolloutPlan,
        at timestamp: String? = nil
    ) -> RolloutExecutionState {
        RolloutExecutionState(
            planID: plan.planID,
            source: plan.source,
            lifecycleState: .draft,
            currentStageIndex: nil,
            startedAt: nil,
            updatedAt: timestamp ?? plan.updatedAt,
            latestEvaluation: nil,
            completionReason: nil,
            completedAt: nil,
            rollbackState: nil
        )
    }
}

enum RolloutTransitionError: Error, Hashable {
    case invalidLifecycleTransition(state: RolloutLifecycleState, action: String)
    case invalidEvaluationTransition(state: RolloutLifecycleState, recommendation: RolloutStageEvaluationRecommendation)
    case stageIndexOutOfBounds(planID: String, index: Int)
}

protocol RolloutOrchestrating {
    func transition(
        _ state: RolloutExecutionState,
        using action: RolloutTransitionAction,
        at timestamp: String
    ) throws -> RolloutExecutionState

    func apply(
        _ recommendation: RolloutStageEvaluationRecommendation,
        to state: RolloutExecutionState,
        using plan: RolloutPlan,
        at timestamp: String
    ) throws -> RolloutExecutionState
}

struct DefaultRolloutOrchestrator: RolloutOrchestrating {
    func transition(
        _ state: RolloutExecutionState,
        using action: RolloutTransitionAction,
        at timestamp: String
    ) throws -> RolloutExecutionState {
        switch (state.lifecycleState, action) {
        case (.draft, .submitProposal):
            return state.with(lifecycleState: .proposed, updatedAt: timestamp)
        case (.proposed, .approve):
            return state.with(lifecycleState: .approved, updatedAt: timestamp)
        case (.proposed, .reject):
            return state.with(lifecycleState: .failed, updatedAt: timestamp, completionReason: "rejected")
        case (.proposed, .cancel):
            return state.with(lifecycleState: .failed, updatedAt: timestamp, completionReason: "cancelled")
        case (.approved, .prepare):
            return state.with(lifecycleState: .preparing, updatedAt: timestamp)
        case (.preparing, .markReady):
            return state.with(lifecycleState: .ready, updatedAt: timestamp)
        case (.ready, .startStage):
            return state.with(
                lifecycleState: .executingStage,
                currentStageIndex: state.currentStageIndex ?? 0,
                startedAt: state.startedAt ?? timestamp,
                updatedAt: timestamp
            )
        case (.paused, .markReady):
            return state.with(lifecycleState: .ready, updatedAt: timestamp)
        case (.paused, .prepare):
            return state.with(lifecycleState: .ready, updatedAt: timestamp)
        case (.paused, .cancel):
            return state.with(lifecycleState: .halted, updatedAt: timestamp, completionReason: "cancelled")
        case (.halted, .fail(let reason)):
            return state.with(lifecycleState: .failed, updatedAt: timestamp, completionReason: reason)
        case (.rollingBack, .markReady):
            return state.with(lifecycleState: .completed, updatedAt: timestamp, completedAt: timestamp)
        case (.rollingBack, .fail(let reason)):
            return state.with(
                lifecycleState: .failed,
                updatedAt: timestamp,
                completionReason: reason,
                rollbackState: .failed
            )
        case (.executingStage, .finishStageExecution):
            return state.with(lifecycleState: .evaluatingStage, updatedAt: timestamp)
        case (_, .fail(let reason)):
            return state.with(lifecycleState: .failed, updatedAt: timestamp, completionReason: reason)
        default:
            throw RolloutTransitionError.invalidLifecycleTransition(
                state: state.lifecycleState,
                action: String(describing: action)
            )
        }
    }

    func apply(
        _ recommendation: RolloutStageEvaluationRecommendation,
        to state: RolloutExecutionState,
        using plan: RolloutPlan,
        at timestamp: String
    ) throws -> RolloutExecutionState {
        guard state.lifecycleState == .evaluatingStage else {
            throw RolloutTransitionError.invalidEvaluationTransition(
                state: state.lifecycleState,
                recommendation: recommendation
            )
        }

        let currentIndex = state.currentStageIndex ?? 0
        guard plan.stages.indices.contains(currentIndex) else {
            throw RolloutTransitionError.stageIndexOutOfBounds(planID: plan.planID, index: currentIndex)
        }

        switch recommendation {
        case .advance:
            if currentIndex < (plan.stages.count - 1) {
                return state.with(
                    lifecycleState: .ready,
                    currentStageIndex: currentIndex + 1,
                    updatedAt: timestamp,
                    latestEvaluation: .advance
                )
            }
            return state.with(
                lifecycleState: .completed,
                currentStageIndex: currentIndex,
                updatedAt: timestamp,
                latestEvaluation: .advance,
                completedAt: timestamp
            )
        case .pause:
            return state.with(
                lifecycleState: .paused,
                updatedAt: timestamp,
                latestEvaluation: .pause
            )
        case .halt:
            return state.with(
                lifecycleState: .halted,
                updatedAt: timestamp,
                latestEvaluation: .halt
            )
        case .rollback:
            return state.with(
                lifecycleState: .rollingBack,
                updatedAt: timestamp,
                latestEvaluation: .rollback,
                rollbackState: .requested
            )
        }
    }
}

private extension RolloutExecutionState {
    func with(
        lifecycleState: RolloutLifecycleState,
        currentStageIndex: Int? = nil,
        startedAt: String? = nil,
        updatedAt: String,
        latestEvaluation: RolloutStageEvaluationRecommendation? = nil,
        completionReason: String? = nil,
        completedAt: String? = nil,
        rollbackState: RolloutRollbackState? = nil
    ) -> RolloutExecutionState {
        RolloutExecutionState(
            planID: planID,
            source: source,
            lifecycleState: lifecycleState,
            currentStageIndex: currentStageIndex ?? self.currentStageIndex,
            startedAt: startedAt ?? self.startedAt,
            updatedAt: updatedAt,
            latestEvaluation: latestEvaluation ?? self.latestEvaluation,
            completionReason: completionReason ?? self.completionReason,
            completedAt: completedAt ?? self.completedAt,
            rollbackState: rollbackState ?? self.rollbackState
        )
    }
}
