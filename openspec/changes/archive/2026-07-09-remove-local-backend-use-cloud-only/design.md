## Context

The workspace currently mixes an iOS client, a repository-owned server implementation, Mock data, and multiple real-server environment concepts. The deployed service at `http://47.114.113.171` is now the only real integration target.

## Goals / Non-Goals

**Goals:**
- Keep the repository runnable as a native iOS frontend.
- Preserve Mock for deterministic offline UI and XCTest coverage.
- Route all non-Mock HTTP and WebSocket traffic to the fixed cloud host.
- Remove local backend implementation and stale derived documentation.

**Non-Goals:**
- Change, deploy, or document the implementation technology of the external server.
- Add another configurable backend address.
- Remove Mock frontend behavior.

## Decisions

- `APIEnvironment` has only `mock` and `demoCloud` cases.
- Development defaults to Mock and may switch to cloud; Demo and Production builds always use cloud.
- A single Info plist contains the narrowly scoped ATS exception for `47.114.113.171`.
- Unknown persisted environment values fall back through the build channel default without preserving local-server-specific migration code.
- Git history, rather than checked-in obsolete artifacts, preserves the removed backend implementation history.

## Risks / Trade-offs

- The fixed HTTP endpoint requires an ATS exception and is unsuitable for App Store production until the external service adopts HTTPS.
- Cloud E2E availability depends on an external service and is reported separately from local build and unit-test results.
