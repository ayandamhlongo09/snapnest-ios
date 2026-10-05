import XCTest
@testable import CaptureCore

final class RetryPolicyTests: XCTestCase {
    func testRetryDelayIsExponentialAndCapped() {
        let policy = RetryPolicy()
        XCTAssertEqual((1...7).map { policy.delay(after: $0) }, [2,4,8,16,32,60,60])
    }
}
