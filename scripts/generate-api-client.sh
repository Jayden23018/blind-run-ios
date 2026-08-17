#!/usr/bin/env bash
#
# 从后端契约重新生成 OpenAPI 客户端代码。产物 check-in 进仓库。
#
#   scripts/generate-api-client.sh [后端 api_spec.yaml 路径]
#
# 契约的唯一源在后端仓库 blind-run-backend（本机 /Users/mac/Downloads/demo），
# 本仓库不留副本（AGENTS.md §7）。所以这个脚本必须能拿到后端仓库路径：
# 用第一个参数传，或设 AIDRUN_BACKEND_SPEC 环境变量。
#
# CI 用法：跑完之后 `git diff --exit-code Packages/AidRunAPI/Sources/AidRunAPI`。
# 非空 diff = 有人改了 spec 却没重新生成，或改了生成产物却没改 spec。

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="${1:-${AIDRUN_BACKEND_SPEC:-/Users/mac/Downloads/demo/docs/api_spec.yaml}}"
CONFIG="$REPO_ROOT/scripts/openapi/openapi-generator-config.yaml"
# 产物落在独立的 AidRunAPI 包里，不在 App target 内 —— 原因见
# Packages/AidRunAPI/Package.swift 顶部（主工程的 MainActor 默认隔离与生成代码相撞）。
OUT_DIR="$REPO_ROOT/Packages/AidRunAPI/Sources/AidRunAPI"

if [[ ! -f "$SPEC" ]]; then
  echo "[generate-api-client] 找不到契约文件：$SPEC" >&2
  echo "[generate-api-client] 用参数传后端仓库的 docs/api_spec.yaml，或设 AIDRUN_BACKEND_SPEC。" >&2
  exit 1
fi

# 契约必须是 3.0.x。这条检查不是形式主义：spec 曾经声称 3.1.0 却用了 nullable，
# 而 3.1 移除了该关键字 —— 3.1 感知的生成器会把那些可空字段生成成非可选，
# 服务端返 null 时客户端直接解码崩。
SPEC_VERSION="$(head -5 "$SPEC" | sed -n 's/^openapi: *//p' | head -1)"
case "$SPEC_VERSION" in
  3.0.*) ;;
  *)
    echo "[generate-api-client] 契约版本是 '$SPEC_VERSION'，预期 3.0.x。" >&2
    echo "[generate-api-client] 若后端确实升到了 3.1，先确认 nullable 字段已改成 type 数组再放行。" >&2
    exit 1
    ;;
esac

echo "[generate-api-client] 契约：$SPEC (openapi $SPEC_VERSION)"
echo "[generate-api-client] 产物：$OUT_DIR"

mkdir -p "$OUT_DIR"

# --package-path 指向只钉版本的工具包；首次运行要下载并编译生成器（约 1 分钟），之后走缓存。
swift run \
  --package-path "$REPO_ROOT/scripts/openapi" \
  -c release \
  swift-openapi-generator generate \
  --config "$CONFIG" \
  --output-directory "$OUT_DIR" \
  "$SPEC"

echo "[generate-api-client] 完成："
wc -l "$OUT_DIR"/*.swift
