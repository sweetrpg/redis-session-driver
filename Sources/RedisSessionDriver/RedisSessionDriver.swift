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
/// Every write sets the underlying Redis key's TTL to `ttl` (refreshed on each
/// `updateSession`, so an active session stays alive; an idle one expires `ttl` after its last
/// write). Once the key's TTL elapses, Redis drops it and `readSession` sees a plain cache miss
/// - the same path as "no session" - so expiry needs no separate date check here. See
/// `sweetrpg/platform`'s `resilient-session-storage` spec ("Sessions carry an expiry and are
/// not read past it").
public struct ResilientRedisSessionDriver: AsyncSessionDriver {
  /// Default session lifetime: 24 hours, matching Auth0's typical access token lifetime.
  /// Confirm against the actual configured lifetime in the Auth0 dashboard for this tenant
  /// (not captured as code - see `auth-web`'s `AGENTS.md`) and override via `init(ttl:)` if it
  /// diverges.
  public static let defaultTTL: TimeInterval = 60 * 60 * 24

  private let ttl: TimeInterval

  public init(ttl: TimeInterval = defaultTTL) {
    self.ttl = ttl
  }

  private func key(for id: SessionID) -> RedisKey { RedisKey("vrs-\(id.string)") }

  private func makeID() -> SessionID {
    SessionID(string: [UInt8].random(count: 32).base64String())
  }

  private func setWithTTL(_ key: RedisKey, data: SessionData, request: Request) async throws {
    try await request.redis.set(key, toJSON: data).get()
    _ = try await request.redis.expire(key, after: .seconds(Int64(ttl))).get()
  }

  public func createSession(_ data: SessionData, for request: Request) async throws -> SessionID {
    let id = makeID()
    do {
      try await setWithTTL(key(for: id), data: data, request: request)
    } catch {
      request.logger.warning("Redis unavailable, session will not persist: \(error)")
    }
    return id
  }

  public func readSession(_ sessionID: SessionID, for request: Request) async throws -> SessionData? {
    do {
      return try await request.redis.get(key(for: sessionID), asJSON: SessionData.self).get()
    } catch {
      request.logger.warning("Redis unavailable, treating request as logged-out: \(error)")
      return nil
    }
  }

  public func updateSession(
    _ sessionID: SessionID, to data: SessionData, for request: Request
  ) async throws -> SessionID {
    do {
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
