import Foundation

@main
struct FilteringTestMain {
    static func main() {
        do {
            try FilteringEngineTests.runAll()
            print("FilteringEngineTests: PASS")
        } catch {
            print("FilteringEngineTests: FAIL - \(error)")
            exit(1)
        }
    }
}
