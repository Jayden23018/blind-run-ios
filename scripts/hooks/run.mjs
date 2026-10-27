#!/usr/bin/env node

// 钩子转发器（#483）。`.claude/settings.json` 里每个钩子都经它启动：
//   node "$CLAUDE_PROJECT_DIR/scripts/hooks/run.mjs" <钩子名> [参数…]
//
// 为什么要它：桌面 App 开的 worktree 会话从**主 checkout** 读 settings 与钩子，钩子在主 checkout
// 根目录里跑，`$CLAUDE_PROJECT_DIR` 也指向主 checkout（官方 worktrees 文档
// 「What worktrees share with the main checkout」，2026-10-28 核实）。于是 worktree 会话执行的是
// 主 checkout 那份钩子、读的是主 checkout 的状态 —— main 上对钩子的修复，到不了任何 worktree 会话，
// 直到有人更新主 checkout（2026-10-19 实测主 checkout 停在 10-02 的分支上）。
// 官方给的出路是读钩子输入里的 `cwd` 字段：它才是会话实际所在的 worktree。
//
// 做法：从 stdin 读钩子输入，取 `cwd`，找到它所在的 git worktree；那个 worktree 属于本仓库、
// 且有同名钩子时，就跑那一份（工作目录与 `CLAUDE_PROJECT_DIR` 都改成那个 worktree 的根）；
// 否则跑转发器自己这份。输入、输出、退出码原样透传 —— 退出码 2 照样能拦工具调用。
// 转发器自己出错一律退出 1（非阻断错误）：开工被卡住比漏跑一次提醒更糟。

import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const HOOK_NAME = /^[a-z][a-z0-9-]*$/;
const GIT_TIMEOUT_MS = 3000;

const ownRoot = path.resolve(import.meta.dirname, '../..');

function git(cwd, ...args) {
  try {
    return execFileSync('git', ['-C', cwd, ...args], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      timeout: GIT_TIMEOUT_MS,
    }).trim();
  } catch {
    return null;
  }
}

// 同一个仓库的所有 worktree 共用一个 git common dir；后端仓库等别的仓库不共用。
function commonDir(root) {
  const dir = git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir');
  if (!dir) return null;
  try {
    return fs.realpathSync(dir);
  } catch {
    return null;
  }
}

export function hookPath(root, hook) {
  return path.join(root, 'scripts', 'hooks', `${hook}.mjs`);
}

// 返回该跑哪一份钩子的仓库根。`selfRoot` 只给测试用。
export function resolveHookRoot(cwd, hook, selfRoot = ownRoot) {
  if (typeof cwd !== 'string' || !cwd || !fs.existsSync(cwd)) return selfRoot;
  const top = git(cwd, 'rev-parse', '--show-toplevel');
  if (!top || !fs.existsSync(hookPath(top, hook))) return selfRoot;
  const mine = commonDir(selfRoot);
  if (!mine || mine !== commonDir(top)) return selfRoot;
  return top;
}

function main() {
  const [hook, ...args] = process.argv.slice(2);
  if (!hook || !HOOK_NAME.test(hook)) {
    console.error(`[hooks/run] 钩子名不合法：${hook ?? '(空)'}`);
    process.exit(1);
  }
  const input = fs.readFileSync(0);
  let cwd = null;
  try {
    cwd = JSON.parse(input.toString('utf8')).cwd;
  } catch {
    // 输入不是 JSON：跑自己这份，由钩子本身决定怎么处理。
  }
  const root = resolveHookRoot(cwd, hook);
  const result = spawnSync(process.execPath, [hookPath(root, hook), ...args], {
    input,
    cwd: root,
    stdio: ['pipe', 'inherit', 'inherit'],
    env: { ...process.env, CLAUDE_PROJECT_DIR: root },
  });
  if (result.error) {
    console.error(`[hooks/run] ${hook} 没能启动：${result.error.message}`);
    process.exit(1);
  }
  process.exit(result.status ?? 1);
}

// 比真实路径：node 给 import.meta.url 的是解析过软链接的路径，argv[1] 是调用时写的路径
// （macOS 的 /var → /private/var、/tmp → /private/tmp 都会让两者不等，main() 就静默不跑）。
function invokedDirectly() {
  try {
    return import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href;
  } catch {
    return false;
  }
}

if (invokedDirectly()) main();
