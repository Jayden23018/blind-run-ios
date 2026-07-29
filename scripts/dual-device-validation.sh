#!/usr/bin/env bash
set -euo pipefail

BLIND_DEVICE="${AIDRUN_BLIND_DEVICE_NAME:-111}"
VOLUNTEER_DEVICE="${AIDRUN_VOLUNTEER_DEVICE_NAME:-iPad Pro (2)}"
SAFETY_SCRIPT="scripts/device-test-safety.sh"
STATE_DIR="$(mktemp -d)"
BLIND_STATE="${STATE_DIR}/blind.sha256"
VOLUNTEER_STATE="${STATE_DIR}/volunteer.sha256"

bash "${SAFETY_SCRIPT}" snapshot "${BLIND_DEVICE}" "${BLIND_STATE}"
bash "${SAFETY_SCRIPT}" snapshot "${VOLUNTEER_DEVICE}" "${VOLUNTEER_STATE}"

cleanup() {
  local status=$?
  trap - EXIT
  bash "${SAFETY_SCRIPT}" terminate "${BLIND_DEVICE}" || status=1
  bash "${SAFETY_SCRIPT}" terminate "${VOLUNTEER_DEVICE}" || status=1
  bash "${SAFETY_SCRIPT}" assert "${BLIND_DEVICE}" "${BLIND_STATE}" || status=1
  bash "${SAFETY_SCRIPT}" assert "${VOLUNTEER_DEVICE}" "${VOLUNTEER_STATE}" || status=1
  rm -rf "${STATE_DIR}"
  exit "${status}"
}
trap cleanup EXIT

echo "[dual-device] blind device: ${BLIND_DEVICE}"
echo "[dual-device] volunteer device: ${VOLUNTEER_DEVICE}"

node scripts/validate-docs.mjs
openspec validate cloud-only-api-environment --strict --no-interactive
openspec validate enable-live-escort-location-and-track-summary --strict --no-interactive

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

BLIND_DEMO_APP_PATH="$(bash "${SAFETY_SCRIPT}" build-demo "${BLIND_DEVICE}" | tail -n 1)"
VOLUNTEER_DEMO_APP_PATH="$(bash "${SAFETY_SCRIPT}" build-demo "${VOLUNTEER_DEVICE}" | tail -n 1)"
bash "${SAFETY_SCRIPT}" terminate "${BLIND_DEVICE}"
bash "${SAFETY_SCRIPT}" terminate "${VOLUNTEER_DEVICE}"
bash "${SAFETY_SCRIPT}" assert "${BLIND_DEVICE}" "${BLIND_STATE}"
bash "${SAFETY_SCRIPT}" assert "${VOLUNTEER_DEVICE}" "${VOLUNTEER_STATE}"
bash "${SAFETY_SCRIPT}" install-demo "${BLIND_DEVICE}" "${BLIND_DEMO_APP_PATH}"
bash "${SAFETY_SCRIPT}" install-demo "${VOLUNTEER_DEVICE}" "${VOLUNTEER_DEMO_APP_PATH}"
trap - EXIT
rm -rf "${STATE_DIR}"

echo "[dual-device] manual final pass: use ${BLIND_DEVICE} as blind runner and ${VOLUNTEER_DEVICE} as volunteer for the real-time order flow"
