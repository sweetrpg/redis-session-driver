import XCTest

@testable import RedisSessionDriver

final class RedisSessionDriverTests: XCTestCase {
    func testPlaceholder() throws {
        // Fail-open behavior tests land here in a follow-up commit alongside the extracted
        // ResilientRedisSessionDriver.
    }
}
