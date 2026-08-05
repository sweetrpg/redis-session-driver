# redis-session-driver

[![Coverage](https://img.shields.io/endpoint?url=https://sweetrpg.github.io/redis-session-driver/coverage-badge.json)](https://sweetrpg.github.io/redis-session-driver/)

A Vapor `AsyncSessionDriver` backed by Redis that fails open - a Redis read/write error degrades
a request to "logged out" instead of propagating as a 500. Shared by every sweetrpg Vapor
frontend that needs Redis-backed sessions (`catalog-web`, `admin-web`, `auth-web`), replacing a
copy of the same ~50 lines that used to be hand-maintained in each.

## Usage

```swift
app.sessions.use { _ in ResilientRedisSessionDriver() }
```
