#!/usr/bin/env node
//
// scripts/install-git-hooks.sh 生成的 pre-push 里「后端契约取自哪份文件」的回归测试。
//
// 为什么需要它：那 4 道契约门禁是本地唯一一道（CI 配不上 BACKEND_REPO_TOKEN，见
// AGENTS.md §11），而 ../demo 是共享 checkout。一旦门禁改回读工作区文件，症状不是报错，
// 而是**一条听起来很有道理的错误建议**：
//
//   [pre-push] ✗ 生成代码与契约不同步，把重新生成的结果一起提交：
//    M Packages/AidRunAPI/Sources/AidRunAPI/Types.swift
//
// 照它做，就是把同事未合并的契约烘进自己的 PR；而 CI 从后端默认分支拉契约，两边必然对不上。
// 2026-08-09 实测踩到。AGENTS.md §1.3 要求这类事落到机器归宿，这就是那个归宿。
//
// 做法：把安装脚本里真正会被写进 .git/hooks 的那段 body 抠出来跑，而不是另抄一份逻辑 ——
// 抄一份的话，改了钩子却没改测试时它照样绿。

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const installer = path.resolve(import.meta.dirname, 'install-git-hooks.sh');
const GEN_DIR = 'Packages/AidRunAPI/Sources/AidRunAPI';

// ── 从安装脚本里取出契约来源那一段 ──────────────────────────────────────────
const body = fs
  .readFileSync(installer, 'utf8')
  .split(/^cat > "\$HOOK" <<'HOOK_BODY'$/m)[1]
  ?.split(/^HOOK_BODY$/m)[0];
if (!body) {
  console.error('✗ 抠不出 pre-push body —— 安装脚本的 heredoc 结构变了，先修这个测试再说。');
  process.exit(1);
}
const start = body.indexOf('BACKEND_DIR="${AIDRUN_BACKEND_DIR');
const end = body.indexOf('if [ "$fail" -ne 0 ]');
if (start < 0 || end < 0 || end <= start) {
  console.error('✗ 抠不出契约来源段落（BACKEND_DIR … fail 判定之间）。');
  process.exit(1);
}
const section = body.slice(start, end);

// ── 造 fixture：后端 origin/main 是契约，工作区是同事未提交的 WIP ────────────
//
// 必须先把继承来的 GIT_* 全部剥掉。git 在跑钩子时会导出 GIT_DIR / GIT_WORK_TREE /
// GIT_INDEX_FILE，指向**本仓库**；带着它们去 /tmp 里造 fixture，git init/commit 会
// 报 `fatal: this operation must be run in a work tree`，于是这个测试单跑全绿、
// 从 pre-push 里跑却红 —— 正好在它唯一要起作用的地方失效。2026-08-09 实测踩到。
const cleanEnv = (extra = {}) => {
  const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith('GIT_')));
  return {
    ...env,
    GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t',
    GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t',
    ...extra,
  };
};

const git = (cwd, ...args) => spawnSync('git', args, { cwd, encoding: 'utf8', env: cleanEnv() });

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-prepush-src-'));
const backend = path.join(tmp, 'backend');
const app = path.join(tmp, 'app');

const FILES = {
  'docs/api_spec.yaml': (tag) => `openapi: 3.0.3\ninfo: {title: ${tag}, version: 1.0.0}\n`,
  'docs/voice-golden-corpus.json': (tag) => `{"corpus":"${tag}"}\n`,
  'src/main/java/com/example/demo/exception/ErrorCode.java': (tag) => `enum ErrorCode { ${tag} }\n`,
};
const writeContracts = (tag) => {
  for (const [rel, make] of Object.entries(FILES)) {
    fs.mkdirSync(path.join(backend, path.dirname(rel)), { recursive: true });
    fs.writeFileSync(path.join(backend, rel), make(tag));
  }
};

fs.mkdirSync(backend);
git(backend, 'init', '-q', '-b', 'main', '.');
writeContracts('UPSTREAM');
git(backend, 'add', '-A');
git(backend, 'commit', '-qm', 'contract');
git(tmp, 'init', '-q', '--bare', 'backend-origin.git');
git(backend, 'remote', 'add', 'origin', path.join(tmp, 'backend-origin.git'));
git(backend, 'push', '-q', 'origin', 'main');
writeContracts('COLLEAGUE_WIP'); // 同事未提交的契约改动，留在工作区

// 前端：产物基线与 origin/main 的契约一致（= 已经是最新的，不该被判不同步）
fs.mkdirSync(path.join(app, GEN_DIR), { recursive: true });
fs.mkdirSync(path.join(app, 'scripts'), { recursive: true });
git(app, 'init', '-q', '-b', 'main', '.');
fs.writeFileSync(path.join(app, GEN_DIR, 'Client.swift'), 'let generatedFrom = "UPSTREAM"\n');
// 桩生成器：把契约里的 title 写进产物，于是「契约不同」直接体现为「产物变脏」。
// 不跑真的 swift-openapi-generator —— 这里要验的是读了哪份契约，不是生成器本身。
fs.writeFileSync(
  path.join(app, 'scripts/generate-api-client.sh'),
  `#!/usr/bin/env bash\ntitle="$(sed -n 's/.*title: \\([A-Za-z_0-9]*\\).*/\\1/p' "$1" | head -1)"\n` +
    `[ -z "$title" ] && title="$(sed -n 's/.*"corpus":"\\([A-Za-z_0-9]*\\)".*/\\1/p' "$1" | head -1)"\n` +
    `echo "let generatedFrom = \\"$title\\"" > ${GEN_DIR}/Client.swift\n`,
  { mode: 0o755 },
);
git(app, 'add', '-A');
git(app, 'commit', '-qm', 'baseline');

