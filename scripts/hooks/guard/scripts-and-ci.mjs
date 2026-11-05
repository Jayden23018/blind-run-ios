// pre 段 · 脚本、CI 与签名：workflow 的 if: 里读 secrets、真机 xcodebuild 没传团队号、文档里写死团队号。
// 每个函数命中即 `fail()` 退出 2；没命中就返回。调用顺序由 `guard.mjs` 决定。

import { fail, nonCommentLines } from './common.mjs';

export function checkSecretsInIf({ filePath, body }) {
  // 7. workflow 的 if: 里出现 secrets（2026-08-06）
  //
  // `secrets` 不在 `if:` 的可用上下文里 —— 官方 context availability 表：
  //   jobs.<job_id>.if        → github, needs, vars, inputs
  //   jobs.<job_id>.steps.if  → github, needs, strategy, matrix, job, runner, env, vars, steps, inputs
  // 两处都没有 secrets。写了不是「这一步失败」，是**整个 workflow 启动失败**：
  // 0 个 job、0 条日志，Actions 页面点进去什么都没有，只有一封 run failed 邮件。
  // verify.yml 因此连续 9 次 run 全红，而红的原因在 UI 上根本看不见。
  //
  // 改法：job 级 `env` 是允许 secrets 的，转一道再在 `if` 里读 env：
  //   env:
  //     HAS_TOKEN: ${{ secrets.FOO != '' }}
  //   steps:
  //     - if: env.HAS_TOKEN == 'true'
  //
  // 只查新内容不查 old_string：把坏的 if 删掉是我们想要的方向。
  const isWorkflow = /\.github\/workflows\/[^/]+\.ya?ml$/.test(filePath);
  const secretsIfLine = isWorkflow
    ? body
        .split('\n')
        .find((l) => /^\s*-?\s*if:\s.*\bsecrets\./.test(l) && !l.includes('guard:allow secrets-in-if'))
    : undefined;
  if (secretsIfLine) {
    fail(
      'secrets-in-if',
      `${filePath}\n  ${secretsIfLine.trim()}\n\n` +
        `\`secrets\` 在 job 级和 step 级的 \`if:\` 里都不可用，GitHub 解析到就报 Unrecognized named-value，\n` +
        `**整个 workflow 不启动** —— 0 个 job、0 条日志，只有一封 run failed 邮件，红在哪根本看不见。\n` +
        `改法：job 级 env 允许 secrets，转一道再在 if 里读 env：\n` +
        `  env:\n    HAS_TOKEN: \${{ secrets.FOO != '' }}\n  steps:\n    - if: env.HAS_TOKEN == 'true'`
    );
  }
}

