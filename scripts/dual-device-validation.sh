#!/usr/bin/env bash
set -euo pipefail

BLIND_DEVICE="${AIDRUN_BLIND_DEVICE_NAME:-111}"
VOLUNTEER_DEVICE="${AIDRUN_VOLUNTEER_DEVICE_NAME:-iPad Pro (2)}"

echo "[dual-device] blind device: ${BLIND_DEVICE}"
echo "[dual-device] volunteer device: ${VOLUNTEER_DEVICE}"

node scripts/validate-docs.mjs
openspec validate remove-local-backend-use-cloud-only --strict --no-interactive

echo "[dual-device] baseline XCTest on blind device"
xcodebuild test \
  -workspace blindRun.xcworkspace \
  -scheme blindRun \
  -destination "platform=iOS,name=${BLIND_DEVICE}"

echo "[dual-device] baseline XCTest on volunteer device"
xcodebuild test \
  -workspace blindRun.xcworkspace \
  -scheme blindRun \
  -destination "platform=iOS,name=${VOLUNTEER_DEVICE}"

if [[ "${AIDRUN_RUN_REAL_AMAP:-0}" == "1" ]]; then
  echo "[dual-device] real AMap smoke on blind device"
  AIDRUN_UI_TEST_REAL_AMAP=1 xcodebuild test \
    -workspace blindRun.xcworkspace \
    -scheme blindRun \
    -destination "platform=iOS,name=${BLIND_DEVICE}" \
    -only-testing:blindRunUITests/blindRunUITests/testRealAMapEnabledSmoke

  echo "[dual-device] real AMap smoke on volunteer device"
  AIDRUN_UI_TEST_REAL_AMAP=1 xcodebuild test \
    -workspace blindRun.xcworkspace \
    -scheme blindRun \
    -destination "platform=iOS,name=${VOLUNTEER_DEVICE}" \
    -only-testing:blindRunUITests/blindRunUITests/testRealAMapEnabledSmoke
else
  echo "[dual-device] skip real AMap smoke; set AIDRUN_RUN_REAL_AMAP=1 to enable"
fi

if [[ "${AIDRUN_RUN_CLOUD_UI:-0}" == "1" ]]; then
  echo "[dual-device] Demo Cloud UI smoke on blind device"
  AIDRUN_UI_TEST_RUN_CLOUD_SMOKE=1 xcodebuild test \
    -workspace blindRun.xcworkspace \
    -scheme blindRun-Demo \
    -destination "platform=iOS,name=${BLIND_DEVICE}" \
    -only-testing:blindRunUITests/blindRunUITests/testCloudBackendBlindRunnerBookingSmoke

  echo "[dual-device] Demo Cloud UI smoke on volunteer device"
  AIDRUN_UI_TEST_RUN_CLOUD_SMOKE=1 xcodebuild test \
    -workspace blindRun.xcworkspace \
    -scheme blindRun-Demo \
    -destination "platform=iOS,name=${VOLUNTEER_DEVICE}" \
    -only-testing:blindRunUITests/blindRunUITests/testCloudBackendBlindRunnerBookingSmoke
else
  echo "[dual-device] skip Demo Cloud UI smoke; set AIDRUN_RUN_CLOUD_UI=1 to enable"
fi

if [[ "${AIDRUN_RUN_CLOUD_E2E:-0}" == "1" ]]; then
  echo "[dual-device] backend cloud E2E"
  node scripts/cloud-e2e.mjs
else
  echo "[dual-device] skip backend cloud E2E; set AIDRUN_RUN_CLOUD_E2E=1 to enable"
fi

echo "[dual-device] manual final pass: use ${BLIND_DEVICE} as blind runner and ${VOLUNTEER_DEVICE} as volunteer for the real-time order flow"