// 桩 run()：只回显每道门禁**实际拿到的文件内容**，这才是本测试要断言的东西。
const harness = `set -uo pipefail
fail=0
run() { label="$1"; shift; echo "GATE $label :: $(head -1 "\${@: -1}")"; }
${section}
echo "FAIL=$fail"
`;
fs.writeFileSync(path.join(app, 'harness.sh'), harness);

function runHook(env = {}) {
  git(app, 'checkout', '-q', '--', '.'); // 上一条用例可能把产物改脏了
  const r = spawnSync('bash', ['harness.sh'], {
    cwd: app,
    encoding: 'utf8',
    // 同样要剥 GIT_*：被测段落里的 `git -C … show` 和 `git status --porcelain`
    // 一旦被 GIT_DIR 指回本仓库，验的就不是 fixture 了。
    env: cleanEnv({ AIDRUN_BACKEND_DIR: backend, ...env }),
  });
  return r.stdout + r.stderr;
}

// ── 用例 ────────────────────────────────────────────────────────────────────
const cases = [
  {
    name: '默认路径：3 份契约全部取自 origin/main，不读后端工作区的 WIP',
    check: () => {
      const out = runHook();
      if (out.includes('COLLEAGUE_WIP')) {
        return `门禁读到了后端工作区未提交的契约。实得：\n${out}`;
      }
      const gates = out.split('\n').filter((l) => l.startsWith('GATE '));
      return gates.length === 3 ? null : `期望 3 道 run 门禁都拿到文件，实得 ${gates.length}：\n${out}`;
    },
  },
  {
    name: '默认路径：后端工作区脏着不得让 push 失败（旧版新鲜度检查会误拦）',
    check: () => {
      const out = runHook();
      return out.includes('FAIL=0') ? null : `期望 FAIL=0，实得：\n${out}`;
    },
  },
  {
    // 这条是本次事故的正脸：契约不是 origin/main 时，绝不能叫人提交重新生成的结果。
    name: '契约来自后端工作区时，不得出现「一起提交」的建议',
    check: () => {
      const out = runHook({ AIDRUN_ALLOW_BACKEND_DRIFT: '1' });
      if (!out.includes('COLLEAGUE_WIP')) return `期望读到工作区 WIP 契约，实得：\n${out}`;
      if (out.includes('一起提交')) return `叫人提交了拿 WIP 契约生成的结果：\n${out}`;
      return out.includes('别提交') ? null : `期望明确说「别提交」，实得：\n${out}`;
    },
  },
  {
    name: 'AIDRUN_API_SPEC 显式指定时，同样不得建议提交，且来源标签不许谎称 origin/main',
    check: () => {
      const spec = path.join(tmp, 'mine.yaml');
      fs.writeFileSync(spec, 'openapi: 3.0.3\ninfo: {title: MYLOCAL, version: 2.0.0}\n');
      const out = runHook({ AIDRUN_API_SPEC: spec });
      if (out.includes('一起提交')) return `叫人提交了拿非上游契约生成的结果：\n${out}`;
      const label = out.split('\n').find((l) => l.includes('重新生成 API 客户端并比对')) || '';
      return label.includes('AIDRUN_API_SPEC')
        ? null
        : `来源标签没说清是显式指定的，实得：${JSON.stringify(label)}`;
    },
  },
  {
    name: '取不到契约时明说没跑（跳过 ≠ 通过），且不假装失败',
    check: () => {
      const out = runHook({ AIDRUN_BACKEND_DIR: path.join(tmp, 'nope') });
      const skipped = out.split('\n').filter((l) => l.includes('这不算通过。')).length;
      if (skipped !== 3) return `期望 3 条「这不算通过」，实得 ${skipped}：\n${out}`;
      return out.includes('FAIL=0') ? null : `读不到契约不该判 push 失败：\n${out}`;
    },
  },
];

let failed = 0;
for (const c of cases) {
  let err;
  try {
    err = c.check();
  } catch (e) {
    err = `用例自身抛错：${e.message}`;
  }
  if (err) {
    failed += 1;
    console.error(`✗ ${c.name}\n  ${err.split('\n').join('\n  ')}`);
  } else {
    console.log(`✓ ${c.name}`);
  }
}

fs.rmSync(tmp, { recursive: true, force: true });

if (failed) {
  console.error(`\n${failed}/${cases.length} 条未通过。`);
  process.exit(1);
}
console.log(`\n${cases.length}/${cases.length} 条通过。`);
