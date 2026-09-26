#!/usr/bin/env node
//
// scripts/hooks/pre-push.sh（pre-push 正文，由 install-git-hooks.sh 装的壳 exec）里「后端契约取自哪份文件」的回归测试。
//
// 为什么需要它：那 5 道契约门禁是本地唯一一道（CI 配不上 BACKEND_REPO_TOKEN，见
// AGENTS.md §11），而 ../demo 是共享 checkout。一旦门禁改回读工作区文件，症状不是报错，
// 而是**一条听起来很有道理的错误建议**：
//
//   [pre-push] ✗ 生成代码与契约不同步，把重新生成的结果一起提交：
//    M Packages/AidRunAPI/Sources/AidRunAPI/Types.swift
//
// 照它做，就是把同事未合并的契约烘进自己的 PR；而 CI 从后端默认分支拉契约，两边必然对不上。
// 2026-08-09 实测踩到。AGENTS.md §1.3 要求这类事落到机器归宿，这就是那个归宿。
//
// 做法：直接读真正会被执行的正文 scripts/hooks/pre-push.sh 抠段落跑，而不是另抄一份逻辑 ——
// 抄一份的话，改了钩子却没改测试时它照样绿。（2026-09-24 前正文是安装脚本里的 heredoc，那时从 heredoc 抠。）

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const hookBody = path.resolve(import.meta.dirname, 'hooks/pre-push.sh');
const GEN_DIR = 'Packages/AidRunAPI/Sources/AidRunAPI';

// ── 从安装脚本里取出契约来源那一段 ──────────────────────────────────────────
const body = fs.existsSync(hookBody) ? fs.readFileSync(hookBody, 'utf8') : '';
if (!body) {
  console.error('✗ 读不到 scripts/hooks/pre-push.sh —— 正文挪地方了，先修这个测试再说。');
  process.exit(1);
}
const start = body.indexOf('BACKEND_DIR="${AIDRUN_BACKEND_DIR');
const end = body.indexOf('if [ "$fail" -ne 0 ]');
if (start < 0 || end < 0 || end <= start) {
  console.error('✗ 抠不出契约来源段落（BACKEND_DIR … fail 判定之间）。');
  process.exit(1);
}
const section = body.slice(start, end);
// 收尾那段（fail 判定 + 最终汇报）。它不属于「契约来源」，但**汇报是否诚实**要在这里验：
// 2026-08-14 事故正是 4 行 ⚠「这不算通过」之后紧跟一行「全部通过」。
const tail = body.slice(end);

