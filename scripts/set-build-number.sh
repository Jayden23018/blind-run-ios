#!/bin/sh
# Xcode 构建阶段：把刚处理好的 Info.plist 里的 CFBundleVersion 改成当前提交数。
#
# 为什么要有：工程里 CURRENT_PROJECT_VERSION 写死是 1，手机上装的包永远显示 1.0 (1)，
# 看不出是哪一版代码编的（2026-09-24 负责人问「手机上的包是不是最新」时只能靠对时间线判断）。
#
# 挂在 blindRun 与 blindRunWidget 两个 target 上，两边算的是同一个数 ——
# App 扩展的 CFBundleVersion 必须与主 App 一致，否则上架校验报错。
# 这两个 target 关了 ENABLE_USER_SCRIPT_SANDBOXING：沙箱里读不了 .git。
#
# ponytail: 只取提交数。不同分支可能撞同一个数；要精确到提交再加一个写 git 短哈希的自定义键。
set -eu

plist="${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"

# 取不到（没有 git、不是仓库）就不改，保留工程里的默认值，不让构建失败。
if ! count=$(git -C "${SRCROOT}" rev-list --count HEAD 2>/dev/null); then
  echo "warning: 取不到 git 提交数，build 号保持 ${CURRENT_PROJECT_VERSION:-1}"
  exit 0
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${count}" "${plist}"
echo "CFBundleVersion = ${count}（${PRODUCT_NAME}）"
