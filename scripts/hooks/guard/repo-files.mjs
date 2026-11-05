// pre 段 · 仓库文件、依赖与密钥：归档契约、冻结文件与架构排除设置、隐私清单、高德 key、OpenAPI 运行时。
// 每个函数命中即 `fail()` 退出 2；没命中就返回。调用顺序由 `guard.mjs` 决定。

import { fail, nonCommentLines } from './common.mjs';

// Podfile 保持整文件冻结：架构排除设置与 pod 列表都在里面，没有安全的局部改法。
const FROZEN = [/(^|\/)Podfile$/];

// project.pbxproj 不再冻结：2026-08-05 起行级冻结 DEVELOPMENT_TEAM，2026-10-03 负责人解冻（#302），
// 12 处团队号改为 QW8R457UHN。架构排除设置不必在这里重复挡，下面那条内容级规则对所有文件都生效。

// 键名拼出来而不是写成字面量 —— 见下面用到它的地方的说明。
const ARCH_EXCLUSION_KEY = new RegExp(['EXCLUDED', 'ARCHS'].join('_'));

export function checkArchivedContract({ tool, filePath }) {
  // 1. 禁读已知有错的归档契约副本（AGENTS.md 第 2 节）
  if (tool === 'Read' && /docs\/_archive-.*\.bak$/.test(filePath)) {
    fail(
      'archived-contract',
      `${filePath}\n\n这是已归档的旧 API 契约副本，含已知错误，不得读取或复制（AGENTS.md 第 2 节）。` +
        `\n契约唯一源是后端仓库 /Users/mac/Downloads/demo 的 docs/api_spec.yaml 与 docs/websocket-protocol.md。`
    );
  }
}

export function checkFrozenFile({ filePath }) {
  // 2. 冻结文件（AGENTS.md 第 9 节）
  if (FROZEN.some((re) => re.test(filePath))) {
    fail(
      'frozen-files',
      `${filePath}\n\n该文件是冻结的（AGENTS.md 第 9 节）。真机是唯一 XCTest 通道，` +
        `模拟器因高德无 arm64-sim slice 永久不可用；架构排除设置与 pod 列表都在这里，没有安全的局部改法。`
    );
  }
}

export function checkArchExclusion({ filePath, body }) {
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
  //
  // 这条**故意不过 nonCommentLines**：AGENTS.md 第 9 节写死了「确需在代码或注释里提及，
  // 行尾加 guard:allow excluded-archs」。注释里出现这个键名值得停一下看看是不是真注释，
  // 而 .md 已经整类豁免，文档本身不受影响。
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
}

export function checkVendorPrivacyManifest({ filePath, body }) {
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
  // 注释行放行（nonCommentLines）：podspec 里那段「为什么不要加回来」的说明本身就写着
  // 这个文件名，不跳过的话整份 Write 会被自己的文档拦住。
  const vendorManifestLine = isPodspec
    ? nonCommentLines(body).find(
        (l) => /PrivacyInfo\.xcprivacy/.test(l) && !l.includes('guard:allow vendor-privacy-manifest')
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
}

export function checkSdkOnlyReasonCode({ filePath, body }) {
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
}

export function checkAmapKey({ filePath, body }) {
  // 3. 高德 key 硬编码（AGENTS.md 第 8 节）
  //
  // 这条**故意不过 nonCommentLines**：注释里的真实 key 一样是被提交的真实 key，
  // 「注释掉就不算泄露」正是密钥进仓库最常见的那条路。
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
}

export function checkOpenAPIInAppTarget({ filePath, body }) {
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
}
