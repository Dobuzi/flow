import Foundation

@main
struct TestMain {
    static func main() async {
        do {
            try await DataLayerTests.runAll()
            print("DataLayerTests: PASS")
        } catch {
            print("DataLayerTests: FAIL - \(error)")
            exit(1)
        }
    }
}
