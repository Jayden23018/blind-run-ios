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
  'placeholder-promise': {
    // 2026-08-13：`VolunteerPointsPlaceholderView` 是一整页对志愿者的空头承诺 ——
    // 积分数字写死 `--`，4 个商品硬编码全标「敬请期待」，配套的 view model 只有一个
    // 从不被赋值的 `errorMessage`。它在仓库里躺了很久，没有任何检查会说一句话。
    //
    // 一个永远兑现不了的承诺比没有承诺更伤：它每次都在提醒用户，平台说过什么、又没做到
    // （调研里「没有实质的表彰」是激励设计的首要陷阱，
    // `docs/research/live-trip-sharing-and-volunteer-incentives-20260813.md` §2）。
    //
    // 占位 UI 本身不是问题，**把占位说成即将兑现的承诺**才是。要摆占位就如实说
    // 「这个功能还没有」，别给日期、别说「即将」。
    pattern: /敬请期待|即将上线|敬请关注/,
    why: '不要在出货代码里承诺一个还不存在的功能（「敬请期待」「即将上线」）。占位 UI 可以有，但要如实说明该功能当前不可用，不要给出会兑现的暗示 —— 兑现不了的承诺比没有承诺更伤信任。确实要保留，行尾加 `// guard:allow placeholder-promise`。',
  },
  'volunteer-hours-credential': {
    // 志愿服务记录证明受《志愿服务记录与证明出具办法（试行）》（民政部令第 67 号）约束：
    // 须经志愿服务信息系统出具、可查验。我们**没有**与全国志愿服务信息系统完成数据对接，
    // 所以成就页上的时长与星级只是展示，不是凭据。
    //
    // 把它写成「服务证明」「时长证书」「时长已认证」不是措辞问题，是违规 —— 而志愿者会拿着
    // 这句话去学校申报，到那边才发现平台出具的东西不作数。
    //
    // 词表刻意不含「资质证书」「实名认证」「身份认证」：那些是志愿者注册流程里的真实动作，
    // 与服务时长的法律效力无关。新增说法时对着这条边界加，别把整个「认证」都堵死。
    pattern: /(志愿服务|服务时长|服务|时长|志愿|公益)(记录)?(证明|证书)|(时长|服务|星级|服务记录)已认证/,
    why: '客户端不得把志愿服务时长/星级说成「证明」「证书」「已认证」：可查验的志愿服务记录证明须经志愿服务信息系统出具（民政部令第 67 号），本平台尚未与全国志愿服务信息系统完成数据对接。改用「平台记录」「累计服务」这类展示性措辞，并说明对外申报要走志愿服务信息系统。确实要引用这些词（例如注释里解释为什么不能这么写），行尾加 `// guard:allow volunteer-hours-credential`。',
  },
  'motion-not-gated': {
    // 「减弱动态效果」是前庭功能的无障碍设置，与看不看得见无关：它服务的是晕动症用户，
    // 位移越大越难受。这条被漏过**两轮 review**（2026-08-12 与 08-15 都记着「只有 3 个文件响应」），
    // 原因是它没有任何运行时症状 —— 开发者自己不开这个设置就永远看不见。
    //
    // 拦的是**位移类**动效：滑入 / 弹簧 / 缩放 / 偏移，以及 `withAnimation`。
    // 不拦 `.opacity` / `.easeInOut` 的纯淡入淡出 —— 那正是降级后该有的样子。
    //
    // 降级写法（任选，`check` 认的是同一条语句里出现 reduceMotion）：
    //   .transition(reduceMotion ? .opacity : .move(edge: .top))
    //   .animation(reduceMotion ? nil : .spring(...), value: x)
    //   withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { ... }
    //
    // 只拦**写在这一行的动画字面量**（`.spring(` / `.move(` 这种）。传具名属性的写法
    // （`withAnimation(demandPanelAnimation)`）放行 —— 降级判断在那个属性的定义处，
    // 而那处若写了字面量同样会被这条规则查到，所以没有漏洞，只是把检查点挪到了定义处。
    pattern: /\.transition\(\s*\.(move|slide|scale|offset|push)|\.animation\(\s*\.(spring|interpolatingSpring|bouncy|snappy|smooth)|withAnimation\(\s*\./,
    check: (_line, statement) => !/reduceMotion|accessibilityReduceMotion/.test(statement),
    why: '位移类动效必须先看「减弱动态效果」（`@Environment(\\.accessibilityReduceMotion)`）：开启时降级为淡入淡出或瞬时到位。滑入/弹簧/缩放对晕动症用户是实打实的不适，而这条没有任何运行时症状 —— 自己不开这个设置就永远发现不了，所以只能靠守卫。确实无关（例如动的是不可见的辅助层），行尾加 `// guard:allow motion-not-gated`。',
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

// ---- accessibilityIdentifier 漂移检测（规则 8，见下面用到它的地方的完整说明）----

// XCUITest 里「按 identifier 找元素」的几种写法。
const UI_TEST_QUERY_KEY =
  /(?:staticTexts|buttons|textFields|switches|navigationBars|alerts|scrollViews|otherElements|images|cells)\[\s*"([^"]+)"\s*\]|matching\(identifier:\s*"([^"]+)"\)|descendants\(matching:\s*\.any\)\[\s*"([^"]+)"\s*\]/g;

// 只判 ASCII 标识符形状的键。中文文案不在此列 —— 理由见规则 8 的注释。
const IDENTIFIER_SHAPED = /^[A-Za-z][A-Za-z0-9._]*$/;

// iOS 系统键盘的按键（收键盘用），不是 App 挂的 identifier，App 侧永远找不到它们。
// 白名单只有这两个，且必须写明理由 —— 白名单一长，这条规则就被架空了。
const SYSTEM_KEYBOARD_IDENTIFIERS = new Set(['Done', 'Return']);

const ACCESSIBILITY_IDENTIFIER = /accessibilityIdentifier\(\s*"((?:[^"\\]|\\.)*)"\s*\)/g;

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// App 侧字面量里的插值段当通配：`"\(identifierPrefix)AgreeButton"` 要能匹配
// `appLaunchConsentAgreeButton`，`"volunteerRegistrationStep.\(step.displayIndex)"`
// 要能匹配 `volunteerRegistrationStep.1`。
// 已知上限：插值里再套括号（`\(f(x))`）会截断在第一个 `)` —— 本仓库目前没有这种写法，
// 真出现了它只会让规则更宽松（多匹配），不会误报。
function identifierLiteralToRegExp(literal) {
  const parts = literal.split(/\\\([^)]*\)/).map(escapeRegExp);
  return new RegExp(`^${parts.join('.+')}$`);
}

