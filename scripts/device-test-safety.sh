#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE_ID="com.jerry.aidrun"
UI_TEST_RUNNER_BUNDLE_ID="com.jerry.aidrun.uitests.xctrunner"

hash_app_state() {
  local device="$1"
  local destination="$2"
  local transfer_dir
  transfer_dir="$(mktemp -d)"
  local plist="${transfer_dir}/com.jerry.aidrun.plist"

  if ! xcrun devicectl device copy from \
    --device "${device}" \
    --domain-type appDataContainer \
    --domain-identifier "${APP_BUNDLE_ID}" \
    --source "Library/Preferences/com.jerry.aidrun.plist" \
    --destination "${plist}" \
    --quiet; then
    printf '%s\n' "APP_STATE_MISSING" | shasum -a 256 | awk '{print $1}' > "${destination}"
    rm -rf "${transfer_dir}"
    return
  fi

  {
    for key in \
      com.aidrun.mvp.apiEnvironment \
      com.aidrun.mvp.activeRole \
      com.aidrun.mvp.userId \
      com.aidrun.mvp.accessToken; do
      printf '%s=' "${key}"
      plutil -extract "${key}" raw -o - "${plist}" 2>/dev/null || printf '%s' "<missing>"
      printf '\n'
    done
  } | shasum -a 256 | awk '{print $1}' > "${destination}"
  rm -rf "${transfer_dir}"
}

assert_app_state() {
  local device="$1"
  local expected_file="$2"
  local actual_file
  actual_file="$(mktemp)"
  hash_app_state "${device}" "${actual_file}"
  if ! cmp -s "${expected_file}" "${actual_file}"; then
    echo "[device-safety] ERROR: ${device} 的环境/角色/userId/token 脱敏哈希在测试后发生变化" >&2
    rm -f "${actual_file}"
    return 1
  fi
  echo "[device-safety] ${device} 的正常 App 会话哈希未改变"
  rm -f "${actual_file}"
}

terminate_test_hosts() {
  local device="$1"
  local json_file
  json_file="$(mktemp)"
  if xcrun devicectl device info processes --device "${device}" --json-output "${json_file}" --quiet; then
    jq -r '.. | objects | select((.executable? // "") | test("blindRun(UITests-Runner)?$")) | .processIdentifier? // empty' "${json_file}" \
      | sort -u \
      | while read -r pid; do
          [[ -n "${pid}" ]] || continue
          xcrun devicectl device process terminate --device "${device}" --pid "${pid}" --quiet || true
        done
  fi
  rm -f "${json_file}"
}

build_demo_app() {
  local device="$1"
  local suffix
  suffix="$(printf '%s' "${device}" | shasum -a 256 | awk '{print substr($1,1,12)}')"
  local derived_data="${AIDRUN_DEMO_DERIVED_DATA:-/tmp/aidrun-demo-${suffix}-derived}"
  xcodebuild build \
    -workspace blindRun.xcworkspace \
    -scheme blindRun-Demo \
    -configuration DemoRelease \
    -destination "platform=iOS,name=${device}" \
    -derivedDataPath "${derived_data}"
  printf '%s\n' "${derived_data}/Build/Products/DemoRelease-iphoneos/blindRun.app"
}

install_and_launch_demo() {
  local device="$1"
  local app_path="$2"
  xcrun devicectl device install app --device "${device}" "${app_path}" --quiet
  xcrun devicectl device process launch --device "${device}" --terminate-existing "${APP_BUNDLE_ID}" --quiet
  echo "[device-safety] ${device} 已安装并启动 blindRun-Demo / DemoRelease"
}

case "${1:-}" in
  snapshot)
    hash_app_state "$2" "$3"
    ;;
  assert)
    assert_app_state "$2" "$3"
    ;;
  terminate)
    terminate_test_hosts "$2"
    ;;
  build-demo)
    build_demo_app "$2"
    ;;
  install-demo)
    install_and_launch_demo "$2" "$3"
    ;;
  "")
    ;;
  *)
    echo "usage: $0 {snapshot DEVICE FILE|assert DEVICE FILE|terminate DEVICE|build-demo DEVICE|install-demo DEVICE APP_PATH}" >&2
    exit 64
    ;;
esac
