import Redis
import Vapor

/// Redis-backed session driver that degrades instead of failing the request when Redis is
/// unreachable. Vapor's stock `RedisSessionsDriver` (used via `app.sessions.use(.redis)`)
/// propagates any Redis error straight through `SessionsMiddleware`, which runs on every
/// request - so a Redis outage would 500 the whole app, not just the caching path that
/// a typical cache-backed service already degrades gracefully.
///
/// Reads fail open to "no session" (the request proceeds as logged-out); writes and deletes are
/// logged and swallowed so the response still succeeds, at the cost of the session not
/// surviving until Redis recovers.
///
/// Sessions expire under two independent limits (see `sweetrpg/platform`'s
/// `session-expiration-policy` spec):
///
/// - **Idle expiry** - every write and every successful read sets the key's TTL to `idleTTL`
///   (renewed on each touch), so an actively-used session stays alive while an abandoned one
///   expires `idleTTL` after its last touch.
/// - **Absolute cap** - `createSession` stamps `created_at` into the stored JSON;
///   `readSession` treats a session whose age reaches `absoluteTTL` as invalid regardless of
///   activity, so renewal can never extend a session past `absoluteTTL` from creation.
///
/// Either limit produces exactly the same observable result as a nonexistent session: once the
/// key's TTL elapses Redis drops it, and an over-cap key is deleted on first read. Sessions
/// written before this scheme existed (no `created_at`) are treated as already expired and
/// self-clean on first read.
public struct ResilientRedisSessionDriver: AsyncSessionDriver {
  /// Default rolling idle expiry: 30 days. A starting recommendation, not a constant expected
  /// to be right forever - callers override via `init(idleTTL:absoluteTTL:)`.
  public static let defaultIdleTTL: TimeInterval = 30 * 24 * 60 * 60

  /// Default absolute lifetime cap: 90 days from creation. Same caveat as `defaultIdleTTL`.
  public static let defaultAbsoluteTTL: TimeInterval = 90 * 24 * 60 * 60

  /// Field added to the stored session JSON at creation; epoch seconds.
  private static let createdAtField = "created_at"

  private let idleTTL: TimeInterval
  private let absoluteTTL: TimeInterval

  public init(
    idleTTL: TimeInterval = ResilientRedisSessionDriver.defaultIdleTTL,
    absoluteTTL: TimeInterval = ResilientRedisSessionDriver.defaultAbsoluteTTL
  ) {
    self.idleTTL = idleTTL
    self.absoluteTTL = absoluteTTL
  }

  /// Outcome of checking one stored session against its two limits.
  enum ExpiryDecision: Equatable {
    /// Session is valid; its Redis TTL should be renewed to `renewFor`.
    case valid(renewFor: TimeInterval)
    /// Session must not be served (past the cap, or missing/malformed `created_at`).
    case expired
  }

  /// Pure expiry math, extracted for unit testing without a live Redis.
  static func expiryDecision(
    createdAt: TimeInterval?,
    now: TimeInterval,
    idleTTL: TimeInterval,
    absoluteTTL: TimeInterval
  ) -> ExpiryDecision {
    guard let createdAt else { return .expired }
    let age = now - createdAt
    guard age >= 0, age < absoluteTTL else { return .expired }
    return .valid(renewFor: min(idleTTL, absoluteTTL - age))
  }

  private func key(for id: SessionID) -> RedisKey { RedisKey("vrs-\(id.string)") }

  private func makeID() -> SessionID {
    SessionID(string: [UInt8].random(count: 32).base64String())
  }

  private func setWithTTL(_ key: RedisKey, data: SessionData, request: Request) async throws {
    try await request.redis.set(key, toJSON: data).get()
    _ = try await request.redis.expire(key, after: .seconds(Int64(idleTTL))).get()
  }

  public func createSession(_ data: SessionData, for request: Request) async throws -> SessionID {
    let id = makeID()
    var stored = data
    stored[Self.createdAtField] = String(Int64(Date().timeIntervalSince1970))
    do {
      try await setWithTTL(key(for: id), data: stored, request: request)
    } catch {
      request.logger.warning("Redis unavailable, session will not persist: \(error)")
    }
    return id
  }

  public func readSession(_ sessionID: SessionID, for request: Request) async throws -> SessionData? {
    do {
      guard let data = try await request.redis.get(key(for: sessionID), asJSON: SessionData.self).get() else {
        return nil
      }
      switch Self.expiryDecision(
        createdAt: data[Self.createdAtField].flatMap(TimeInterval.init),
        now: Date().timeIntervalSince1970,
        idleTTL: idleTTL,
        absoluteTTL: absoluteTTL
      ) {
      case .expired:
        // Self-cleaning: drop the dead key outright when possible. If this fails (Redis blip),
        // the key's own TTL still reaps it later - either way the caller sees nil.
        try? await request.redis.delete(key(for: sessionID)).get()
        return nil
      case .valid(let renewFor):
        // Plain EXPIRE, not a full rewrite: reads happen on every page-view across every
        // frontend and must not re-serialize the session value.
        _ = try await request.redis.expire(key(for: sessionID), after: .seconds(Int64(renewFor))).get()
        return data
      }
    } catch {
      request.logger.warning("Redis unreachable, treating request as logged-out: \(error)")
      return nil
    }
  }

  public func updateSession(
    _ sessionID: SessionID, to data: SessionData, for request: Request
  ) async throws -> SessionID {
    do {
      // `data` round-trips whatever was loaded, including the original `created_at` - updates
      // refresh the idle TTL but never reset the absolute-cap clock.
      try await setWithTTL(key(for: sessionID), data: data, request: request)
    } catch {
      request.logger.warning("Redis unavailable, session update dropped: \(error)")
    }
    return sessionID
  }

  public func deleteSession(_ sessionID: SessionID, for request: Request) async throws {
    do {
      _ = try await request.redis.delete(key(for: sessionID)).get()
    } catch {
      request.logger.warning("Redis unavailable, session delete dropped: \(error)")
    }
  }
}
