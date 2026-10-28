#!/usr/bin/env node
//
// scripts/hooks/run.mjs（钩子转发器，#483）的回归测试：在临时仓库里真建一个 worktree，
// 从「主 checkout」那份转发器启动钩子，看实际跑的是哪一份、输入输出和退出码有没有透传。
//
// 为什么要真跑 git：转发器坏掉的样子是「照样跑主 checkout 那份旧钩子」—— 什么都不报错，
// 只是 main 上对钩子的修复又一次到不了 worktree 会话。只测字符串抓不到这种坏法。
// 最后一组检查 `.claude/settings.json`：新加的钩子绕开转发器直接写 `$CLAUDE_PROJECT_DIR/…`，
// 同一个问题会原样回来。

import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const launcherSource = readFileSync(join(repoRoot, 'scripts/hooks/run.mjs'));

// 在 git 钩子里被调用时（pre-push）会继承 GIT_DIR 等变量，指向本仓库 —— 必须清掉。
const env = { ...process.env };
for (const key of Object.keys(env)) {
  if (key.startsWith('GIT_')) delete env[key];
}
delete env.CLAUDE_PROJECT_DIR;
Object.assign(env, {
  GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t',
});

const sh = (cwd, args) => execFileSync('git', args, { cwd, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });

// 探针钩子：报告自己是哪一份、在哪个目录跑、看到的 CLAUDE_PROJECT_DIR、收到的输入和参数；退出码 2。
const probe = (who) => `
import fs from 'node:fs';
const input = fs.readFileSync(0, 'utf8');
process.stdout.write(JSON.stringify({
  who: ${JSON.stringify(who)}, cwd: process.cwd(), projectDir: process.env.CLAUDE_PROJECT_DIR,
  input, args: process.argv.slice(2),
}));
process.exit(2);
`;

function makeRepo(base, name, who) {
  const root = join(base, name);
  mkdirSync(join(root, 'scripts/hooks'), { recursive: true });
  sh(root, ['init', '-q', '-b', 'main']);
  writeFileSync(join(root, 'scripts/hooks/run.mjs'), launcherSource);
  writeFileSync(join(root, 'scripts/hooks/probe.mjs'), probe(who));
  sh(root, ['add', '.']);
  sh(root, ['commit', '-q', '-m', 'init']);
  return root;
}

function launch(mainRoot, hook, input) {
  const r = spawnSync(process.execPath, [join(mainRoot, 'scripts/hooks/run.mjs'), hook, 'arg-1'], {
    input, env, encoding: 'utf8',
  });
  let out = null;
  try {
    out = JSON.parse(r.stdout);
  } catch {
    // 留给断言报错
  }
  return { status: r.status, out, stdout: r.stdout, stderr: r.stderr };
}

const base = mkdtempSync(join(tmpdir(), 'aidrun-hook-launcher-'));
const main = makeRepo(base, 'main', 'main');
const wt = join(base, 'wt');
sh(main, ['worktree', 'add', '-q', '--detach', wt]);
writeFileSync(join(wt, 'scripts/hooks/probe.mjs'), probe('worktree'));
const other = makeRepo(base, 'other', 'other');
const real = (p) => realpathSync(p);

const cases = [
  {
    name: 'cwd 在本仓库的另一个 worktree → 跑 worktree 那份，目录与 CLAUDE_PROJECT_DIR 都是它的根',
    run() {
      const input = JSON.stringify({ cwd: join(wt, 'scripts'), marker: 'm1' });
      const r = launch(main, 'probe', input);
      if (!r.out) return `输出不是 JSON：${r.stdout}${r.stderr}`;
      if (r.out.who !== 'worktree') return `跑的是 ${r.out.who} 那份`;
      if (real(r.out.cwd) !== real(wt)) return `工作目录是 ${r.out.cwd}`;
      if (real(r.out.projectDir) !== real(wt)) return `CLAUDE_PROJECT_DIR 是 ${r.out.projectDir}`;
      if (r.out.input !== input) return '钩子收到的输入被改了';
      if (r.out.args.join(',') !== 'arg-1') return `参数没透传：${r.out.args}`;
      if (r.status !== 2) return `退出码 2 没透传，得到 ${r.status}`;
      return null;
    },
  },
  {
    name: 'cwd 在别的仓库（例如后端）→ 跑自己这份，不跑别的仓库里的同名脚本',
    run() {
      const r = launch(main, 'probe', JSON.stringify({ cwd: other }));
      return r.out?.who === 'main' ? null : `跑的是 ${r.out?.who ?? r.stdout + r.stderr}`;
    },
  },
  {
    name: 'cwd 不存在或输入不是 JSON → 跑自己这份',
    run() {
      const missing = launch(main, 'probe', JSON.stringify({ cwd: join(base, 'gone') }));
      if (missing.out?.who !== 'main') return `cwd 不存在时跑的是 ${missing.out?.who}`;
      const garbage = launch(main, 'probe', 'not json');
      return garbage.out?.who === 'main' ? null : `输入不是 JSON 时跑的是 ${garbage.out?.who}`;
    },
  },
  {
    name: 'worktree 里没有这个钩子 → 跑自己这份',
    run() {
      writeFileSync(join(main, 'scripts/hooks/only-main.mjs'), probe('main-only'));
      const r = launch(main, 'only-main', JSON.stringify({ cwd: wt }));
      return r.out?.who === 'main-only' ? null : `跑的是 ${r.out?.who ?? r.stdout + r.stderr}`;
    },
  },
  {
    name: '钩子名带路径 → 退出 1（非阻断），不执行任何脚本',
    run() {
      const r = launch(main, '../probe', JSON.stringify({ cwd: wt }));
      return r.status === 1 && !r.out ? null : `退出码 ${r.status}，输出 ${r.stdout}`;
    },
  },
  {
    name: '.claude/settings.json 的每个钩子都经转发器启动，且钩子文件存在',
    run() {
      const settings = JSON.parse(readFileSync(join(repoRoot, '.claude/settings.json'), 'utf8'));
      const LAUNCHED = /^node "\$CLAUDE_PROJECT_DIR\/scripts\/hooks\/run\.mjs" ([a-z][a-z0-9-]*)(?: |$)/;
      const problems = [];
      for (const [event, groups] of Object.entries(settings.hooks ?? {})) {
        for (const group of groups) {
          for (const hook of group.hooks ?? []) {
            const m = LAUNCHED.exec(hook.command ?? '');
            if (!m) problems.push(`${event}: ${hook.command}`);
            else if (!existsSync(join(repoRoot, 'scripts/hooks', `${m[1]}.mjs`))) problems.push(`${event}: 没有 scripts/hooks/${m[1]}.mjs`);
          }
        }
      }
      return problems.length ? `没经转发器或钩子不存在：\n    ${problems.join('\n    ')}` : null;
    },
  },
];

let failed = 0;
try {
  for (const c of cases) {
    const error = c.run();
    if (error) {
      failed += 1;
      console.error(`✗ ${c.name}\n  ${error}`);
    } else {
      console.log(`✓ ${c.name}`);
    }
  }
} finally {
  rmSync(base, { recursive: true, force: true });
}

if (failed) {
  console.error(`\n[validate-hook-launcher] ${failed}/${cases.length} 条失败`);
  process.exit(1);
}
console.log(`\n[validate-hook-launcher] ${cases.length}/${cases.length} 条通过`);
