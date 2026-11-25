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

## Platform Conventions and Decisions

This repo is a submodule of `sweetrpg/platform`. Platform-wide conventions and Architecture
Decision Records live there:

- checked out inside the platform tree: `../../../docs/README.md` (convention index) and
  `../../../docs/adr/README.md` (platform ADRs, `PADR-*`)
- standalone or module-only checkout:
  <https://github.com/sweetrpg/platform/tree/master/docs> and
  <https://github.com/sweetrpg/platform/tree/master/docs/adr>

Accepted `PADR-*` records are binding constraints. Read the ADR index before proposing a
structural change; if a task needs to contradict an accepted record, stop and say so -
propose a superseding ADR rather than working around it. This repo's own service-local
decisions are `ADR-*` and belong in `docs/adr/` here.

Before implementing any feature, complete the
[feature work checkpoint](https://github.com/sweetrpg/platform/blob/master/docs/openspec.md#feature-work-checkpoint)
and record the answers in the issue or PR.