// ── 造 fixture：后端 origin/main 是契约，工作区是同事未提交的 WIP ────────────
//
// 必须先把继承来的 GIT_* 全部剥掉。git 在跑钩子时会导出 GIT_DIR / GIT_WORK_TREE /
// GIT_INDEX_FILE，指向**本仓库**；带着它们去 /tmp 里造 fixture，git init/commit 会
// 报 `fatal: this operation must be run in a work tree`，于是这个测试单跑全绿、
// 从 pre-push 里跑却红 —— 正好在它唯一要起作用的地方失效。2026-08-09 实测踩到。
//
// AIDRUN_* 同理：被测段落就是读这一族变量决定契约来源的。外层用官方开口
// `AIDRUN_API_SPEC=… git push` 时它漏进每条用例，自测 3/8 红，只能 --no-verify 跳过全部门禁；
// 继承来的 AIDRUN_BACKEND_DIR 则让「不设它走默认解析」那条用例假绿（#221）。
// 用例要的值一律经 extra 显式传。
const cleanEnv = (extra = {}) => {
  const env = Object.fromEntries(
    Object.entries(process.env).filter(([k]) => !k.startsWith('GIT_') && !k.startsWith('AIDRUN_')),
  );
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

// 5 份契约 = 5 道门禁真正读到的后端文件。**加门禁时这里要一起加** ——
// 少一份，那道门禁就会绕过 backend_file 回退成读工作区，而本测试看不见它。
// 2026-08-12 补上后两个：validate-voice-intent-words 读两个 .java，
// 合 #16 时发现它们仍直接指向 ../demo 工作区路径，是这类漏网的现行例子。
const FILES = {
  'docs/api_spec.yaml': (tag) => `openapi: 3.0.3\ninfo: {title: ${tag}, version: 1.0.0}\n`,
  'docs/voice-golden-corpus.json': (tag) => `{"corpus":"${tag}"}\n`,
  'src/main/java/com/example/demo/exception/ErrorCode.java': (tag) => `enum ErrorCode { ${tag} }\n`,
  'src/main/java/com/example/demo/util/VoiceSlotParser.java': (tag) => `class VoiceSlotParser { ${tag} }\n`,
  'src/main/java/com/example/demo/service/VoiceOrderService.java': (tag) => `class VoiceOrderService { ${tag} }\n`,
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
// 前三行对应正文开头那段公共变量（契约段落之前定义，截取时拿不到）。
const harness = `set -uo pipefail
fail=0
SKIPPED_GATES=0
PREPUSH_TMP="$(mktemp -d)"; LOG="$PREPUSH_TMP/gate.log"
run() { label="$1"; shift; echo "GATE $label :: $(head -1 "\${@: -1}")"; }
${section}
echo "FAIL=$fail"
`;
fs.writeFileSync(path.join(app, 'harness.sh'), harness);
// 带收尾汇报的版本，只给「跳过 ≠ 全部通过」那条用例用。
fs.writeFileSync(path.join(app, 'harness-with-report.sh'), `${harness}${tail}`);

function runHook(env = {}, { cwd = app, script = 'harness.sh', backendDir = backend } = {}) {
  git(app, 'checkout', '-q', '--', '.'); // 上一条用例可能把产物改脏了
  const r = spawnSync('bash', [path.join(app, script)], {
    cwd,
    encoding: 'utf8',
    // 同样要剥 GIT_*：被测段落里的 `git -C … show` 和 `git status --porcelain`
    // 一旦被 GIT_DIR 指回本仓库，验的就不是 fixture 了。
    // backendDir=null 表示**不设** AIDRUN_BACKEND_DIR，走默认解析那条路径。
    env: cleanEnv({ ...(backendDir === null ? {} : { AIDRUN_BACKEND_DIR: backendDir }), ...env }),
  });
  return r.stdout + r.stderr;
}

// ── 用例 ────────────────────────────────────────────────────────────────────
const cases = [
  {
    // 2026-08-14 事故：为了不打扰并行会话，在 /tmp 开隔离 worktree 解冲突并从那里 push，
    // `../demo` 变成 `/tmp/demo`（不存在）→ 4 道读后端契约的门禁全部静默跳过。
    // 隔离 worktree 正是本仓库推荐的复验方式，所以这条不修就会反复发生。
    name: '从 linked worktree push 时，默认路径仍要按**主 worktree** 找到后端（不是当前 worktree 的 ../demo）',
    check: () => {
      // 后端放在主 worktree 的兄弟位置（真实布局：~/Downloads/blind-run-ios 与 ~/Downloads/demo）
      const sibling = path.join(tmp, 'demo');
      if (!fs.existsSync(sibling)) fs.symlinkSync(backend, sibling);
      // worktree 故意开在**另一个父目录**下：这样 `../demo` 解不出来，
      // 只有「按主 worktree 解析」才找得到。不这么放，用例会假绿。
      const away = path.join(tmp, 'elsewhere');
      fs.mkdirSync(away, { recursive: true });
      const wt = path.join(away, 'app-wt');
      if (!fs.existsSync(wt)) {
        const r = git(app, 'worktree', 'add', '-q', '--detach', wt);
        if (r.status !== 0) return `建 worktree 失败：${r.stderr}`;
      }
      if (fs.existsSync(path.join(away, 'demo'))) return 'fixture 布置错了：worktree 的 ../demo 不该存在';

      const out = runHook({}, { cwd: wt, backendDir: null });
      if (out.includes('这不算通过')) {
        return `在 linked worktree 里没找到后端契约，门禁被静默跳过 —— 就是这次的 bug。实得：\n${out}`;
      }
      const gates = out.split('\n').filter((l) => l.startsWith('GATE '));
      return gates.length === 4 ? null : `期望 4 道门禁都拿到文件，实得 ${gates.length}：\n${out}`;
    },
  },
  {
    name: '有门禁被跳过时，收尾**不许**汇报「全部通过」（只看末行的人会以为验过了）',
    check: () => {
      const empty = path.join(tmp, 'not-a-backend');
      fs.mkdirSync(empty, { recursive: true });
      const out = runHook({}, { script: 'harness-with-report.sh', backendDir: empty });
      if (!out.includes('这不算通过')) return `fixture 没造出「取不到契约」的场景：\n${out}`;
      if (out.includes('全部通过')) {
        return `4 道门禁被跳过，末行仍说「全部通过」—— 就是这次的 bug。实得：\n${out}`;
      }
      if (!/被跳过/.test(out)) return `跳过时的收尾没说清有多少道没跑：\n${out}`;
      // 跳过不是失败：不能因为读不到后端就拦住 push（离线、没 checkout 都合理）。
      return /FAIL=0/.test(out) ? null : `跳过被当成了失败：\n${out}`;
    },
  },
  {
    // 2026-09-24（workflow-review A3）：run_node 跳过「本分支没有这个校验脚本」时以前不计数，
    // 末行照样「全部通过」—— 与上一条是同一种谎，只是换了个入口。
    name: 'run_node 跳过缺失的校验脚本也要计数，末行不许说「全部通过」',
    check: () => {
      const s = body.indexOf('run_node() {');
      const fn = s < 0 ? '' : body.slice(s, body.indexOf('\n}\n', s) + 3);
      if (!fn) return '抠不出 run_node() —— 正文结构变了，先修这个测试';
      const script = path.join(app, 'harness-run-node.sh');
      fs.writeFileSync(
        script,
        `set -uo pipefail\nfail=0\nSKIPPED_GATES=0\nBACKEND_DIR=x\nrun() { :; }\n${fn}\n` +
          `run_node "不存在的校验" scripts/does-not-exist.mjs\n${tail}`
      );
      const r = spawnSync('bash', [script], { cwd: app, encoding: 'utf8', env: cleanEnv() });
      const out = `${r.stdout}${r.stderr}`;
      if (!out.includes('这不算通过')) return `run_node 没明说跳过：\n${out}`;
      return out.includes('全部通过') ? `run_node 跳过了，末行仍说「全部通过」：\n${out}` : null;
    },
  },
  {
    name: '默认路径：5 份契约全部取自 origin/main，不读后端工作区的 WIP',
    check: () => {
      const out = runHook();
      if (out.includes('COLLEAGUE_WIP')) {
        return `门禁读到了后端工作区未提交的契约。实得：\n${out}`;
      }
      const gates = out.split('\n').filter((l) => l.startsWith('GATE '));
      return gates.length === 4 ? null : `期望 4 道 run 门禁都拿到文件，实得 ${gates.length}：\n${out}`;
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
    // #221：平时 CI / pre-push 都不带这些变量跑本测试，过滤被改回去也没人发现 —— 所以在这里造一次。
    name: '外层环境里的 AIDRUN_* 不得漏进用例（否则 `AIDRUN_API_SPEC=… git push` 必被本测试拦下）',
    check: () => {
      process.env.AIDRUN_ALLOW_BACKEND_DRIFT = '1';
      try {
        const out = runHook();
        return out.includes('COLLEAGUE_WIP') ? `外层的 AIDRUN_ALLOW_BACKEND_DRIFT 漏进了用例：\n${out}` : null;
      } finally {
        delete process.env.AIDRUN_ALLOW_BACKEND_DRIFT;
      }
    },
  },
  {
    name: '取不到契约时明说没跑（跳过 ≠ 通过），且不假装失败',
    check: () => {
      const out = runHook({ AIDRUN_BACKEND_DIR: path.join(tmp, 'nope') });
      const skipped = out.split('\n').filter((l) => l.includes('这不算通过。')).length;
      if (skipped !== 4) return `期望 4 条「这不算通过」，实得 ${skipped}：\n${out}`;
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
