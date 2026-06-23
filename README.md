# AidRun iOS Frontend

This repository contains only the native iOS frontend for AidRun / 助盲跑. It does not contain, maintain, build, or deploy backend code. The backend is an external service, and the only real integration endpoint is `http://47.114.113.171`.

## Requirements

- Xcode with iOS 16+ SDK support
- CocoaPods dependencies installed
- A valid AMap iOS key in the ignored `LocalConfig.xcconfig`

Open `blindRun.xcworkspace`, not the `.xcodeproj` file.

## Configuration

Copy `LocalConfig.xcconfig.example` to `LocalConfig.xcconfig` and set `AMAP_API_KEY`. Do not commit the real key.

Development builds can switch between:

- `Mock`: in-process frontend data for offline UI and automated tests; it makes no network requests.
- `Demo Cloud`: HTTP requests use `http://47.114.113.171` and WebSocket connections use `ws://47.114.113.171`.

Demo and Production build channels are locked to Demo Cloud. There is no configurable alternative server and no server runtime in this repository.

## Validation

```bash
openspec validate remove-local-backend-use-cloud-only --strict --no-interactive
xcodebuild -workspace blindRun.xcworkspace -scheme blindRun -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS Simulator,name=iPhone 15'
```

Cloud E2E checks use `scripts/cloud-e2e.mjs` and depend on the external service being available.

## Contracts

- HTTP API: `docs/07-api-contract.openapi.yaml`
- WebSocket: `docs/websocket-protocol.md`
- Agent rules: `AGENTS.md`