export function checkMissingTeam({ filePath, body }) {
  // 7. 脚本里调 xcodebuild 真机动作却没传 DEVELOPMENT_TEAM（2026-08-07）
  //
  // 2026-10-03 前 pbxproj 写死的是原开发者的团队号 R6PH2TFB3Q，当时每条打真机的 xcodebuild 都得在命令行覆盖；
  // #302 改为 QW8R457UHN，2026-10-20 换成公司组织账号 8LG486RF64，本规则保留作为「显式传团队号」的约定。**只当环境变量前缀不生效** ——
  // `DEVELOPMENT_TEAM=… xcodebuild …` 会被静默忽略，报的是
  // `No Account for Team "R6PH2TFB3Q"` + `No profiles for 'com.jerry.aidrun' were found`，
  // 两条都不提团队号是从哪来的，很容易被当成证书或 provisioning 问题去查。
  //
  // 落这条的直接原因：`dual-device-validation.sh` 与 `device-test-safety.sh` 里
  // 6+1 处 xcodebuild 一处都没传，等于这两个脚本在任何非原开发者的机器上都必然失败，
  // 而它们是发布验证的入口。同一天我自己也用环境变量前缀撞了一次。
  //
  // 只查真机动作：`-destination 'generic/platform=iOS'` 那种编译门禁走
  // CODE_SIGNING_ALLOWED=NO，不需要团队号，拦它是误报。
  const isShellScript = /\.(sh|bash)$/.test(filePath) || /^#!.*\b(bash|sh)\b/.test(body);
  let missingTeamCmd;
  if (isShellScript && /xcodebuild/.test(body)) {
    // xcodebuild 的调用是多行续行的，按 `\` 折行重新粘成一条命令再判。
    // 先粘再滤注释：脚本顶部的用法说明里常常原样贴着这条命令，注释掉的命令不会执行。
    const commands = nonCommentLines(body.replace(/\\\n\s*/g, ' '));
    missingTeamCmd = commands.find(
      (l) =>
        /\bxcodebuild\b/.test(l) &&
        /-destination\s+["']?platform=iOS,\s*(name|id)=/.test(l) &&
        !/DEVELOPMENT_TEAM=/.test(l) &&
        !/CODE_SIGNING_ALLOWED=NO/.test(l) &&
        !l.includes('guard:allow missing-team')
    );
  }
  if (missingTeamCmd) {
    fail(
      'missing-team',
      `${filePath}\n  ${missingTeamCmd.trim().slice(0, 160)}\n\n` +
        `这条 xcodebuild 打的是真机（-destination platform=iOS,name=/id=）却没传 DEVELOPMENT_TEAM。\n` +
        `约定每条真机 xcodebuild 都显式传团队号（pbxproj 里是 8LG486RF64，可被覆盖）。\n` +
        `**环境变量前缀不生效**，必须作为构建设置参数传：\n` +
        `  TEAM="\${AIDRUN_TEAM:-8LG486RF64}"\n` +
        `  xcodebuild … -allowProvisioningUpdates DEVELOPMENT_TEAM="\$TEAM"\n` +
        `照抄 scripts/device-test.sh:25,60。不传的报错是 \`No Account for Team "R6PH2TFB3Q"\`，\n` +
        `字面上不提团队号从哪来，容易被误当成证书或 provisioning 问题查半天。\n` +
        `确实不需要签名（编译门禁），用 CODE_SIGNING_ALLOWED=NO，或行尾加 \`guard:allow missing-team\`。`
    );
  }
}

export function checkHardcodedTeamId({ filePath, body }) {
  const isDocument = /\.md$/i.test(filePath);
  // 7.5 Markdown 里教人传写死的团队号（2026-10-15，#441）
  //
  // 上一条规则要求**脚本**显式传团队号，结果文档也跟着把号抄了进去：项目 CLAUDE.md 写过
  // 「命令行要传 `DEVELOPMENT_TEAM=<某个号>`」。团队号随人、随机器变（2026-10-03 一天换过团队，
  // 工程团队又是个人类型账号、成员签不了），2026-10-15 三个并行会话照抄全部报
  // `No Account for Team`，而常驻的 CLAUDE.md 优先被照做，压过了 skill `aidrun-device-test`
  // 「不写死任何 id」的说法。第二次以上的同类错误，按 AGENTS.md §1 落成守卫。
  //
  // 只管 `.md` 里「NAME=<10 位团队号>」这种可原样粘贴的命令行写法，两个变量名都查：
  // `DEVELOPMENT_TEAM`（xcodebuild 构建设置）与 `AIDRUN_TEAM`（device-test.sh 的覆盖变量）。
  // 不拦：脚本里的默认值 `${AIDRUN_TEAM:-…}`（脚本得有默认）、pbxproj 里的 `DEVELOPMENT_TEAM = X;`
  // （带空格、不是命令行）、报错原文里的 `No Account for Team "X"`、`<团队号>` 之类占位符。
  // 只看本次写入的内容，所以历史文档里已有的号不会让无关编辑被拦。
  const TEAM_ID_ARG = /\b(?:DEVELOPMENT_TEAM|AIDRUN_TEAM)=["']?[A-Z0-9]{10}\b/;
  const hardcodedTeamLine = isDocument
    ? body
        .split('\n')
        .find((l) => TEAM_ID_ARG.test(l) && !l.includes('guard:allow hardcoded-team-id'))
    : undefined;
  if (hardcodedTeamLine) {
    fail(
      'hardcoded-team-id',
      `${filePath}\n  ${hardcodedTeamLine.trim().slice(0, 160)}\n\n` +
        `文档里不要写 \`DEVELOPMENT_TEAM=<具体团队号>\` / \`AIDRUN_TEAM=<具体团队号>\`：团队号随人、随机器变，\n` +
        `被照抄的下场是 \`No Account for Team\`（2026-10-15 三个会话同时中招，#441）。\n` +
        `改成指向 skill \`aidrun-device-test\`（第二节有当场查团队的命令），或写占位符 \`<你的团队号>\`。\n` +
        `确实是在引用一段历史原文，行尾加 \`guard:allow hardcoded-team-id\`。`
    );
  }
}
