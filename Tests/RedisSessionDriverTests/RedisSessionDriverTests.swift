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

  func testCreateSessionWithCustomTTLsFailsOpen() async throws {
    let app = try makeUnreachableApp()
    let req = Request(application: app, on: app.eventLoopGroup.next())
    // The TTL-setting `expire` call, like the initial `set`, must also fail open rather than
    // surfacing a Redis outage as a request error.
    let driver = ResilientRedisSessionDriver(idleTTL: 3600, absoluteTTL: 86400 * 7)
    let data = SessionData()

    let id = try await driver.createSession(data, for: req)

    XCTAssertFalse(id.string.isEmpty)
    try await app.asyncShutdown()
  }

  // MARK: Expiry decision

  private let day: TimeInterval = 24 * 60 * 60

  private func decide(
    age: TimeInterval, idleDays: TimeInterval = 30, absoluteDays: TimeInterval = 90
  ) -> ResilientRedisSessionDriver.ExpiryDecision {
    ResilientRedisSessionDriver.expiryDecision(
      createdAt: 1_000_000,
      now: 1_000_000 + age,
      idleTTL: idleDays * day,
      absoluteTTL: absoluteDays * day
    )
  }

  func testFreshSessionRenewsForIdleWindow() {
    XCTAssertEqual(.valid(renewFor: 30 * day), decide(age: 0))
    XCTAssertEqual(.valid(renewFor: 30 * day), decide(age: 10 * day))
  }

  func testActiveSessionNearCapRenewsOnlyRemainingTime() {
    // Renewal must not push past the absolute cap: at day 80 only 10 days remain.
    XCTAssertEqual(.valid(renewFor: 10 * day), decide(age: 80 * day))
    XCTAssertEqual(.valid(renewFor: day / 2), decide(age: 90 * day - day / 2))
  }

  func testSessionAtAbsoluteCapIsExpired() {
    XCTAssertEqual(.expired, decide(age: 90 * day))
    XCTAssertEqual(.expired, decide(age: 200 * day))
  }

  func testMissingCreatedAtIsExpired() {
    // Pre-0.1.0 sessions carry no created_at; they must read as expired, not immortal.
    let decision = ResilientRedisSessionDriver.expiryDecision(
      createdAt: nil,
      now: 1_000_000,
      idleTTL: 30 * day,
      absoluteTTL: 90 * day
    )
    XCTAssertEqual(.expired, decision)
  }

  func testNegativeAgeIsExpired() {
    // Clock-skew guard: created_at in the future means malformed data.
    XCTAssertEqual(.expired, decide(age: -day))
  }
}
