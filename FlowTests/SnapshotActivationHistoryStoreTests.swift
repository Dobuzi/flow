import Testing
@testable import Flow

struct SnapshotActivationHistoryStoreTests {
    @Test
    func appendsAndListsAllEventsInDeterministicNewestFirstOrder() async {
        let store = InMemorySnapshotActivationHistoryStore()

        await store.append(makeRequestedEvent(
            eventID: "evt-1",
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            timestamp: "2026-03-10T00:00:01Z"
        ))
        await store.append(makeRequestedEvent(
            eventID: "evt-2",
            source: .koreaNational,
            snapshotID: "national-2026.01",
            timestamp: "2026-03-10T00:00:03Z"
        ))
        await store.append(makeRequestedEvent(
            eventID: "evt-3",
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            timestamp: "2026-03-10T00:00:02Z"
        ))

        let events = await store.events()
        #expect(events.map(\.eventID) == ["evt-2", "evt-3", "evt-1"])
    }

    @Test
    func filtersBySourceCommandIDSnapshotIDAndType() async {
        let store = InMemorySnapshotActivationHistoryStore()

        let promoteA = makeRequestedEvent(
            eventID: "evt-a",
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.04",
            commandID: "cmd-1",
            timestamp: "2026-03-10T00:00:00Z"
        )
        let promoteB = makeRequestedEvent(
            eventID: "evt-b",
            source: .koreaNational,
            snapshotID: "national-2026.02",
            commandID: "cmd-2",
            timestamp: "2026-03-10T00:00:01Z"
        )
        let blocked = makeBlockedRollbackEvent(
            eventID: "evt-c",
            source: .seoulCapitalSnapshot,
            commandID: "cmd-1",
            timestamp: "2026-03-10T00:00:02Z"
        )

        await store.append(promoteA)
        await store.append(promoteB)
        await store.append(blocked)

        let sourceEvents = await store.events(for: .seoulCapitalSnapshot)
        #expect(sourceEvents.map(\.eventID) == ["evt-c", "evt-a"])

        let commandEvents = await store.events(commandID: "cmd-1")
        #expect(commandEvents.map(\.eventID) == ["evt-c", "evt-a"])

        let snapshotEvents = await store.events(snapshotID: "seoul-2026.04")
        #expect(snapshotEvents.map(\.eventID) == ["evt-a"])

        let typeEvents = await store.events(type: .rollbackBlocked)
        #expect(typeEvents.map(\.eventID) == ["evt-c"])
    }

    @Test
    func latestEventForSourceReturnsMostRecent() async {
        let store = InMemorySnapshotActivationHistoryStore()

        await store.append(makeRequestedEvent(
            eventID: "evt-1",
            source: .koreaNational,
            snapshotID: "national-2026.01",
            timestamp: "2026-03-10T01:00:00Z"
        ))
        await store.append(makeRequestedEvent(
            eventID: "evt-2",
            source: .koreaNational,
            snapshotID: "national-2026.02",
            timestamp: "2026-03-10T01:00:01Z"
        ))

        let latest = await store.latestEvent(for: .koreaNational)
        #expect(latest?.eventID == "evt-2")
    }

    @Test
    func repeatedTimestampOrderingRemainsDeterministicByAppendSequence() async {
        let store = InMemorySnapshotActivationHistoryStore()

        let timestamp = "2026-03-10T02:00:00Z"
        await store.append(makeRequestedEvent(eventID: "evt-1", source: .seoulCapitalSnapshot, snapshotID: "s1", timestamp: timestamp))
        await store.append(makeRequestedEvent(eventID: "evt-2", source: .seoulCapitalSnapshot, snapshotID: "s2", timestamp: timestamp))
        await store.append(makeRequestedEvent(eventID: "evt-3", source: .seoulCapitalSnapshot, snapshotID: "s3", timestamp: timestamp))

        let newestFirst = await store.events()
        #expect(newestFirst.map(\.eventID) == ["evt-3", "evt-2", "evt-1"])

        let oldestFirst = await store.query(.init(source: .seoulCapitalSnapshot, sortOrder: .oldestFirst))
        #expect(oldestFirst.map(\.eventID) == ["evt-1", "evt-2", "evt-3"])
    }

    @Test
    func querySupportsLimitForRecentTimeline() async {
        let store = InMemorySnapshotActivationHistoryStore()

        await store.append(makeRequestedEvent(eventID: "evt-1", source: .seoulCapitalSnapshot, snapshotID: "s1", timestamp: "2026-03-10T03:00:00Z"))
        await store.append(makeRequestedEvent(eventID: "evt-2", source: .seoulCapitalSnapshot, snapshotID: "s2", timestamp: "2026-03-10T03:00:01Z"))
        await store.append(makeRequestedEvent(eventID: "evt-3", source: .seoulCapitalSnapshot, snapshotID: "s3", timestamp: "2026-03-10T03:00:02Z"))

        let limited = await store.query(.init(source: .seoulCapitalSnapshot, limit: 2))
        #expect(limited.map(\.eventID) == ["evt-3", "evt-2"])
    }

    private func makeRequestedEvent(
        eventID: String,
        source: FlowDatasetSource,
        snapshotID: String,
        commandID: String = "cmd-requested",
        timestamp: String
    ) -> SnapshotActivationHistoryEvent {
        let command = SnapshotActivationCommand.promote(
            PromoteSnapshotCommand(
                source: source,
                snapshotID: snapshotID,
                context: SnapshotActivationCommandContext(
                    commandID: commandID,
                    requestedAt: timestamp,
                    trigger: .operatorManual
                )
            )
        )

        return SnapshotActivationHistoryEvent.requested(
            command: command,
            eventID: eventID,
            timestamp: timestamp
        )
    }

    private func makeBlockedRollbackEvent(
        eventID: String,
        source: FlowDatasetSource,
        commandID: String,
        timestamp: String
    ) -> SnapshotActivationHistoryEvent {
        let command = SnapshotActivationCommand.rollback(
            RollbackSnapshotCommand(
                source: source,
                expectedActiveSnapshotID: nil,
                context: SnapshotActivationCommandContext(
                    commandID: commandID,
                    requestedAt: timestamp,
                    trigger: .recoveryRollback
                )
            )
        )

        let decision = SnapshotActivationGuardInput(
            command: command,
            isLiveCapable: true,
            rollbackDecision: SnapshotRollbackDecision(
                source: source,
                status: .noSafeRollback,
                target: nil,
                reasons: ["last_known_good_missing"]
            )
        ).baselineDecision()

        return SnapshotActivationHistoryEvent.fromGuardDecision(
            decision,
            eventID: eventID,
            timestamp: timestamp
        )
    }
}
