#!/usr/bin/env node
//
// scripts/hooks/post-checkout-localconfig.sh 的回归测试：在临时仓库里跑**真的** install-git-hooks.sh
// 和**真的** `git worktree add`，看 LocalConfig.xcconfig 有没有被带过去。
//
// 为什么要真跑 git：这个钩子唯一的价值是「新 worktree 自动有这个文件」，而它坏掉的样子是
// 什么都不发生 —— 下一个会话照样编译不过，还是得让用户手动 cp。只测脚本里的字符串抓不到
// 「git 在 worktree add 时根本没跑 post-checkout」或「安装脚本没装它」这两种坏法。

import { execFileSync } from 'node:child_process';
import { chmodSync, existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const installer = join(repoRoot, 'scripts/install-git-hooks.sh');

// 在 git 钩子里被调用时（pre-push）会继承 GIT_DIR 等变量，指向本仓库 —— 必须清掉，
// 否则下面每条 git 命令都会打到本仓库上。
const env = { ...process.env };
for (const key of Object.keys(env)) {
  if (key.startsWith('GIT_')) delete env[key];
}
Object.assign(env, {
  GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t',
});

const sh = (cwd, cmd, args) => execFileSync(cmd, args, { cwd, env, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });

function makeRepo({ withConfig }) {
  const base = mkdtempSync(join(tmpdir(), 'aidrun-localconfig-'));
  const main = join(base, 'main');
  execFileSync('mkdir', ['-p', main]);
  sh(main, 'git', ['init', '-q', '-b', 'main']);
  writeFileSync(join(main, '.gitignore'), 'LocalConfig.xcconfig\n');
  sh(main, 'git', ['add', '.gitignore']);
  sh(main, 'git', ['commit', '-q', '-m', 'init']);
  if (withConfig) writeFileSync(join(main, 'LocalConfig.xcconfig'), 'AMAP_API_KEY = from-main\n');
  // 被测的安装脚本引用 scripts/hooks/ 下的钩子本体，按仓库里的相对位置放一份。
  execFileSync('mkdir', ['-p', join(main, 'scripts/hooks')]);
  writeFileSync(join(main, 'scripts/install-git-hooks.sh'), readFileSync(installer));
  writeFileSync(
    join(main, 'scripts/hooks/post-checkout-localconfig.sh'),
    readFileSync(join(repoRoot, 'scripts/hooks/post-checkout-localconfig.sh')),
  );
  chmodSync(join(main, 'scripts/install-git-hooks.sh'), 0o755);
  sh(main, 'bash', ['scripts/install-git-hooks.sh']);
  return { base, main };
}

const cases = [
  {
    name: '主 worktree 有 LocalConfig → worktree add 之后新副本里有同样内容',
    run() {
      const { base, main } = makeRepo({ withConfig: true });
      const wt = join(base, 'wt');
      sh(main, 'git', ['worktree', 'add', '-q', '-b', 'feature', wt]);
      const copied = join(wt, 'LocalConfig.xcconfig');
      if (!existsSync(copied)) return { base, error: '新 worktree 里没有 LocalConfig.xcconfig —— 钩子没装上，或 git 没在 worktree add 时跑它' };
      const content = readFileSync(copied, 'utf8');
      return { base, error: content === 'AMAP_API_KEY = from-main\n' ? null : `内容不对：${JSON.stringify(content)}` };
    },
  },
  {
    name: 'worktree 里已有自己的 LocalConfig → 之后的 checkout 不覆盖它',
    run() {
      const { base, main } = makeRepo({ withConfig: true });
      const wt = join(base, 'wt');
      sh(main, 'git', ['worktree', 'add', '-q', '-b', 'feature', wt]);
      writeFileSync(join(wt, 'LocalConfig.xcconfig'), 'AMAP_API_KEY = my-own\n');
      sh(wt, 'git', ['checkout', '-q', '-b', 'another']);
      const content = readFileSync(join(wt, 'LocalConfig.xcconfig'), 'utf8');
      return { base, error: content === 'AMAP_API_KEY = my-own\n' ? null : `被覆盖成了 ${JSON.stringify(content)}` };
    },
  },
  {
    name: '主 worktree 也没有 LocalConfig → worktree add 照常成功，不凭空造文件',
    run() {
      const { base, main } = makeRepo({ withConfig: false });
      const wt = join(base, 'wt');
      try {
        sh(main, 'git', ['worktree', 'add', '-q', '-b', 'feature', wt]);
      } catch (e) {
        return { base, error: `钩子让 worktree add 失败了：${e.stderr || e.message}` };
      }
      return { base, error: existsSync(join(wt, 'LocalConfig.xcconfig')) ? '凭空造出了 LocalConfig.xcconfig' : null };
    },
  },
];

let failed = 0;
for (const c of cases) {
  let result;
  try {
    result = c.run();
  } catch (e) {
    result = { error: `抛异常：${e.stderr || e.message}` };
  }
  if (result.base) rmSync(result.base, { recursive: true, force: true });
  if (result.error) {
    failed += 1;
    console.log(`✗ ${c.name}\n    ${result.error}`);
  } else {
    console.log(`✓ ${c.name}`);
  }
}
console.log(`[validate-worktree-localconfig] ${cases.length - failed}/${cases.length} 通过`);
process.exit(failed ? 1 : 0);
