#!/usr/bin/env node

// AidRun 项目守卫 —— 把 AGENTS.md 里代价最高的几条红线从「散文约束」变成「机器强制」。
//
// 存在理由：这些规则全部写在 AGENTS.md 里很久了，但每一条都至少被违反过一次。
// 文档是建议，hook 每次都执行。
//
// 用法（由 .claude/settings.json 调用）：
//   node scripts/hooks/guard.mjs pre    # PreToolUse：阻断
//   node scripts/hooks/guard.mjs post   # PostToolUse：写完再查，Claude 收到后会自己改回来
//
// 退出码 2 = 拦下并把 stderr 反馈给 Claude；0 = 放行。
// 任何内部异常一律放行（守卫本身不该成为阻塞源），但会在 stderr 留痕。
//
// 抑制：在触发行尾加 `// guard:allow <rule-id>`。
// 刻意做成需要显式标注 —— 白名单文件会腐烂，行内标注跟着代码走。

import fs from 'node:fs';
import path from 'node:path';

const MODE = process.argv[2] === 'pre' ? 'pre' : 'post';
const REAL_HOST = '47.114.113.171';

// RFC 2606 保留域名，永远不可能是真实服务端，不必标注
const DOC_DOMAINS = /^https?:\/\/(www\.)?example\.(com|org|net)/;

const rules = {
  'legacy-status': {
    // AGENTS.md 第 5 节：禁用的遗留订单词汇
    pattern: /"(submitted|contacted|expired|matching|accepted|arrived|emergency)"/,
    why: '订单状态只能用 PENDING_MATCH / PENDING_ACCEPT / IN_PROGRESS / DRIVER_EN_ROUTE / DRIVER_ARRIVED / COMPLETED / CANCELLED / REMATCHING / NO_VOLUNTEER（AGENTS.md 第 5 节）。若这里不是订单状态（例如诊断事件名），行尾加 `// guard:allow legacy-status`。',
  },
  'sos-copy': {
    // AGENTS.md 第 6 节：短信是事务提交后异步发的，失败从不回告盲人。
    // App 说「已送达」就是在对一个看不见屏幕的人撒谎。
    //
    // 2026-08-13 补「家人」：行程告知功能通篇用的是「家人」这个词，而原词表只有
    // 「联系人 / 家属 / 亲属」，于是「已通知家人」整条绕过了这道守卫。同一类缺陷换个称呼
    // 就能穿过去，说明词表本身是这条规则的薄弱面 —— 再新增称呼时一并加进来。
    //
    // 这里同时覆盖第二条来源相同的红线：`MFMessageComposeViewController` 的 `.sent`
    // 只代表用户点了发送，**不保证送达**，用户还能改收件人和正文。所以行程告知那条路径
    // 与 SOS 一样，只能说「已交给系统短信」，不能说「已通知」。
    pattern: /联系人已收到短信|已(成功)?(发送|送达|通知|联系)(给)?(您的)?(紧急)?(联系人|家属|亲属|家人)|(联系人|家属|亲属|家人)已(收到|被通知|知晓)/,
    why: 'App 永远不得宣称短信已发出/已送达/家属已被通知（AGENTS.md 第 6 节）。SOS 短信在事务提交后才异步发送，失败只播给客服、从不回告盲人；行程告知走系统 composer，`.sent` 同样不保证送达。两条路径都必须用进行时文案（例如「短信已交给系统，请在短信里确认已发出」）。',
  },
  'server-addr': {
    pattern: /https?:\/\/[a-zA-Z0-9.\-_:]+/,
    check: (line) => {
      const urls = line.match(/https?:\/\/[a-zA-Z0-9.\-_:]+/g) || [];
      return urls.some((u) => !u.includes(REAL_HOST) && !DOC_DOMAINS.test(u));
    },
    why: `所有真实 HTTP 必须走 http://${REAL_HOST}，地址在 App 内不可配置，不得加入本地或占位的真实服务端地址（AGENTS.md 第 3 节）。`,
  },
};

// Podfile 保持整文件冻结：架构排除设置与 pod 列表都在里面，没有安全的局部改法。
const FROZEN = [/(^|\/)Podfile$/];

// project.pbxproj 自 2026-08-05 起改为行级冻结，不再整文件拦。
//
// 核对过 AGENTS.md 第 9 节列的两条理由，只有一条真的落在 pbxproj 里：
//   · DEVELOPMENT_TEAM = R6PH2TFB3Q（12 处，原开发者的团队号）—— 成立
//   · 架构排除设置 —— 在 pbxproj 里出现 0 次，它只存在于 Podfile:36
//
// 整文件冻结的代价是连加一个 SPM 依赖都做不到，而「临时解锁、改完加回来」
// 依赖人记得加回来 —— 第 1 节说的就是这种挡不住重复犯错的做法。
// 行级冻结让保护变成永久的：文件可以改，碰到签名团队号就拦。
// 架构排除设置不必在这里重复挡，下面那条内容级规则对所有文件都生效。
const PBXPROJ = /project\.pbxproj$/;
const PBXPROJ_FROZEN_KEY = /DEVELOPMENT_TEAM/;

