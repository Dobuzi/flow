import Foundation

struct FlowCacheKey: Hashable {
    let datasetVersion: String
    let spatialLevel: SpatialLevel
    let timeBucketID: String
    let modeSet: Set<TransportMode>
    let unitType: String

    var stringValue: String {
        let modes = modeSet.map(\.rawValue).sorted().joined(separator: ",")
        return "\(datasetVersion)|\(spatialLevel.rawValue)|\(timeBucketID)|\(modes)|\(unitType)"
    }
}

actor CacheDataSource {
    struct CacheStats: Equatable {
        let memoryEntries: Int
        let memoryUsageBytes: Int
        let memoryBudgetBytes: Int
        let diskFiles: Int
        let diskUsageBytes: Int
        let diskBudgetBytes: Int
    }

    static let shared = CacheDataSource()

    private struct Entry {
        var flows: [FlowRecord]
        var cost: Int
        var lastAccess: Date
    }

    private var memoryStore: [String: Entry] = [:]
    private var currentMemoryCost = 0
    private let memoryBudgetBytes = 120 * 1024 * 1024
    private let diskBudgetBytes = 500 * 1024 * 1024
    private let fileManager = FileManager.default

    private lazy var cacheDirectory: URL = {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = base.appendingPathComponent("FlowCache", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    func getFlows(for key: FlowCacheKey) -> [FlowRecord]? {
        let k = key.stringValue
        if var entry = memoryStore[k] {
            entry.lastAccess = Date()
            memoryStore[k] = entry
            return entry.flows
        }

        let diskURL = fileURL(for: k)
        guard let data = try? Data(contentsOf: diskURL),
              let flows = try? JSONDecoder().decode([FlowRecord].self, from: data) else {
            return nil
        }

        let cost = estimatedCost(for: flows)
        memoryStore[k] = Entry(flows: flows, cost: cost, lastAccess: Date())
        currentMemoryCost += cost
        enforceMemoryBudget()
        return flows
    }

    func setFlows(_ flows: [FlowRecord], for key: FlowCacheKey) {
        let k = key.stringValue
        let cost = estimatedCost(for: flows)

        if let existing = memoryStore[k] {
            currentMemoryCost -= existing.cost
        }
        memoryStore[k] = Entry(flows: flows, cost: cost, lastAccess: Date())
        currentMemoryCost += cost
        enforceMemoryBudget()

        let diskURL = fileURL(for: k)
        if let data = try? JSONEncoder().encode(flows) {
            try? data.write(to: diskURL, options: .atomic)
        }
        enforceDiskBudget()
    }

    func clearAll() {
        memoryStore.removeAll()
        currentMemoryCost = 0

        guard let urls = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) else { return }

        for url in urls {
            try? fileManager.removeItem(at: url)
        }
    }

    func cacheStats() -> CacheStats {
        let diskFilesAndUsage = diskStats()
        return CacheStats(
            memoryEntries: memoryStore.count,
            memoryUsageBytes: currentMemoryCost,
            memoryBudgetBytes: memoryBudgetBytes,
            diskFiles: diskFilesAndUsage.files,
            diskUsageBytes: diskFilesAndUsage.bytes,
            diskBudgetBytes: diskBudgetBytes
        )
    }

    private func enforceMemoryBudget() {
        guard currentMemoryCost > memoryBudgetBytes else { return }
        let sorted = memoryStore.sorted { $0.value.lastAccess < $1.value.lastAccess }
        for (key, entry) in sorted where currentMemoryCost > memoryBudgetBytes {
            currentMemoryCost -= entry.cost
            memoryStore.removeValue(forKey: key)
        }
    }

    private func enforceDiskBudget() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else { return }

        var fileInfos: [(url: URL, size: Int, modified: Date)] = []
        var totalSize = 0

        for url in urls {
            guard
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                let size = values.fileSize,
                let modified = values.contentModificationDate
            else { continue }
            totalSize += size
            fileInfos.append((url, size, modified))
        }

        guard totalSize > diskBudgetBytes else { return }
        for file in fileInfos.sorted(by: { $0.modified < $1.modified }) where totalSize > diskBudgetBytes {
            try? fileManager.removeItem(at: file.url)
            totalSize -= file.size
        }
    }

    private func fileURL(for key: String) -> URL {
        let safeKey = key.replacingOccurrences(of: "[^a-zA-Z0-9._-]", with: "_", options: .regularExpression)
        return cacheDirectory.appendingPathComponent(safeKey).appendingPathExtension("json")
    }

    private func estimatedCost(for flows: [FlowRecord]) -> Int {
        max(flows.count * 256, 1)
    }

    private func diskStats() -> (files: Int, bytes: Int) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return (files: 0, bytes: 0)
        }

        var bytes = 0
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            bytes += values?.fileSize ?? 0
        }
        return (files: urls.count, bytes: bytes)
    }
}
