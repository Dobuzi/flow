import Foundation

final class PerformanceMonitor {
    private var metrics: [String: [Double]] = [:]

    func record(_ key: String, milliseconds: Double) {
        metrics[key, default: []].append(milliseconds)
    }

    func measure(_ key: String, operation: () -> Void) {
        let start = CFAbsoluteTimeGetCurrent()
        operation()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        record(key, milliseconds: elapsed)
    }

    func average(_ key: String) -> Double? {
        guard let samples = metrics[key], !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / Double(samples.count)
    }

    func p95(_ key: String) -> Double? {
        guard let samples = metrics[key], !samples.isEmpty else { return nil }
        let sorted = samples.sorted()
        let index = Int(Double(sorted.count - 1) * 0.95)
        return sorted[index]
    }

    func report() -> [String: (avg: Double, p95: Double)] {
        var output: [String: (avg: Double, p95: Double)] = [:]
        for key in metrics.keys {
            if let avg = average(key), let p95 = p95(key) {
                output[key] = (avg, p95)
            }
        }
        return output
    }
}
