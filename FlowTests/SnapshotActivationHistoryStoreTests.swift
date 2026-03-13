import Foundation
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

    @Test
    func persistentStorePersistsEventsAcrossReinitialization() async throws {
        let fileURL = temporaryHistoryFileURL(testName: #function)
        let store = PersistentSnapshotActivationHistoryStore(fileURL: fileURL)

        await store.append(makeRequestedEvent(
            eventID: "evt-1",
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.03",
            commandID: "cmd-1",
            timestamp: "2026-03-10T04:00:00Z"
        ))
        await store.append(makeRequestedEvent(
            eventID: "evt-2",
            source: .koreaNational,
            snapshotID: "national-2026.01",
            commandID: "cmd-2",
            timestamp: "2026-03-10T04:00:01Z"
        ))

        let reloaded = PersistentSnapshotActivationHistoryStore(fileURL: fileURL)
        let events = await reloaded.events()
        #expect(events.map(\.eventID) == ["evt-2", "evt-1"])

        let latestSeoul = await reloaded.latestEvent(for: .seoulCapitalSnapshot)
        #expect(latestSeoul?.eventID == "evt-1")
    }

    @Test
    func persistentStorePreservesFilteringAndOrderingAfterReload() async throws {
        let fileURL = temporaryHistoryFileURL(testName: #function)
        let store = PersistentSnapshotActivationHistoryStore(fileURL: fileURL)
        let timestamp = "2026-03-10T05:00:00Z"

        await store.append(makeRequestedEvent(
            eventID: "evt-1",
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.01",
            commandID: "cmd-shared",
            timestamp: timestamp
        ))
        await store.append(makeRequestedEvent(
            eventID: "evt-2",
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.02",
            commandID: "cmd-shared",
            timestamp: timestamp
        ))
        await store.append(makeBlockedRollbackEvent(
            eventID: "evt-3",
            source: .seoulCapitalSnapshot,
            commandID: "cmd-shared",
            timestamp: "2026-03-10T05:00:01Z"
        ))

        let reloaded = PersistentSnapshotActivationHistoryStore(fileURL: fileURL)

        let bySource = await reloaded.events(for: .seoulCapitalSnapshot)
        #expect(bySource.map(\.eventID) == ["evt-3", "evt-2", "evt-1"])

        let byCommand = await reloaded.events(commandID: "cmd-shared")
        #expect(byCommand.map(\.eventID) == ["evt-3", "evt-2", "evt-1"])

        let bySnapshot = await reloaded.events(snapshotID: "seoul-2026.02")
        #expect(bySnapshot.map(\.eventID) == ["evt-2"])

        let oldestFirst = await reloaded.query(
            .init(source: .seoulCapitalSnapshot, sortOrder: .oldestFirst)
        )
        #expect(oldestFirst.map(\.eventID) == ["evt-1", "evt-2", "evt-3"])
    }

    @Test
    func persistentStoreSupportsRecentTimelineQueriesAfterReload() async throws {
        let fileURL = temporaryHistoryFileURL(testName: #function)
        let store = PersistentSnapshotActivationHistoryStore(fileURL: fileURL)

        await store.append(makeRequestedEvent(
            eventID: "evt-1",
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.01",
            timestamp: "2026-03-10T06:00:00Z"
        ))
        await store.append(makeBlockedRollbackEvent(
            eventID: "evt-2",
            source: .seoulCapitalSnapshot,
            commandID: "cmd-recent",
            timestamp: "2026-03-10T06:00:01Z"
        ))
        await store.append(makeRequestedEvent(
            eventID: "evt-3",
            source: .koreaNational,
            snapshotID: "national-2026.01",
            timestamp: "2026-03-10T06:00:02Z"
        ))

        let reloaded = PersistentSnapshotActivationHistoryStore(fileURL: fileURL)
        let recent = await reloaded.query(
            .init(source: .seoulCapitalSnapshot, limit: 2, sortOrder: .newestFirst)
        )

        #expect(recent.map(\.eventID) == ["evt-2", "evt-1"])
    }

    @Test
    func persistentStoreMigratesLegacyRawStorageFormat() async throws {
        let fileURL = temporaryHistoryFileURL(testName: #function)
        let legacyEvent = makeRequestedEvent(
            eventID: "evt-legacy",
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.05",
            commandID: "cmd-legacy",
            timestamp: "2026-03-10T07:00:00Z"
        )
        try writeLegacyStorageFile(
            at: fileURL,
            storedEvents: [
                [
                    "event": eventJSONObject(legacyEvent),
                    "sequence": 1
                ]
            ],
            sequenceCounter: 1
        )

        let reloaded = PersistentSnapshotActivationHistoryStore(fileURL: fileURL)
        let events = await reloaded.events()

        #expect(events.map(\.eventID) == ["evt-legacy"])
        #expect(await reloaded.events(commandID: "cmd-legacy").map(\.eventID) == ["evt-legacy"])

        let persistedRoot = try persistedJSONObject(at: fileURL)
        #expect((persistedRoot["formatVersion"] as? Int) == 2)
    }

    @Test
    func persistentStoreRecoversValidSubsetFromMalformedEnvelopeEntries() async throws {
        let fileURL = temporaryHistoryFileURL(testName: #function)
        let validEvent = makeRequestedEvent(
            eventID: "evt-valid",
            source: .seoulCapitalSnapshot,
            snapshotID: "seoul-2026.06",
            commandID: "cmd-valid",
            timestamp: "2026-03-10T08:00:00Z"
        )
        let malformedEnvelope: [String: Any] = [
            "formatVersion": 2,
            "sequenceCounter": 3,
            "events": [
                [
                    "event": eventJSONObject(validEvent),
                    "sequence": 1
                ],
                [
                    "event": ["bad": "shape"],
                    "sequence": "oops"
                ]
            ]
        ]
        try writeJSONObject(malformedEnvelope, to: fileURL)

        let reloaded = PersistentSnapshotActivationHistoryStore(fileURL: fileURL)
        let events = await reloaded.events()

        #expect(events.map(\.eventID) == ["evt-valid"])
        #expect(await reloaded.events(snapshotID: "seoul-2026.06").map(\.eventID) == ["evt-valid"])

        let backupFiles = try corruptedBackups(for: fileURL)
        #expect(backupFiles.count == 1)
    }

    @Test
    func corruptedPersistedFileFallsBackToStableEmptyStateAndBacksUpOriginal() async throws {
        let fileURL = temporaryHistoryFileURL(testName: #function)
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try Data("not-json".utf8).write(to: fileURL, options: [.atomic])

        let reloaded = PersistentSnapshotActivationHistoryStore(fileURL: fileURL)
        let events = await reloaded.events()

        #expect(events.isEmpty)

        let backupFiles = try corruptedBackups(for: fileURL)
        #expect(backupFiles.count == 1)

        await reloaded.append(
            makeRequestedEvent(
                eventID: "evt-new",
                source: .koreaNational,
                snapshotID: "national-2026.03",
                commandID: "cmd-new",
                timestamp: "2026-03-10T09:00:00Z"
            )
        )

        let persistedRoot = try persistedJSONObject(at: fileURL)
        #expect((persistedRoot["formatVersion"] as? Int) == 2)
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

    private func temporaryHistoryFileURL(testName: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FlowTests", isDirectory: true)
            .appendingPathComponent("ActivationHistory", isDirectory: true)
            .appendingPathComponent("\(testName)-\(UUID().uuidString).json", isDirectory: false)
    }

    private func writeLegacyStorageFile(
        at url: URL,
        storedEvents: [[String: Any]],
        sequenceCounter: Int
    ) throws {
        try writeJSONObject(
            [
                "eventsByID": Dictionary(
                    uniqueKeysWithValues: storedEvents.enumerated().map { index, storedEvent in
                        ("legacy-\(index)", storedEvent)
                    }
                ),
                "sequenceCounter": sequenceCounter
            ],
            to: url
        )
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted])
        try data.write(to: url, options: [.atomic])
    }

    private func eventJSONObject(_ event: SnapshotActivationHistoryEvent) -> [String: Any] {
        let data = try! JSONEncoder().encode(event)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func persistedJSONObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    private func corruptedBackups(for originalURL: URL) throws -> [URL] {
        let directory = originalURL.deletingLastPathComponent()
        let base = originalURL.deletingPathExtension().lastPathComponent
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("\(base).corrupted.") }
    }
}