// 键名拼出来而不是写成字面量 —— 见下面用到它的地方的说明。
const ARCH_EXCLUSION_KEY = new RegExp(['EXCLUDED', 'ARCHS'].join('_'));

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

function fail(ruleId, detail) {
  process.stderr.write(`[guard:${ruleId}] ${detail}\n`);
  process.exit(2);
}

function scanSwift(filePath) {
  let src;
  try {
    src = fs.readFileSync(filePath, 'utf8');
  } catch {
    return; // 文件可能已被删除或改名，不是守卫该管的事
  }

  const lines = src.split('\n');
  for (const [id, rule] of Object.entries(rules)) {
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      // 纯注释行跳过：守卫管的是出货代码。引用后端的坏文案来解释「为什么要覆盖它」
      // 恰恰是我们希望留在代码里的东西，不该被拦。
      if (/^\s*(\/\/|\*|\/\*)/.test(line)) continue;
      // 标注可以写在同一行，也可以写在紧邻的上一行 —— Swift 经常把长字符串折到
      // 声明的下一行，强制同行标注会把标注挤成噪声。
      const marker = `guard:allow ${id}`;
      if (line.includes(marker) || (i > 0 && lines[i - 1].includes(marker))) continue;
      if (!rule.pattern.test(line)) continue;
      if (rule.check && !rule.check(line)) continue;
      fail(id, `${filePath}:${i + 1}\n  ${line.trim()}\n\n${rule.why}`);
    }
  }
}

