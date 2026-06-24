#!/usr/bin/env bash
set -euo pipefail

DEVICE_NAME="${AIDRUN_DEVICE_NAME:-111}"
DESTINATION="platform=iOS,name=${DEVICE_NAME}"

echo "[production-readiness] device: ${DEVICE_NAME}"

echo "[production-readiness] validate maintained docs"
node scripts/validate-docs.mjs

echo "[production-readiness] validate OpenSpec cloud-only change"
openspec validate remove-local-backend-use-cloud-only --strict --no-interactive

echo "[production-readiness] run real-device XCTest baseline"
xcodebuild test \
  -workspace blindRun.xcworkspace \
  -scheme blindRun \
  -destination "${DESTINATION}"

if [[ "${AIDRUN_RUN_REAL_AMAP:-0}" == "1" ]]; then
  echo "[production-readiness] run real AMap device smoke"
  AIDRUN_UI_TEST_REAL_AMAP=1 xcodebuild test \
    -workspace blindRun.xcworkspace \
    -scheme blindRun \
    -destination "${DESTINATION}" \
    -only-testing:blindRunUITests/blindRunUITests/testRealAMapEnabledSmoke
else
  echo "[production-readiness] skip real AMap smoke; set AIDRUN_RUN_REAL_AMAP=1 to enable"
fi

if [[ "${AIDRUN_RUN_CLOUD_UI:-0}" == "1" ]]; then
  echo "[production-readiness] run real cloud UI smoke"
  AIDRUN_UI_TEST_RUN_CLOUD_SMOKE=1 xcodebuild test \
    -workspace blindRun.xcworkspace \
    -scheme blindRun-Demo \
    -destination "${DESTINATION}" \
    -only-testing:blindRunUITests/blindRunUITests/testCloudBackendBlindRunnerBookingSmoke
else
  echo "[production-readiness] skip real cloud UI smoke; set AIDRUN_RUN_CLOUD_UI=1 to enable"
fi

if [[ "${AIDRUN_RUN_CLOUD_E2E:-0}" == "1" ]]; then
  echo "[production-readiness] run backend cloud E2E"
  node scripts/cloud-e2e.mjs
else
  echo "[production-readiness] skip backend cloud E2E; set AIDRUN_RUN_CLOUD_E2E=1 to enable"
fi

echo "[production-readiness] complete"