function collectSwiftFiles(dir, out = []) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) collectSwiftFiles(full, out);
    else if (entry.name.endsWith('.swift')) out.push(full);
  }
  return out;
}

function readFileOrEmpty(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch {
    return '';
  }
}

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
      // check 拿得到后续几行：SwiftUI 经常把动画曲线折到 `.animation(` 的下一行，
      // 只看当前行会把已经做了降级的写法误判成违规。
      if (rule.check && !rule.check(line, lines.slice(i, i + 4).join('\n'))) continue;
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

    // 2.5 隐私清单的两个坑（2026-08-21）
    //
    // (a) vendored podspec 把 PrivacyInfo.xcprivacy 列进 s.resources
    //
    // `s.resources` 是**平铺**复制到 App bundle 根目录，而根目录那份**就是主 App 自己的**
    // 隐私清单槽位。Vendor/AliyunCloudAuth/2.3.50 原先就这么写，造成两件事：
    //   · 与 blindRun/PrivacyInfo.xcprivacy 撞车 → "Multiple commands produce .../PrivacyInfo.xcprivacy"
    //   · 撞车之前（没有主 App 清单时）更隐蔽：阿里云的清单**冒充**主 App 的对外声明，
    //     ITMS-91053 看着过了，实际过的是别人的文件 —— 且它带着 NSPrivacyCollectedDataTypes
    //     DeviceID/Linked=true，purpose 写的 "Protect Device Security" 根本不是 Apple 的合法取值。
    // 升级阿里云 SDK 时重新落一份 podspec 是常规动作，这个洞会原样回来，所以按文件类型拦死。
    const isPodspec = /\.podspec$/.test(filePath);
    const vendorManifestLine = isPodspec
      ? body
          .split('\n')
          .find(
            (l) =>
              // 注释行放行：podspec 里那段「为什么不要加回来」的说明本身就写着这个文件名，
              // 不跳过的话整份 Write 会被自己的文档拦住。
              !/^\s*#/.test(l) &&
              /PrivacyInfo\.xcprivacy/.test(l) &&
              !l.includes('guard:allow vendor-privacy-manifest')
          )
      : undefined;
    if (vendorManifestLine) {
      fail(
        'vendor-privacy-manifest',
        `${filePath}\n  ${vendorManifestLine.trim()}\n\n` +
          `不要在 podspec 里声明 PrivacyInfo.xcprivacy。\`s.resources\` 是平铺复制到 App bundle 根目录，\n` +
          `而根目录那份是**主 App 自己的**隐私清单槽位 —— 会撞车（Multiple commands produce），\n` +
          `或者更糟：在主 App 还没有清单时冒充主 App 的对外数据收集声明。\n` +
          `本 SDK 的 framework 全是静态库，静态库代码链进主二进制，它用到的 required reason API\n` +
          `必须由 blindRun/PrivacyInfo.xcprivacy 声明（已声明 DiskSpace/FileTimestamp）。\n` +
          `确有必要（例如改用 s.resource_bundles 放进独立 .bundle），行尾加 \`# guard:allow vendor-privacy-manifest\`。`
      );
    }

    // (b) 把「仅限第三方 SDK」的 reason code 抄进主 App 的清单
    //
    // Apple 对 1C8F.1（UserDefaults）与 3B52.1（FileTimestamp）逐字写着
    // "This reason may only be declared by third-party SDKs"。阿里云的 roll-up 清单里两条都有，
    // 而「把 vendor 清单的内容合并进主 App 清单」正是修 ITMS-91053 时最自然的动作 ——
    // 抄进来换到的是 ITMS-91055 无效理由，且要等下一次上传才知道。
    // 路径按「含不含 /Vendor/」判，不能锚在字符串开头 —— 钩子拿到的是绝对路径。
    const isAppManifest = /\.xcprivacy$/.test(filePath) && !/(^|\/)Vendor\//.test(filePath);
    const sdkOnlyCodeLine = isAppManifest
      ? body.split('\n').find((l) => /<string>\s*(3B52\.1|1C8F\.1)\s*<\/string>/.test(l))
      : undefined;
    if (sdkOnlyCodeLine) {
      fail(
        'sdk-only-reason-code',
        `${filePath}\n  ${sdkOnlyCodeLine.trim()}\n\n` +
          `1C8F.1 与 3B52.1 是 Apple 明写「仅限第三方 SDK 声明」的 reason code，主 App 的清单里填了会触发 ITMS-91055。\n` +
          `主 App 该用的对应项：UserDefaults → CA92.1；FileTimestamp → DDA9.1（App 容器内文件）或 C617.1（用户经文档选择器授权的文件）。\n` +
          `注意别照抄 Vendor/ 下第三方 SDK 的 roll-up 清单，那份是按「第三方 SDK」身份写的。`
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

    // 6.5 绕开 EmergencyDialer 直接开 URL（2026-08-14）
    //
    // 真机 UI 测试里一次误触走到了 `tel://110`：触点落在底部常驻求助条上，弹出本地拨号
    // 确认单，随后的 swipe 又在确认单上选中「拨打110」。那台 iPhone 是双卡，iOS 多弹了
    // 一层 `com.apple.BusinessActionSheet` 选号单才没拨出去 —— 单卡设备上会直接拨给警方。
    //
    // 现在拨号统一走 `EmergencyDialer.dial(_:)`，它在 DEBUG 下按启动环境拦截并留痕。
    // 但只要有人再写一行裸的 `UIApplication.shared.open`，那道拦截就等于不存在，
    // 而这种「新增一个出口」是最不会被 review 注意到的改法。
    //
    // 规则按出口登记：拨号走 `EmergencyDialer.dial`；确实是别的 scheme（地图、系统设置、
    // 短信 composer）就在行尾标注，标注本身就是那份出口清单。
    // 已登记：ExternalMapNavigation.swift:145、LocationPermissionGuard.swift:57、
    // BlindBookingView.swift:1717。
    const isProductionSwift =
      /\/blindRun\/[^/]/.test(filePath) &&
      /\.swift$/.test(filePath) &&
      !/\/blindRun(Tests|UITests)\//.test(filePath) &&
      !/\/Safety\/SafetyModule\.swift$/.test(filePath);
    //
    // 2026-08-20 补 `tel://`：原规则只认 `UIApplication.shared.open`，而志愿者端两处拨号写的是
    // SwiftUI 的 `@Environment(\.openURL)` + `openURL(URL(string: "tel://\(phone)"))`
    // （`VolunteerOrderFlowViews.swift:2559,2865`）—— 同一个洞、换一种拼法，整整两处从这道
    // 守卫底下走了过去。所以判据改成**按 URL 本身登记**：`tel://` 只允许出现在
    // `EmergencyDialer.telURL` 里，不再去追有多少种 open 的写法（追写法必然漏下一种）。
    const rawOpenLine = isProductionSwift
      ? body
          .split('\n')
          .find(
            (l) =>
              (/UIApplication\.shared\.open\(/.test(l) || /"tel:\/\//.test(l)) &&
              !l.includes('guard:allow raw-open-url')
          )
      : undefined;
    if (rawOpenLine) {
      fail(
        'raw-open-url',
        `${filePath}\n  ${rawOpenLine.trim()}\n\n` +
          `拨号必须走 \`EmergencyDialer.dial(_:)\`（blindRun/Safety/SafetyModule.swift）——\n` +
          `它是唯一拨出点，DEBUG 下按启动环境拦截并记一次痕迹。裸的 UIApplication.shared.open\n` +
          `会绕开拦截：2026-08-14 真机 UI 测试因此差点真的拨出 110（当时只有双卡选号单挡了一下）。\n` +
          `确实是别的 scheme（地图 / 系统设置 / 短信），行尾加 \`// guard:allow raw-open-url\`。`
      );
    }

    // 6.6 盲人端触达低于 64pt（2026-08-15）
    //
    // AGENTS 与 `AccessibilityAuditTests` 的线是 64pt，不是 Apple 的 44pt —— 视障用户是靠
    // 手指扫过屏幕找控件的，44pt 的目标能被 VoiceOver 读到，却不一定按得中。
    //
    // 但那条 UI 审计只量**主按钮**（`minimumBlindPrimaryButtonHeight`，逐页点名），
    // 于是次级控件一路漏了过去：「跳过评价并返回首页」52pt、「查看大图路线」44pt、
    // 「临时显示身份证号」44pt、收藏地点那三处 52pt —— 六处都在盲人自己要按的路径上，
    // 六处都没有任何检查说过一句话（`docs/review/frontend-backend-alignment-review-20260812.md` §D6
    // 只点了其中一处，一处一处修就是这条守卫存在的理由）。
    //
    // 志愿者端不在此列：那边是明眼人用的，走 Apple 的 44pt 线。
    // 非交互元素（文本块最小高度之类）确实用得着小数值，行尾标注即可 —— 标注本身
    // 就是「这不是触达目标」的声明。
    const isBlindFacingSwift =
      /\/blindRun\/[^/]/.test(filePath) &&
      /\.swift$/.test(filePath) &&
      !/\/blindRun(Tests|UITests)\//.test(filePath) &&
      !/\/blindRun\/Volunteer\//.test(filePath);
    const smallTargetLine = isBlindFacingSwift
      ? body.split('\n').find((l) => {
          const m = l.match(/\.frame\((?:[^)]*,\s*)?minHeight:\s*(\d+)/);
          return m && Number(m[1]) < 64 && !l.includes('guard:allow small-touch-target');
        })
      : undefined;
    if (smallTargetLine) {
      fail(
        'small-touch-target',
        `${filePath}\n  ${smallTargetLine.trim()}\n\n` +
          `盲人端触达高度不得低于 64pt（AGENTS.md 第 8 节的 64pt 线，比 WCAG 2.5.5 的 44pt 更严）。\n` +
          `视障用户靠手指扫过屏幕找控件：44pt 的目标读得到、按不中，而按不中在盲人端的表现是「点了没反应」。\n` +
          `\`AccessibilityAuditTests\` 只量逐页点名的主按钮，次级控件全靠这条守卫。\n` +
          `确实不是触达目标（纯文本块的最小高度等），行尾加 \`// guard:allow small-touch-target\`。`
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

    // 8. UI 测试与 App 的 accessibilityIdentifier 对不上（2026-08-22）
    //
    // 2026-08-14 `30b0770` 把盲人首页装饰地图对读屏隐藏，连同
    // `.accessibilityIdentifier("blindRunnerHomeAuxiliaryMap")` 一起删掉 —— 那是隐藏它的既定代价。
    // 同一个提交改了 blindRunUITests 58 行，但**漏了一处**，`testRealAMapEnabledSmoke` 从那天起
    // 一直红，8 天后才被查出来（`docs/review/ui-test-red-triage-20260822.md`）。
    // 本仓库 CI 跑不了 XCTest（高德无 arm64-sim slice），红用例照样能合进 main，
    // 所以这类漂移**没有任何运行时信号**，只能靠静态检查。
    //
    // 两个方向都查：
    //   A. 改 UI 测试时写了一个 App 侧不存在的 identifier
    //   B. 改 App 代码时删掉了一个 UI 测试还在用的 identifier（`30b0770` 就是这个方向）
    //
    // **只判 identifier 形状的键。** 中文文案那版实测过：149 个查询键报 28 个，其中 26 个是
    // 插值拼出来的 a11y label（「张三，关系家人，电话139****9001，非主联系人」这种），误报 93%
    // —— 白名单会比信号还长，那种守卫会被下一个人直接关掉。identifier 版实测 45 个键报 5 个：
    // 2 个系统键盘键（已白名单），3 个是真问题。所以「积分」那类中文文案漂移这条**管不了**，
    // 别以为它覆盖了。
    //
    // 故意断言某个 identifier **不存在**（例如 `matching(identifier:).count == 0`）是合法的，
    // 行尾加 `// guard:allow stale-ui-test-identifier` —— 标注本身就是「这个 id 是被有意删掉的」的声明。
    const repoRootMatch = filePath.match(/^(.*)\/blindRun(?:Tests|UITests)?\//);
    const repoRoot = repoRootMatch ? repoRootMatch[1] : '';
    const appDir = repoRoot ? path.join(repoRoot, 'blindRun') : '';
    const uiTestDir = repoRoot ? path.join(repoRoot, 'blindRunUITests') : '';
    // 两侧都读得到才判。读不到（工程结构变了、跑在别的目录里）时宁可漏，不可误报。
    const canCrossCheck = Boolean(appDir) && fs.existsSync(appDir) && fs.existsSync(uiTestDir);

    if (canCrossCheck && isUITest) {
      const matchers = [];
      for (const file of collectSwiftFiles(appDir)) {
        for (const m of readFileOrEmpty(file).matchAll(ACCESSIBILITY_IDENTIFIER)) {
          matchers.push(identifierLiteralToRegExp(m[1]));
        }
      }
      // 一个都没读到说明扫描本身出了问题，别把它当成「App 侧什么 id 都没有」。
      if (matchers.length > 0) {
        for (const line of body.split('\n')) {
          if (line.includes('guard:allow stale-ui-test-identifier')) continue;
          for (const m of line.matchAll(UI_TEST_QUERY_KEY)) {
            const key = m[1] || m[2] || m[3];
            if (!key || !IDENTIFIER_SHAPED.test(key)) continue;
            if (SYSTEM_KEYBOARD_IDENTIFIERS.has(key)) continue;
            if (matchers.some((re) => re.test(key))) continue;
            fail(
              'stale-ui-test-identifier',
              `${filePath}\n  ${line.trim()}\n\n` +
                `UI 测试引用了 identifier \`${key}\`，但 blindRun/ 里没有任何 accessibilityIdentifier 会产出它。\n` +
                `这条断言永远命中不了：正面断言必然红，反面断言（XCTAssertFalse）恒真、等于没写。\n` +
                `本仓库 CI 跑不了 XCTest，所以这种漂移合进 main 时不会有任何信号。\n` +
                `改法：用 App 侧真实存在的 identifier，或改成按 label 断言。\n` +
                `确实是想断言它**不存在**，行尾加 \`// guard:allow stale-ui-test-identifier\`。`
            );
          }
        }
      }
    }

    // B：App 侧删掉 identifier，而 UI 测试还在用它。
    // 只对 Edit 生效（要有 old_string 才知道删了什么）。Write 整文件重写查不到，
    // 那种改法本来就会被方向 A 在改测试时拦下。
    const removedIdentifiers = canCrossCheck && /\.swift$/.test(filePath) && appDir && filePath.startsWith(`${appDir}/`)
      ? [...(input.old_string || '').matchAll(ACCESSIBILITY_IDENTIFIER)]
          .map((m) => m[1])
          .filter((lit) => !lit.includes('\\(') && !body.includes(`accessibilityIdentifier("${lit}")`))
      : [];
    for (const removed of removedIdentifiers) {
      // 同一个 id 可能在别处还挂着（挪了位置而不是删了），那不算删除。
      const stillInApp = collectSwiftFiles(appDir).some(
        (file) => file !== filePath && readFileOrEmpty(file).includes(`accessibilityIdentifier("${removed}")`)
      );
      if (stillInApp) continue;
      const referencing = collectSwiftFiles(uiTestDir).filter((file) =>
        readFileOrEmpty(file)
          .split('\n')
          .some((l) => l.includes(`"${removed}"`) && !l.includes('guard:allow stale-ui-test-identifier'))
      );
      if (referencing.length === 0) continue;
      fail(
        'stale-ui-test-identifier',
        `${filePath}\n  删掉了 accessibilityIdentifier("${removed}")\n\n` +
          `但这些 UI 测试还在按它找元素：\n` +
          referencing.map((f) => `  · ${path.relative(repoRoot, f)}`).join('\n') +
          `\n\n先把 UI 测试改掉再删 identifier。本仓库 CI 跑不了 XCTest，漏改的那一处不会有任何信号：\n` +
          `2026-08-14 \`30b0770\` 就是这么让 testRealAMapEnabledSmoke 红了 8 天。\n` +
          `确实是有意让它消失、且测试那边断的就是「不存在」，在测试那一行加 \`// guard:allow stale-ui-test-identifier\`。`
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