function main() {
  const raw = readStdin();
  if (!raw.trim()) process.exit(0);

  let payload;
  try {
    payload = JSON.parse(raw);
  } catch {
    process.exit(0);
  }

  const tool = payload.tool_name || '';
  const input = payload.tool_input || {};
  const filePath = input.file_path || '';

  if (MODE === 'pre') {
    // 1. 禁读已知有错的归档契约副本（AGENTS.md 第 2 节）
    if (tool === 'Read' && /docs\/_archive-.*\.bak$/.test(filePath)) {
      fail(
        'archived-contract',
        `${filePath}\n\n这是已归档的旧 API 契约副本，含已知错误，不得读取或复制（AGENTS.md 第 2 节）。` +
          `\n契约唯一源是后端仓库 /Users/mac/Downloads/demo 的 docs/api_spec.yaml 与 docs/websocket-protocol.md。`
      );
    }

    if (tool !== 'Edit' && tool !== 'Write') process.exit(0);

    // 2. 冻结文件（AGENTS.md 第 9 节）
    if (FROZEN.some((re) => re.test(filePath))) {
      fail(
        'frozen-files',
        `${filePath}\n\n该文件是冻结的（AGENTS.md 第 9 节）。真机是唯一 XCTest 通道，` +
          `模拟器因高德无 arm64-sim slice 永久不可用；架构排除设置与 pod 列表都在这里，没有安全的局部改法。`
      );
    }

    const body = input.content || input.new_string || '';

    // 工程文件是行级冻结：允许加 SPM 依赖之类的段落，但签名团队号一个字都不许碰。
    // old_string 也要查 —— 只看新内容会漏掉「把那 12 行删掉」这种改法。
    if (PBXPROJ.test(filePath) && (PBXPROJ_FROZEN_KEY.test(body) || PBXPROJ_FROZEN_KEY.test(input.old_string || ''))) {
      fail(
        'frozen-files',
        `${filePath}\n\n工程文件本身可以改，但这次改动碰到了 DEVELOPMENT_TEAM（AGENTS.md 第 9 节）。\n` +
          `写死的 R6PH2TFB3Q 是原开发者的团队号。用命令行传 DEVELOPMENT_TEAM=ZW39BS8NXT 覆盖，不要改工程文件。`
      );
    }

    // 架构排除设置：任何构建相关文件都不许写，它是「模拟器永久不可用」这个事实的载体。
    //
    // 两个豁免，都是被这条规则绊过之后加的（2026-08-06）：
    //   · Markdown —— 文档必须能写出它保护的那个键的名字，否则 AGENTS.md 第 9 节
    //     自己就改不动了。md 文件设不了构建设置，放行零风险。
    //   · 行尾 `guard:allow excluded-archs` —— 给需要在代码或注释里提及它的地方留口，
    //     与 rules 里那几条内容规则的标注方式一致。
    //
    // 键名拆开拼：这条规则会拦住任何含该键名的改动，**包括对本文件的改动**。
    // 写成字面量的话，以后谁想再调这条规则都得先绕过它自己。
    const isDocument = /\.md$/i.test(filePath);
    const offendingArchLine = isDocument
      ? undefined
      : body
          .split('\n')
          .find((l) => ARCH_EXCLUSION_KEY.test(l) && !l.includes('guard:allow excluded-archs'));
    if (offendingArchLine) {
      fail(
        'frozen-files',
        `${filePath}\n  ${offendingArchLine.trim()}\n\n` +
          `不要动架构排除设置（AGENTS.md 第 9 节）。确需在此提及，行尾加 \`guard:allow excluded-archs\`。`
      );
    }

    // 3. 高德 key 硬编码（AGENTS.md 第 8 节）
    const keyLine = body
      .split('\n')
      .find(
        (l) =>
          /(amap|gaode|高德|apiKey|api_key|appKey)/i.test(l) &&
          /["'][0-9a-f]{32}["']/i.test(l) &&
          !l.includes('guard:allow amap-key')
      );
    if (keyLine) {
      fail(
        'amap-key',
        `${filePath}\n  ${keyLine.trim()}\n\n高德 key 只能来自本地配置文件（LocalConfig.xcconfig），` +
          `不得硬编码、不得提交真实 key（AGENTS.md 第 8 节）。`
      );
    }

    // 4. OpenAPI 运行时不得进 App target（2026-08-06）
    //
    // 主工程设了 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor，而 OpenAPI 那套类型假设
    // Swift 默认的 nonisolated。两者相撞时自动合成的一致性会带上 MainActor 隔离，
    // 满足不了 Sendable 约束。这一类冲突已经发作两次：
    //   · APIClient.swift 的泛型约束只能写 Decodable 不能写 Decodable & Sendable（见其注释）
    //   · 生成代码的 submitVerification multipart body 编译不过
    // 第二次之后把生成代码整个搬进了 Packages/AidRunAPI（用 SPM 默认隔离）。
    // 这条守卫防的是有人把它又拽回 App target 里，然后对着费解的报错查半天。
    const inAppTarget = /\/blindRun(Tests|UITests)?\//.test(filePath) && /\.swift$/.test(filePath);
    const openAPIImport = inAppTarget
      ? body
          .split('\n')
          .find((l) => /^\s*import\s+(OpenAPIRuntime|OpenAPIURLSession|HTTPTypes)\b/.test(l))
      : undefined;
    if (openAPIImport) {
      fail(
        'openapi-in-app-target',
        `${filePath}\n  ${openAPIImport.trim()}\n\n` +
          `OpenAPI 运行时不要进 App target —— 主工程的 MainActor 默认隔离会和它打架（这一类冲突已发作两次）。\n` +
          `面向 OpenAPI 的代码放 Packages/AidRunAPI/，App 侧只 import AidRunAPI。\n` +
          `装配客户端用 makeAidRunAPIClient(serverURL:tokenProvider:)。原因见该包 Package.swift 顶部。`
      );
    }

    // 5. 把临时对象传给 weak 依赖（2026-08-06）
    //
    // View model 的依赖清一色是 `weak var`（避免和 View 持有的对象循环引用）。
    // 传一个当场构造的临时对象进去，出了这一行就没人持有它 —— 属性立刻变 nil，
    // 而测试照样绿：它只是没在测你以为在测的那件事。
    // `BlindBookingGateTests.testEntryAnnouncementCoversOnlyGatesFixedElsewhere` 就这么
    // 「过」了很久，把它 `let` 住之后才发现那条断言从来没碰过 LocationService。
    //
    // 名单是「本仓库里所有以该名字存储的属性都是 weak」的那些标签（核对于 2026-08-06）：
    //   appState / locationService / placeSearchProvider / speechInputService / bookingViewModel
    // `speechService` **不在**名单里：它在 VoiceOrderWizard.swift:104 是 weak，
    // 在十几个 view model 里却是强引用的 `SpeechService?`，按标签名拦会全是误报。
    const WEAK_DEP_LABELS = /\b(appState|locationService|placeSearchProvider|speechInputService|bookingViewModel):\s*(?:[\w.]+\s*\?\?\s*)?[A-Z]\w*\(/;
    const weakTempLine = /\.swift$/.test(filePath)
      ? body.split('\n').find((l) => WEAK_DEP_LABELS.test(l) && !l.includes('guard:allow weak-temporary'))
      : undefined;
    if (weakTempLine) {
      fail(
        'weak-temporary',
        `${filePath}\n  ${weakTempLine.trim()}\n\n` +
          `这些依赖在 view model 里是 \`weak var\`（例：BlindBookingView.swift:182-184、VoiceOrderWizard.swift:103-105）。\n` +
          `传当场构造的临时对象 = 传 nil：对象在这一行结束就释放，属性变 nil，断言看着绿其实什么都没测。\n` +
          `改法：先 \`let x = ...\` 在测试方法作用域里持有它再传（helper 函数里的局部变量同样会释放，要么让调用方持有，要么显式传 nil）。\n` +
          `确实就是想传 nil 语义，行尾加 \`// guard:allow weak-temporary\`。`
      );
    }

    // 6. UI 测试里敲屏幕正中（2026-08-08）
    //
    // `app.tap()` 点的是屏幕几何中心。盲人端主按钮的设计目标就是**占满内容区**
    // （对标 Be My Eyes，见 docs/research/blind-ui-visual-benchmark-20260808.md §1），
    // 所以屏幕正中永远压着一个会导航走的按钮。
    //
    // 发作形态特别有欺骗性：用例一启动就被自己点进了下单页，随后每条断言都报
    // 「找不到 blindRunnerHomeStartBookingButton」，看起来像**首页没起来**，
    // 于是会去查启动 gate、mock 数据、签名 —— 全是错方向。
    // 首页主按钮从 64pt 放大到 280pt 那次，5 条用例同时红，跑了 3 轮真机才定位到这一行。
    //
    // 正解是敲一个明确不吃点击的区域，首页顶部地图层就是（`allowsHitTesting(false)`）。
    const isUITest = /blindRunUITests\/.*\.swift$/.test(filePath);
    const tapCenterLine = isUITest
      ? body.split('\n').find((l) => /\bapp\.tap\(\)/.test(l) && !l.includes('guard:allow blind-tap-center'))
      : undefined;
    if (tapCenterLine) {
      fail(
        'blind-tap-center',
        `${filePath}\n  ${tapCenterLine.trim()}\n\n` +
          `\`app.tap()\` 敲的是屏幕正中，而盲人端主按钮的设计目标就是占满那里 —— 一敲就导航走。\n` +
          `症状会伪装成「页面没起来」：后续断言全报找不到元素，实际是用例自己点进了别的页。\n` +
          `改法：敲一个明确无动作的区域，例如顶部地图层（allowsHitTesting(false)）：\n` +
          `  app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()\n` +
          `确实就是要点正中，行尾加 \`// guard:allow blind-tap-center\`。`
      );
    }

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

    // 7. 脚本里调 xcodebuild 真机动作却没传 DEVELOPMENT_TEAM（2026-08-07）
    //
    // pbxproj 里写死的 R6PH2TFB3Q 是原开发者的团队号（第 9 节行级冻结，不许改工程文件），
    // 所以每条打真机的 xcodebuild 都得在命令行覆盖。**只当环境变量前缀不生效** ——
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
      const commands = body.replace(/\\\n\s*/g, ' ').split('\n');
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
          `pbxproj 里写死的 R6PH2TFB3Q 是原开发者的团队号（AGENTS.md 第 9 节，不许改工程文件），\n` +
          `**环境变量前缀不生效**，必须作为构建设置参数传：\n` +
          `  TEAM="\${AIDRUN_TEAM:-ZW39BS8NXT}"\n` +
          `  xcodebuild … -allowProvisioningUpdates DEVELOPMENT_TEAM="\$TEAM"\n` +
          `照抄 scripts/device-test.sh:25,60。不传的报错是 \`No Account for Team "R6PH2TFB3Q"\`，\n` +
          `字面上不提团队号从哪来，容易被误当成证书或 provisioning 问题查半天。\n` +
          `确实不需要签名（编译门禁），用 CODE_SIGNING_ALLOWED=NO，或行尾加 \`guard:allow missing-team\`。`
      );
    }

    process.exit(0);
  }

  // post：从磁盘读改动后的真实内容再查，比解析 diff 可靠
  if (tool !== 'Edit' && tool !== 'Write') process.exit(0);
  if (!filePath.endsWith('.swift')) process.exit(0);
  if (!path.isAbsolute(filePath) || !fs.existsSync(filePath)) process.exit(0);

  // 只查生产 target。测试里出现这些字符串是**正确**的 —— 红线用例本身就得把违规文案
  // 写成断言清单（`EmergencySOSTests.forbidden`），在那儿拦等于把守住红线的人抓起来。
  if (!/\/blindRun\/[^/]/.test(filePath) || /\/blindRun(Tests|UITests)\//.test(filePath)) {
    process.exit(0);
  }

  scanSwift(filePath);
  process.exit(0);
}

try {
  main();
} catch (err) {
  // 守卫自身出错绝不阻塞开发
  process.stderr.write(`[guard] internal error (ignored): ${err.message}\n`);
  process.exit(0);
}
