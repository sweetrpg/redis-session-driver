import Redis
import XCTVapor

@testable import RedisSessionDriver

final class RedisSessionDriverTests: XCTestCase {
  /// No Redis server listens on this port, so every `request.redis` call fails with a
  /// connection error - simulating a Redis outage.
  private func makeUnreachableApp() throws -> Application {
    let app = try Application(.testing)
    app.redis.configuration = try RedisConfiguration(hostname: "127.0.0.1", port: 1)
    try app.boot()
    return app
  }

  func testCreateSessionFailsOpen() async throws {
    let app = try makeUnreachableApp()
    let req = Request(application: app, on: app.eventLoopGroup.next())
    let driver = ResilientRedisSessionDriver()
    let data = SessionData()

    let id = try await driver.createSession(data, for: req)

    XCTAssertFalse(id.string.isEmpty)
    try await app.asyncShutdown()
  }

  func testReadSessionFailsOpenToNil() async throws {
    let app = try makeUnreachableApp()
    let req = Request(application: app, on: app.eventLoopGroup.next())
    let driver = ResilientRedisSessionDriver()

    let result = try await driver.readSession(SessionID(string: "does-not-matter"), for: req)

    XCTAssertNil(result)
    try await app.asyncShutdown()
  }

  func testUpdateSessionFailsOpen() async throws {
    let app = try makeUnreachableApp()
    let req = Request(application: app, on: app.eventLoopGroup.next())
    let driver = ResilientRedisSessionDriver()
    let sessionID = SessionID(string: "existing-session")

    let returnedID = try await driver.updateSession(sessionID, to: SessionData(), for: req)

    XCTAssertEqual(returnedID, sessionID)
    try await app.asyncShutdown()
  }

  func testDeleteSessionFailsOpen() async throws {
    let app = try makeUnreachableApp()
    let req = Request(application: app, on: app.eventLoopGroup.next())
    let driver = ResilientRedisSessionDriver()

    // Doesn't throw despite Redis being unreachable.
    try await driver.deleteSession(SessionID(string: "existing-session"), for: req)
    try await app.asyncShutdown()
  }

  func testCreateSessionWithCustomTTLFailsOpen() async throws {
    let app = try makeUnreachableApp()
    let req = Request(application: app, on: app.eventLoopGroup.next())
    // The TTL-setting `expire` call, like the initial `set`, must also fail open rather than
    // surfacing a Redis outage as a request error.
    let driver = ResilientRedisSessionDriver(ttl: 3600)
    let data = SessionData()

    let id = try await driver.createSession(data, for: req)

    XCTAssertFalse(id.string.isEmpty)
    try await app.asyncShutdown()
  }
}
