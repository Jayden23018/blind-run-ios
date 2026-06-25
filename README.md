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

Mock is useful for deterministic UI and unit tests, but it is not sufficient for release sign-off. Production-readiness validation must run on the real devices named `111` and `iPad Pro (2)` with real AMap and the external backend enabled.

## Validation

```bash
node scripts/validate-docs.mjs
openspec validate remove-local-backend-use-cloud-only --strict --no-interactive
xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=111'
xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=iPad Pro (2)'
```

Real integration checks:

```bash
AIDRUN_UI_TEST_REAL_AMAP=1 xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=111' -only-testing:blindRunUITests/blindRunUITests/testRealAMapEnabledSmoke
AIDRUN_UI_TEST_RUN_CLOUD_SMOKE=1 xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun-Demo -destination 'platform=iOS,name=111' -only-testing:blindRunUITests/blindRunUITests/testCloudBackendBlindRunnerBookingSmoke
node scripts/cloud-e2e.mjs
```

Full production-readiness check:

```bash
AIDRUN_DEVICE_NAME=111 AIDRUN_RUN_REAL_AMAP=1 AIDRUN_RUN_CLOUD_UI=1 AIDRUN_RUN_CLOUD_E2E=1 scripts/production-readiness-check.sh
scripts/dual-device-validation.sh
```

Cloud E2E checks depend on the external service being available and may create/cancel test orders.
Administrator volunteer review for test accounts can be performed with `scripts/admin-review-volunteer.mjs` using `AIDRUN_ADMIN_USERNAME`, `AIDRUN_ADMIN_PASSWORD`, and either `AIDRUN_ADMIN_REVIEW_USER_ID` or `AIDRUN_ADMIN_REVIEW_PHONE`. The long-lived test admin account is `admin` / `admin123`. The administrator review UI is a later standalone web management surface; do not add an administrator role or review page to the iOS user app in this change.

## Contracts

- HTTP API: `docs/07-api-contract.openapi.yaml`
- WebSocket: `docs/websocket-protocol.md`
- Agent rules: `AGENTS.md`
- Production plan: `plan.md`
