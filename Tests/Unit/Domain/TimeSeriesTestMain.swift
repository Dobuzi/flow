import Foundation

@main
struct TimeSeriesTestMain {
    static func main() {
        do {
            try TimeSeriesEngineTests.runAll()
            print("TimeSeriesEngineTests: PASS")
        } catch {
            print("TimeSeriesEngineTests: FAIL - \(error)")
            exit(1)
        }
    }
}
