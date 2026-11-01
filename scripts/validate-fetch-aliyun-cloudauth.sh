#!/usr/bin/env bash
set -uo pipefail
# scripts/fetch-aliyun-cloudauth.sh 的自测。不联网：用 file:// 地址指向现做的假压缩包。
# 脚本的地址和校验值写死、不读环境变量，所以这里用 sed 改出一份只换这几个常量的副本来跑。
#
# 这个脚本坏掉的后果藏得深：Frameworks/ 没东西时 `#if canImport(AliyunFaceAuthFacade)` 为假，
# App 照样编译通过，只是没有活体 SDK。所以这里重点守「校验不过绝不放行」和「不完整就重新解压」。
cd "$(dirname "$0")/.."
FETCH="scripts/fetch-aliyun-cloudauth.sh"
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/aidrun-cloudauth.XXXXXX")" || { echo "[validate-fetch-aliyun-cloudauth] mktemp 失败" >&2; exit 1; }
trap 'rm -rf "$SANDBOX"' EXIT

PASS=0
FAIL=0
ok()  { printf '  ✅ %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL + 1)); }

SOURCE_DIR="${SANDBOX}/src/iOS-2.3.50-Aliyun"
mkdir -p "$SOURCE_DIR"

# make_module <压缩包名> <framework 名> [framework 内的 bundle...]
make_module() {
  local tarball="$1" framework="$2" bundle
  shift 2
  local stage="${SANDBOX}/stage-${tarball}"
  mkdir -p "${stage}/Products/${framework}.framework"
  echo binary >"${stage}/Products/${framework}.framework/${framework}"
  for bundle in "$@"; do
    mkdir -p "${stage}/Products/${framework}.framework/${bundle}"
    echo model >"${stage}/Products/${framework}.framework/${bundle}/toyger.face.dat"
  done
  tar -czf "${SOURCE_DIR}/${tarball}-1.0.0-bin.tgz" -C "$stage" Products
}

make_module AliyunFaceAuthFacade AliyunFaceAuthFacade
make_module ToygerService ToygerService ToygerService.bundle
make_module DTFIdentityManager DTFIdentityManager
make_module ToygerNative ToygerNative
make_module BioAuthEngine BioAuthEngine BioAuthEngine.bundle
make_module DTFUtility DTFUtility
make_module VerifyNativeAbility VerifyNativeAbility
make_module APBToygerFacade APBToygerFacade APBToygerFacade.bundle APBToygerFacadeSuitable.bundle
make_module AliyunDevicePKG faceguard
make_module APPSecuritySDK APPSecuritySDK
# 官方包里有、但我们不要的模块。
make_module OCRDetectSDKForTech OCRDetectSDKForTech

GOOD_ZIP="${SANDBOX}/good.zip"
( cd "${SANDBOX}/src" && zip -qr "$GOOD_ZIP" iOS-2.3.50-Aliyun ) || { echo "[validate-fetch-aliyun-cloudauth] zip 失败" >&2; exit 1; }
GOOD_SHA="$(shasum -a 256 "$GOOD_ZIP" | cut -d ' ' -f 1)"

DEST="${SANDBOX}/dest"
CACHE="${SANDBOX}/cache"
DEAD_URL="file://${SANDBOX}/no-such-file.zip"

# run_fetch <地址> <校验值>：跑一次，返回脚本的退出码，输出写进 ${SANDBOX}/out.log。
run_fetch() {
  sed -e "s|^ARCHIVE_URL=.*|ARCHIVE_URL=\"$1\"|" -e "s|^ARCHIVE_SHA256=.*|ARCHIVE_SHA256=\"$2\"|" \
    -e "s|^DEST=.*|DEST=\"${DEST}\"|" -e "s|^CACHE_DIR=.*|CACHE_DIR=\"${CACHE}\"|" \
    -e 's|^CURL_RETRIES=.*|CURL_RETRIES=0|' "$FETCH" >"${SANDBOX}/fetch-copy.sh"
  bash "${SANDBOX}/fetch-copy.sh" >"${SANDBOX}/out.log" 2>&1
}

echo "[validate-fetch-aliyun-cloudauth] 1/9 SOURCE.md 记录的校验值与脚本一致"
PINNED="$(sed -n 's/^ARCHIVE_SHA256="\([0-9a-f]*\)"$/\1/p' "$FETCH")"
if [ "${#PINNED}" -eq 64 ] && grep -q "$PINNED" Vendor/AliyunCloudAuth/2.3.50/SOURCE.md; then
  ok "两处都是 ${PINNED}"
else
  bad "脚本里的校验值（${PINNED}）没有写进 SOURCE.md"
fi

echo "[validate-fetch-aliyun-cloudauth] 2/9 校验值不符时失败，且什么都不留下"
run_fetch "file://${GOOD_ZIP}" "0000000000000000000000000000000000000000000000000000000000000000"
RC=$?
[ "$RC" -ne 0 ] && ok "退出 ${RC}" || bad "校验值不符却退出 0"
grep -q 'SHA-256 不符' "${SANDBOX}/out.log" && ok "报错点名 SHA-256" || bad "报错没说校验失败：$(cat "${SANDBOX}/out.log")"
[ ! -e "${DEST}/Frameworks" ] && ok "没有解压任何东西" || bad "校验失败后 Frameworks/ 还是出现了"
[ -z "$(ls "$CACHE" 2>/dev/null)" ] && ok "缓存目录没有留下坏文件" || bad "缓存里留下了：$(ls "$CACHE")"

echo "[validate-fetch-aliyun-cloudauth] 3/9 校验通过时只装 ID_PRO 子集"
run_fetch "file://${GOOD_ZIP}" "$GOOD_SHA"
RC=$?
[ "$RC" -eq 0 ] && ok "退出 0" || bad "退出 ${RC}：$(cat "${SANDBOX}/out.log")"
COUNT="$(find "${DEST}/Frameworks" -maxdepth 1 -name '*.framework' | wc -l | tr -d ' ')"
[ "$COUNT" -eq 10 ] && ok "10 个 framework" || bad "framework 数量是 ${COUNT}"
[ -f "${DEST}/Frameworks/faceguard.framework/faceguard" ] && ok "AliyunDevicePKG 解出 faceguard" || bad "缺 faceguard"
[ ! -e "${DEST}/Frameworks/OCRDetectSDKForTech.framework" ] && ok "OCR 模块被排除" || bad "OCR 模块进了 Frameworks/"
RES_COUNT="$(find "${DEST}/Resources" -maxdepth 1 -name '*.bundle' | wc -l | tr -d ' ')"
[ "$RES_COUNT" -eq 4 ] && ok "Resources/ 有 4 个 bundle" || bad "bundle 数量是 ${RES_COUNT}"
[ -z "$(find "$DEST" -maxdepth 1 -name '.fetch.*')" ] && ok "临时目录已清理" || bad "临时目录没清理"

echo "[validate-fetch-aliyun-cloudauth] 4/9 已完整时不联网"
run_fetch "$DEAD_URL" "$GOOD_SHA"
RC=$?
[ "$RC" -eq 0 ] && ok "地址失效也退出 0" || bad "已完整时仍去下载，退出 ${RC}：$(cat "${SANDBOX}/out.log")"

echo "[validate-fetch-aliyun-cloudauth] 5/9 少一个 framework 时，用缓存重新解压"
rm -rf "${DEST}/Frameworks/ToygerNative.framework"
run_fetch "$DEAD_URL" "$GOOD_SHA"
RC=$?
[ "$RC" -eq 0 ] && [ -s "${DEST}/Frameworks/ToygerNative.framework/ToygerNative" ] \
  && ok "补回来了，没有联网" || bad "没补回来，退出 ${RC}：$(cat "${SANDBOX}/out.log")"

echo "[validate-fetch-aliyun-cloudauth] 6/9 活体模型为空时不算完整"
: >"${DEST}/Resources/ToygerService.bundle/toyger.face.dat"
run_fetch "$DEAD_URL" "$GOOD_SHA"
RC=$?
[ "$RC" -eq 0 ] && [ -s "${DEST}/Resources/ToygerService.bundle/toyger.face.dat" ] \
  && ok "模型恢复了" || bad "空模型被当成完整，退出 ${RC}"

echo "[validate-fetch-aliyun-cloudauth] 7/9 上次被强杀时，清掉残留并重新解压"
rm -f "${DEST}/.fetched-sha256"
mkdir -p "${DEST}/.fetch.killed"
run_fetch "$DEAD_URL" "$GOOD_SHA"
RC=$?
[ "$RC" -eq 0 ] && [ -f "${DEST}/.fetched-sha256" ] && ok "没有完成标记时重新解压" || bad "没有重新解压，退出 ${RC}：$(cat "${SANDBOX}/out.log")"
[ ! -e "${DEST}/.fetch.killed" ] && ok "残留的临时目录被清掉" || bad "残留的临时目录还在"

echo "[validate-fetch-aliyun-cloudauth] 8/9 缓存被改坏时不使用，且官方包缺模块时失败"
echo corrupted >"${CACHE}/${GOOD_SHA}.zip"
rm -f "${DEST}/.fetched-sha256"
run_fetch "$DEAD_URL" "$GOOD_SHA"
RC=$?
[ "$RC" -ne 0 ] && ok "坏缓存被拒绝，退出 ${RC}" || bad "用了改坏的缓存"
rm -f "${SOURCE_DIR}"/DTFUtility-*-bin.tgz
PARTIAL_ZIP="${SANDBOX}/partial.zip"
( cd "${SANDBOX}/src" && zip -qr "$PARTIAL_ZIP" iOS-2.3.50-Aliyun )
PARTIAL_SHA="$(shasum -a 256 "$PARTIAL_ZIP" | cut -d ' ' -f 1)"
run_fetch "file://${PARTIAL_ZIP}" "$PARTIAL_SHA"
RC=$?
[ "$RC" -ne 0 ] && grep -q '没有模块 DTFUtility' "${SANDBOX}/out.log" \
  && ok "缺模块时点名失败" || bad "缺模块没有失败，退出 ${RC}：$(cat "${SANDBOX}/out.log")"
[ ! -f "${DEST}/.fetched-sha256" ] && ok "失败后没有写完成标记" || bad "失败后留下了完成标记"

# 需求写的是「下载失败时 pod install 必须失败」。这里只读 podspec 文件开头那段，Pod::Spec 用桩代替，
# 所以不需要 CocoaPods。脚本放在真实的相对位置上，podspec 里的 ../../../ 写错时第一条会红。
echo "[validate-fetch-aliyun-cloudauth] 9/9 下载脚本失败时，podspec 让 pod install 失败"
PODSPEC_ROOT="${SANDBOX}/podspec-root"
mkdir -p "${PODSPEC_ROOT}/scripts" "${PODSPEC_ROOT}/Vendor/AliyunCloudAuth/2.3.50"
cp Vendor/AliyunCloudAuth/2.3.50/AliyunCloudAuth.podspec "${PODSPEC_ROOT}/Vendor/AliyunCloudAuth/2.3.50/"
load_podspec() {
  ruby -e 'module Pod; class Spec; def self.new(*); end; end; end; load ARGV[0]' \
    "${PODSPEC_ROOT}/Vendor/AliyunCloudAuth/2.3.50/AliyunCloudAuth.podspec" >"${SANDBOX}/out.log" 2>&1
}
printf '#!/bin/bash\ntouch "%s/fetch-ran"\nexit 0\n' "$SANDBOX" >"${PODSPEC_ROOT}/scripts/fetch-aliyun-cloudauth.sh"
load_podspec
RC=$?
[ "$RC" -eq 0 ] && [ -f "${SANDBOX}/fetch-ran" ] && ok "下载脚本成功时 podspec 正常，且确实调用了脚本" || bad "podspec 没有调用下载脚本，退出 ${RC}：$(cat "${SANDBOX}/out.log")"
printf '#!/bin/bash\nexit 1\n' >"${PODSPEC_ROOT}/scripts/fetch-aliyun-cloudauth.sh"
load_podspec
RC=$?
[ "$RC" -ne 0 ] && ok "下载脚本失败时 podspec 中止，退出 ${RC}" || bad "下载脚本失败，podspec 却继续了：pod install 会退出 0，App 悄悄没有活体认证"

echo "[validate-fetch-aliyun-cloudauth] passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ]
