#!/usr/bin/env node
// 守卫：shell 脚本里 `$VAR` 后不许紧跟非 ASCII 字符（全角括号 / 冒号 / 逗号等），必须写 `${VAR}`。
//
// 为什么（#263）：macOS 自带 bash 3.2 在 UTF-8 locale 下，会把变量名后那个汉字/全角标点的首字节
// 并进变量名，`"（rc=$rc）"` 变成读一个叫 `rc<半个字>` 的变量，`set -u` 下直接 unbound variable。
// C locale 不触发，所以 LANG 未设时一直绿、一设 UTF-8（比如为跑 pod install）pre-push 就挂。
// 更糟的是它常出现在失败分支的报错文案里：本该打印真正的失败原因，结果崩成 unbound variable。
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';

export const BAD = /\$[A-Za-z_][A-Za-z0-9_]*(?=[^\x00-\x7f])/;

// 自测：门本身能红、也不误报。
if (!BAD.test('echo "（rc=$rc）"') || !BAD.test('echo "$label：x"')) {
  console.error('[validate-shell-varnames] 自测失败：应命中的写法没命中');
  process.exit(1);
}
if (BAD.test('echo "（rc=${rc}）"') || BAD.test('echo "$label: x"') || BAD.test('echo "$1）"')) {
  console.error('[validate-shell-varnames] 自测失败：不该命中的写法命中了');
  process.exit(1);
}

const files = execFileSync('git', ['ls-files', '*.sh', '*.bash'], { encoding: 'utf8' })
  .split('\n')
  .filter(Boolean);

let failed = 0;
for (const file of files) {
  fs.readFileSync(file, 'utf8').split('\n').forEach((line, i) => {
    if (BAD.test(line)) {
      console.error(`[validate-shell-varnames] ${file}:${i + 1}: ${line.trim().slice(0, 100)}`);
      failed += 1;
    }
  });
}

if (failed > 0) {
  console.error(`[validate-shell-varnames] ${failed} 处：把 $VAR 改成 \${VAR}`);
  process.exit(1);
}
console.log(`[validate-shell-varnames] ${files.length} 个脚本，无 $VAR 紧跟非 ASCII 字符`);
