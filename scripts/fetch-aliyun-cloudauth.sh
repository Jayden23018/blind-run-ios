#!/usr/bin/env bash
# 把阿里云实人认证 SDK 下载到 Vendor/AliyunCloudAuth/<版本>/（#636）。
#
# 这份 SDK 是闭源二进制，公开仓库不存放，每台机器从阿里云官方地址取。
# AliyunCloudAuth.podspec 在 CocoaPods 读它时调用本脚本，所以 `pod install` 一步就够，平时不用手动跑。
#
# 已经下载完整时什么都不做，也不联网。官方压缩包缓存在 CACHE_DIR，多个 worktree 共用，不重复下载。
# 自测：scripts/validate-fetch-aliyun-cloudauth.sh。校验值故意写死，不接受环境变量覆盖。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="2.3.50"
ARCHIVE_URL="https://cn-shanghai-aliyun-cloudauth.oss-cn-shanghai.aliyuncs.com/cloudauth_sdk/${VERSION}/iOS-${VERSION}-Aliyun.zip"
ARCHIVE_SHA256="a6072c00adf8f533f46ca5de03eb2dd25d8d85e558f0c7d9702b7c731366feca"
DEST="Vendor/AliyunCloudAuth/${VERSION}"
CACHE_DIR="${HOME}/Library/Caches/AidRun"
CURL_RETRIES=5
STAMP="${DEST}/.fetched-sha256"

# ID_PRO 人脸核验必选的 10 个模块，见 docs/08-ios-architecture.md 第 12 节。
# OCR、NFC、多因子和美颜不进构建产物。官方压缩包里 faceguard 的包名叫 AliyunDevicePKG。
TARBALLS=(AliyunFaceAuthFacade ToygerService DTFIdentityManager ToygerNative BioAuthEngine
  DTFUtility VerifyNativeAbility APBToygerFacade AliyunDevicePKG APPSecuritySDK)
FRAMEWORKS=(AliyunFaceAuthFacade ToygerService DTFIdentityManager ToygerNative BioAuthEngine
  DTFUtility VerifyNativeAbility APBToygerFacade faceguard APPSecuritySDK)
# podspec 的 s.resources 要这 4 个 bundle，它们在官方包里放在各自的 framework 内。
BUNDLES=(APBToygerFacade.framework/APBToygerFacade.bundle
  APBToygerFacade.framework/APBToygerFacadeSuitable.bundle
  BioAuthEngine.framework/BioAuthEngine.bundle
  ToygerService.framework/ToygerService.bundle)

WORK=""
TMP_ZIP=""
cleanup() {
  if [ -n "$WORK" ]; then rm -rf "$WORK"; fi
  if [ -n "$TMP_ZIP" ]; then rm -f "$TMP_ZIP"; fi
}
trap cleanup EXIT

die() {
  echo "[fetch-aliyun-cloudauth] ❌ $1" >&2
  exit 1
}

sha256_of() {
  shasum -a 256 "$1" | cut -d ' ' -f 1
}

# 只看标记文件不够：别的工具删掉一个 framework 时，标记还在。
is_complete() {
  [ "$(cat "$STAMP" 2>/dev/null)" = "$ARCHIVE_SHA256" ] || return 1
  local framework bundle
  for framework in "${FRAMEWORKS[@]}"; do
    [ -s "${DEST}/Frameworks/${framework}.framework/${framework}" ] || return 1
  done
  for bundle in "${BUNDLES[@]}"; do
    [ -d "${DEST}/Resources/${bundle##*/}" ] || return 1
  done
  # 活体模型缺失或为空时 SDK 跑不起来，见 testCloudAuthRequiredResourcesAreBundled。
  [ -s "${DEST}/Resources/ToygerService.bundle/toyger.face.dat" ]
}

# 设置 ARCHIVE。别改成 `ARCHIVE="$(...)"`：子进程不跑 EXIT 清理，失败时临时文件会留在缓存目录。
ensure_archive() {
  ARCHIVE="${CACHE_DIR}/${ARCHIVE_SHA256}.zip"
  if [ -f "$ARCHIVE" ] && [ "$(sha256_of "$ARCHIVE")" = "$ARCHIVE_SHA256" ]; then
    return
  fi
  mkdir -p "$CACHE_DIR"
  TMP_ZIP="$(mktemp "${CACHE_DIR}/download.XXXXXX")"
  echo "[fetch-aliyun-cloudauth] 下载 ${ARCHIVE_URL}" >&2
  curl --fail --location --silent --show-error --retry "$CURL_RETRIES" --retry-all-errors \
    --connect-timeout 20 --max-time 900 --output "$TMP_ZIP" "$ARCHIVE_URL" \
    || die "下载失败：${ARCHIVE_URL}。检查网络或代理后重跑 pod install。"
  local actual
  actual="$(sha256_of "$TMP_ZIP")"
  [ "$actual" = "$ARCHIVE_SHA256" ] \
    || die "SHA-256 不符。期望 ${ARCHIVE_SHA256}，实际 ${actual}。不要改校验值放行，先查官方包是否换了内容。"
  mv "$TMP_ZIP" "$ARCHIVE"
  TMP_ZIP=""
}

if is_complete; then
  exit 0
fi

ensure_archive
mkdir -p "$DEST"
# 被强杀时 EXIT 清理不运行，旧的临时目录要在这里清掉。
rm -rf "${DEST}"/.fetch.*
WORK="$(mktemp -d "${DEST}/.fetch.XXXXXX")"
unzip -q "$ARCHIVE" -d "${WORK}/archive"
SOURCE_DIR="${WORK}/archive/iOS-${VERSION}-Aliyun"

mkdir -p "${WORK}/unpacked" "${WORK}/Resources"
for tarball in "${TARBALLS[@]}"; do
  matches=("${SOURCE_DIR}/${tarball}"-*-bin.tgz)
  [ -f "${matches[0]}" ] || die "官方包里没有模块 ${tarball}。"
  tar -xzf "${matches[0]}" -C "${WORK}/unpacked"
done
for bundle in "${BUNDLES[@]}"; do
  [ -d "${WORK}/unpacked/Products/${bundle}" ] || die "官方包里没有 ${bundle}。"
  cp -R "${WORK}/unpacked/Products/${bundle}" "${WORK}/Resources/"
done

rm -f "$STAMP"
rm -rf "${DEST}/Frameworks" "${DEST}/Resources"
mv "${WORK}/unpacked/Products" "${DEST}/Frameworks"
mv "${WORK}/Resources" "${DEST}/Resources"
# 标记最后写：中途被打断时下次会重新解压。
printf '%s\n' "$ARCHIVE_SHA256" >"$STAMP"
is_complete || die "解压结果不完整：${DEST}。"
echo "[fetch-aliyun-cloudauth] 已就绪：${DEST}" >&2
