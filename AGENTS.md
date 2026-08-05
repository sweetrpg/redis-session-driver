# AGENTS.md

This file provides guidance to Claude Code, Codex, GitHub Copilot, and other coding agents
working in this repository.

## About This Project

`redis-session-driver` is a Swift package providing `ResilientRedisSessionDriver`, a Vapor
`AsyncSessionDriver` backed by Redis that fails open on a Redis outage (degrades to
"logged out" instead of 500ing). It's a shared dependency of every sweetrpg Vapor frontend that
needs Redis-backed sessions - `catalog-web`, `admin-web`, `auth-web` - replacing what used to be
a hand-maintained copy of the same file in each. Lives at `foundational/redis-session-driver` in
`sweetrpg/platform`.

## Committing Code

[Conventional Commits](https://www.conventionalcommits.org/): `<type>(<scope>): <description>`.

## Branches and Workflow

Git-flow (see `docs/git-flow.md` in `sweetrpg/platform`): `develop` is the integration branch,
`master` reflects the latest release. Feature/fix branches off `develop`, PR back into `develop`.

## Running Checks Locally

```bash
swift build
swift test
```
