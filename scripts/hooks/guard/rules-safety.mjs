// 内容规则 · 数据、安全与状态机：邀请码开关、服务端地址、Token 存储、求助状态写入、
// async 闭包隔离、订单状态集合字面量。
// 规则表的字段约定（pattern / check / files / exceptFiles / why）与扫描逻辑见 `content-scan.mjs`。

const REAL_HOST = 'blindrun.culiu-tech.com';
// 2026-10-31 退役的裸 IP（#621）。备案绑定域名，发布包不得再带这个地址，写回一律拦。
const RETIRED_HOST = '47.114.113.171';

// RFC 2606 保留域名，永远不可能是真实服务端，不必标注
const DOC_HOSTNAMES = /^(www\.)?example\.(com|org|net)$/;

// `emergency-state-write` 的两半，拆开是为了让 `check` 能分辨命中的是哪一半。
const EMERGENCY_STATE_WRITE =
  /\bemergencyCoordinator\s*\??\.\s*(state|activeEvent)\b(\s*\??\.\s*\w+)*\s*(=(?!=)|\+=|-=)|\b(emergencyCoordinator|coordinator)\s*\??\.\s*((submittedLocationAccuracyMeters|mergedRetriggerCount|volunteerAlert|countdownTask|countdownAnnouncer|isWithdrawing)\b(\s*\??\.\s*\w+)*\s*(=(?!=)|\+=|-=)|(finish|outcome|locationNote|startServerCountdown)\s*\()/;
const BARE_COORDINATOR_STATE_WRITE = /\bcoordinator\s*\??\.\s*(state|activeEvent)\b(\s*\??\.\s*\w+)*\s*(=(?!=)|\+=|-=)/;

// `unannotated-async-closure` 的两半：存储属性（行首锚定）与函数 / init 参数（#550）。
// 共用的尾巴：冒号之后、函数类型之前只许出现不改变隔离的修饰（`@escaping` / `@Sendable` / `@autoclosure` /
// `sending` / `inout` / `consuming` / `borrowing`），以及显式的 `nonisolated(nonsending)` ——
// 后者和不写是同一个类型，`-emit-silgen` 里传 MainActor 函数值进去照样生成 `Builtin.ImplicitActor` thunk（#592 审查），
// 所以同样算没标。写了 `@MainActor` 或 `@concurrent` 就不匹配。
const ASYNC_FN_TYPE_AFTER_COLON =
  String.raw`\s*:\s*(?:@escaping\s+|@Sendable\s+|@autoclosure\s+|nonisolated\(nonsending\)\s+|sending\s+|inout\s+|consuming\s+|borrowing\s+)*\(?\s*(?:@Sendable\s+|nonisolated\(nonsending\)\s+)*\((?:[^()]|\([^()]*\))*\)\s*async\b`;
const UNANNOTATED_ASYNC_STORED = new RegExp(
  String.raw`^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:private|fileprivate|internal|public|open)(?:\(set\))?\s+|static\s+|lazy\s+|nonisolated\s+)*(?:let|var)\s+\w+` +
    ASYNC_FN_TYPE_AFTER_COLON
);
const UNANNOTATED_ASYNC_PARAM = new RegExp(String.raw`(?:^|[(,])\s*(?:\x60?\w+\x60?\s+)?\x60?\w+\x60?` + ASYNC_FN_TYPE_AFTER_COLON);

// `RunOrderStatus` 的全部 case（`blindRun/Core/Models/OrderModels.swift:12`）。
// 与 AGENTS.md 第 5 节的状态清单一一对应，外加解码兜底用的 `unknown`。
const ORDER_STATUS_CASES = new Set([
  'pendingMatch',
  'pendingIntroCall',
  'scheduledConfirmed',
  'pendingAccept',
  'inProgress',
  'driverEnRoute',
  'driverArrived',
  'completed',
  'cancelled',
  'rematching',
  'noVolunteer',
  'unknown',
]);

// 触发行是不是落在一个 `switch` 块里 —— 从它往回走到最近的函数/属性声明，
// 中途遇到 `switch` 就算是迁移表的一行。
//
// 为什么以「函数声明」为边界而不是数花括号：数括号要处理字符串、注释、闭包里的
// 括号，写对了也没人看得懂；而「同一个函数体内出现过 switch」对这条规则已经够用 ——
// 迁移表恒定是 `switch self { case …: return [...] }` 这一种形状。
// 上限已知：同一个函数里先写了个无关的 switch、再写一个裸字面量，会被放行。
// 真遇到了再收紧，别现在就为它把判据做复杂。
function withinSwitchBlock(before) {
  for (let i = before.length - 1; i >= 0; i--) {
    const line = before[i];
    if (/^\s*(?:@\w+\s+)?(?:(?:public|private|internal|fileprivate|static|final|override)\s+)*(?:func|var|init|subscript)\b/.test(line)) {
      return false;
    }
    if (/\bswitch\s+\S/.test(line)) return true;
  }
  return false;
}

export const safetyRules = {
  'invite-code-reward-flag': {
    // 2026-09-14 立。契约 `FeatureFlagsResponse.invitationRewardEnabled` 的 description 逐字：
    //
    //   「🚨 名字里的 Reward 是刻意的，语义与上面两个不一样：它只关奖励，不关关系建立。
    //     关着时邀请码照样要填、邀请关系照样落库，只是双方不发积分。
    //     **不要**因为它是 false 就把邀请码输入框藏掉 —— 那会让开关打开之后这批用户
    //     永久拿不到奖励，而他们当时根本没机会填。」
    //
    // 也就是说：这个开关与另外两个（streak / favorite）**不能按同一套写法接**。
    // 那两个关着时把对应 UI 藏掉是对的，而这个关着时藏掉，损失是**不可逆**的 ——
    // 设角色只能成功一次（`RoleSelectionView.swift:275` 的注释：没有「先设角色、再补邀请码」这条路），
    // 那一屏没给输入框，这批用户就永远补不回来了。
    //
    // 盯两个文件：
    //   · Role/RoleSelectionView.swift —— **输入框本体**（`inviteCodeSection`），契约点名的就是它
    //   · Shared/InviteCodeView.swift —— 邀请码展示页，同一个功能的另一半
    // 这两处都不该读这个开关。要根据它调整**文案**（例如不再承诺发积分）也别在这里读：
    // 把判断放进 `InviteCodeCopy` / `InviteCodeEntryCopy`，那边有用例钉着文案，
    // 而「读了开关」与「拿开关当显示条件」在 view 里长得一模一样，review 分不出来。
    //
    // 这条原本是 `IncentiveAdoptionTests.testInvitationRewardFlagIsNotWiredIntoAnyVisibilityDecision`
    // （PR #127）。它用 `#filePath` 拼宿主机路径去读源码，而本仓库真机是唯一 XCTest 通道
    // ⇒ 那个路径在手机上不存在，用例从写下那天起每次都是 Code 260，一次都没通过过。
    // 按 AGENTS.md 第 1 节，静态检查能抓的事就该落在这里，不是 XCTest。
    files: /\/blindRun\/(Shared\/InviteCodeView|Role\/RoleSelectionView)\.swift$/,
    pattern: /invitationRewardEnabled/,
    why: '邀请码的输入框与展示页不得读 `invitationRewardEnabled`（契约 FeatureFlagsResponse 逐字：「不要因为它是 false 就把邀请码输入框藏掉」）。这个开关只关**奖励**、不关关系建立：关着时邀请码照样要填、邀请关系照样落库。藏掉的损失不可逆 —— 设角色只能成功一次，没有「先设角色、再补邀请码」这条路，那一屏没给输入框的用户，开关打开后永久拿不到奖励。要按开关改**文案**（不再承诺发积分）就放进 InviteCodeCopy / InviteCodeEntryCopy，那边有用例钉着；view 里「读了开关」和「拿它当显示条件」长得一样，review 分不出来。确有别的用途，行尾加 `// guard:allow invite-code-reward-flag` 并写清它不是显示条件。',
  },
  'server-addr': {
    // 两件事一条规则：**主机**必须是那一个，**scheme** 必须是加密的那一种。
    //
    // 2026-09-14 补 scheme 这一半。原判据只有「主机名对不对」，于是
    // 明文写法（把 https 换成 http，主机一个字没改）能原样穿过去 —— 实测 exit 0。
    // 而 2026-09-08 切 https 之前，实时位置与 SOS 坐标全程明文，那是这个 App
    // 最不能明文传的两样东西；`Info.plist` 的 ATS 例外也已随之删除（AGENTS.md 第 3 节：「别再加回来」）。
    // 一条派生文档（docs/ui/ui-review-checklist.md）当时还在逐项要求「固定使用」明文地址，
    // 照它改代码不会被任何检查拦住 —— 这条补丁就是那个洞。
    //
    // WebSocket 一并纳入：scheme 由 baseURL 推导（WebSocketService.connectionURL），
    // 仓库里本来就不该出现 ws/wss 字面量，出现即是新硬编码。
    //
    // 2026-10-31 补主机全等（#621）。裸 IP 时代的子串比较换成域名后，长主机和别的子域都能穿过去。
    // 旧 IP 不带 scheme 也拦：`components.host = "<旧 IP>"` 不会命中 URL 那一半正则。
    // 主机按 URL 解析后比较：只截 `@` 之前的字符会把 `https://<备案域名>@evil.net` 读成备案域名。解析失败按违规算。
    pattern: /(?:https?|wss?):\/\/[^\s"'`]+|47\.114\.113\.171/,
    check: (line) => {
      if (line.includes(RETIRED_HOST)) return true;
      const urls = line.match(/(?:https?|wss?):\/\/[^\s"'`]+/g) || [];
      return urls.some((u) => {
        let parsed;
        try {
          parsed = new URL(u);
        } catch {
          return true;
        }
        const isRealHost = parsed.hostname === REAL_HOST && !parsed.port && !parsed.username && !parsed.password;
        if (!isRealHost) return !DOC_HOSTNAMES.test(parsed.hostname);
        return parsed.protocol === 'http:' || parsed.protocol === 'ws:'; // 主机对了，但走的是明文
      });
    },
    why: `所有真实 HTTP 必须走 https://${REAL_HOST}（WebSocket 对应 wss://），地址在 App 内不可配置，不得加入本地或占位的真实服务端地址（AGENTS.md 第 3 节）。\n主机写对但 scheme 退回明文（http:// / ws://）同样拦：实时位置与 SOS 坐标是这个 App 最不能明文传的两样东西，且 Info.plist 的 ATS 例外已删除，明文请求会直接失败。\n旧 IP ${RETIRED_HOST} 已退役：备案绑定域名，App 备案填的后台域名必须是 App 实际连接的域名，发布包不得再带旧地址。`,
  },
  'token-in-userdefaults': {
    // AGENTS.md 第 8 节逐字：「不要把 access token 写进 UserDefaults」。
    // `UserDefaults` 是 App 容器里的明文 plist，会进备份；Token 只能进 Keychain
    // （KeychainTokenStore.swift，kSecAttrAccessibleAfterFirstUnlock）。
    //
    // 2026-09-14 立。起因不是有人写错了，是**一份派生文档在教人写错**：
    // docs/ui/ui-review-checklist.md 有一条勾写着「当前 token 存 UserDefaults 且有注释说明
    // 生产需迁移 Keychain」，而迁移早就做完了。文档已订正，但订正挡不住下一份抄件。
    //
    // 只拦**写入**：AppState.restoredToken() 对历史值的一次性迁移是
    // `string(forKey:)` + `removeObject(forKey:)`，不含 `.set(`，不受影响 ——
    // 那段代码恰恰是在**清除** UserDefaults 里的 Token，拦住它等于把迁移路径堵死。
    //
    // ponytail: 词表只覆盖本仓库实际用过的两种拼法（具名 key 常量 / 字面量 forKey）。
    // 上限已知：换一个不含这些词的 key 名就能绕过；真出现第二种拼法时往词表里加，
    // 别改成「凡是 .set( 都拦」——那会把整个 UserDefaults 用法一起锁死。
    pattern: /\.set\([^)]*(?:UserDefaultsKeys\.accessToken|forKey:\s*"[^"]*(?:accessToken|access_token|authToken|jwt)[^"]*")/i,
    why: '不要把 access token 写进 `UserDefaults`（AGENTS.md 第 8 节）——那是 App 容器里的明文 plist，还会进备份。Token 只能经 `KeychainTokenStore`（`blindRun/Core/KeychainTokenStore.swift`，`kSecAttrAccessibleAfterFirstUnlock`，这样锁屏期间的后台陪跑仍读得到）。`AppState.restoredToken()` 里对历史值的一次性迁移只读取和删除，不写入，不会碰到这条。',
  },
  'emergency-state-write': {
    // 2026-10-28（#502）：`EmergencyCoordinator` 拆成 `Safety/EmergencyCoordinator*.swift` 几个文件后，
    // 求助状态的 setter 与几个内部方法只能从 private 放宽到 internal —— Swift 的 private 不跨文件。
    // 放宽之后编译器不再拦「别的文件直接写求助状态」，这一条补上：在外面写 `state = .idle`
    // 会绕过倒计时任务的收尾（`state.didSet`）、重复提交保护与发送失败后的对账，而且没有任何用例会红。
    //
    // 接收者认 `emergencyCoordinator`，以及只有这个类型才有的成员名前的 `coordinator`
    // （`state` / `activeEvent` 太常见，`coordinator.state = …` 在别的协调器上是合法写法，见下）。
    // 视图里持有它的属性多半就叫 `coordinator`（求助屏、陪跑员页、跑者执行屏都是），所以裸 `coordinator.state =`
    // 也拦，但只在**本文件声明过 `: EmergencyCoordinator`** 时 —— 由 `check` 判（#539 审查 B1）。
    pattern: new RegExp(`${EMERGENCY_STATE_WRITE.source}|${BARE_COORDINATOR_STATE_WRITE.source}`),
    check: (line, _statement, src) => {
      if (EMERGENCY_STATE_WRITE.test(line)) return true;
      return /:\s*EmergencyCoordinator\b/.test(src);
    },
    exceptFiles: /\/Safety\/EmergencyCoordinator[^/]*\.swift$/,
    why: '求助状态机只许在 `blindRun/Safety/EmergencyCoordinator*.swift` 里改写（#502 拆文件后这些成员只能是 internal，编译器不再替你拦）。在别处要改求助状态，给 coordinator 加一个方法（写在那几个文件里），由它在内部改写。确有正当理由，行尾加 `// guard:allow emergency-state-write` 并写明。',
  },
  'unannotated-async-closure': {
    // 2026-10-16（#449）陪跑员见面安排表单：View 存着 `let onSubmit: (Request, Double?) async -> Outcome`，
    // 调用方传进来的是 MainActor 闭包。工程开了 `SWIFT_APPROACHABLE_CONCURRENCY`，没标隔离的 async
    // 函数类型默认是 `nonisolated(nonsending)`，中间多一层转换 thunk —— 真机上请求体到服务层时已被释放，
    // 点提交即 `EXC_BAD_ACCESS`。单测直调 view model 全绿，只有「经闭包调用」才走到那层 thunk。
    // #451 把同写法的其余 9 处全部标成 `@MainActor`，这一条拦新写的。
    //
    // 认两种形状：`let/var 名字: (…) async`（含外面包一层 `(…)?` 的可选闭包，括号里可带 `@Sendable`），
    // 以及函数 / init 参数 `标签 名字: (…) async`（#550）。写成 `@MainActor (…) async` 时冒号后第一个属性
    // 不是 `@escaping` / `@Sendable`，不会匹配。
    //
    // #550 把参数也纳入：转换 thunk 在「把 MainActor 闭包传给没标隔离的参数」那一刻就生成，存不存起来只决定何时调用。
    // 参数这一形状在真机上会不会崩没有直接证据，统一要求显式标注，不赌。当时全仓 18 处：MainActor 类型里的
    // 标 `@MainActor`；在 detached task / task group / `async let` 里调的超时、竞速辅助函数标 `@concurrent`
    // （它们本来就不在调用方的执行器上跑；以后有人传 MainActor 方法引用进来，走的是普通的跳 actor，
    // 不是 #449 那种 `Builtin.ImplicitActor` thunk）。显式写 `nonisolated(nonsending)` 不算标：同一个类型、同一个 thunk。
    //
    // 参数那半不锚行首，行尾注释、字符串里的示例会误中，所以 `check` 先把字符串字面量清空、再去掉 `//` 之后的部分判一次
    // （先清字符串：`url: String = "https://…", op: () async` 这种写法按 `//` 一刀切会把后面的参数一起切掉）。
    // ponytail: 只认「标签: 函数类型」写在同一行；typealias 出来的 async 函数类型、返回值位置的函数类型、
    // 容器或泛型实参里的函数类型（`[() async -> Void]`）、参数列表括号嵌套超过两层、多行字符串里的内容都不管，真出现了再加。
    pattern: new RegExp(`${UNANNOTATED_ASYNC_STORED.source}|${UNANNOTATED_ASYNC_PARAM.source}`),
    check: (line) => {
      const code = line.replace(/"(?:[^"\\]|\\.)*"/g, '""').replace(/\/\/.*$/, '');
      return UNANNOTATED_ASYNC_STORED.test(code) || UNANNOTATED_ASYNC_PARAM.test(code);
    },
    why: 'async 函数类型（存储属性、函数 / init 参数）要显式标隔离（#449 / #451 / #550）。MainActor 代码里写 `@MainActor (…) async -> …`，参数写 `@escaping @MainActor (…) async -> …`。有意不在 MainActor 上跑的（在 detached task / task group / `async let` 里调的超时、竞速辅助函数）写 `@escaping @concurrent @Sendable (…) async -> …`。显式写 `nonisolated(nonsending)` 不算标：它和不写是同一个类型、同一个 thunk。不标的话它默认是 `nonisolated(nonsending)`，调用方传进来的 MainActor 闭包要经一层转换 thunk，真机上参数会在到达服务层前被释放（`EXC_BAD_ACCESS`，单测直调抓不到）。配一条「经闭包调用」的用例。确实不该标，行尾加 `// guard:allow unannotated-async-closure` 并写明为什么。',
  },
  'status-set-literal': {
    // 2026-09-21 立。起因是量出来的：全仓 69 处订单状态判定有三种写法，
    // 而**只有一种**会在后端加状态时说话 ——
    //   穷举 switch  39 处 → 加 case 时编译失败，逼一次决策
    //   default: 兜底 13 处 → 静默答 false
    //   数组字面量   17 处 → 静默答 false
    //
    // `OrderDisplayHelpers.swift` 自己把理由写死了：「同族其余判定一样写成穷举 switch：
    // 后端加状态时编译器逼一次决策」。后端已经加过两次状态（迁移 `0031` 通话磨合、
    // `0041` 跨天预约），这不是假想的风险。
    //
    // 代价最高的那一处是 `LiveEscortSessionCoordinator.isSessionEligible`：
    // 它答 false = 陪跑途中不推实时位置，而实时位置是走散告警与求助定位的唯一来源。
    //
    // **迁移表不拦**：`switch self { case .a: return [.b, .c].contains(target) }` 这种
    // 「逐态列出后继状态」的表，字面量在那里就是对的形状 —— 判据是字面量在不在一个
    // `switch` 块里（见 withinSwitchBlock）。这不是宽松，是这两件事本来就不同：
    // 表的每一行已经被外层 switch 穷举过了，加状态时照样编译失败。
    //
    // ponytail: 只拦数组字面量这一种形状，**不拦 `default:`**。
    // 判「这个 switch 是不是在 switch 订单状态」需要类型信息，正则做不到；
    // 而存量 13 处 `default:` 逐个改成穷举 = 13 × 11 格产品决策，那是另一件事。
    //
    // 不写 `files`：`scanSwift` 本来就只在生产 target 上跑到（见 main() 末尾那道
    // `/blindRun(Tests|UITests)/` 闸），再加一道路径闸只会多一个会漂的判据。
    pattern: /\[\s*\.[A-Za-z]\w*\s*(?:,\s*\.[A-Za-z]\w*\s*)+\]\s*\.contains\b/,
    check: (line, _window, _src, before) => {
      const set = line.match(/\[\s*\.[A-Za-z]\w*\s*(?:,\s*\.[A-Za-z]\w*\s*)+\]/);
      if (!set) return false;
      const names = (set[0].match(/\.([A-Za-z]\w*)/g) || []).map((s) => s.slice(1));
      // 别的枚举的集合字面量不归这条管 —— 只认订单状态
      if (!names.some((n) => ORDER_STATUS_CASES.has(n))) return false;
      return !withinSwitchBlock(before);
    },
    why:
      '订单状态的判定不要写成数组字面量（`[.driverEnRoute, .inProgress].contains(…)`）——' +
      '后端往状态机加值时它会**静默答 false**，没有任何东西会说一句话。\n' +
      '改成 `RunOrderStatus` 上一个具名的**穷举 switch** 判定（放 `Core/Models/OrderDisplayHelpers.swift`，' +
      '照 `fetchesVolunteerLocation` 的写法），这样加 case 时编译器会在那一处逼一次决策。\n' +
      '⚠️ 状态集恰好相同**不等于**可以复用同一条判定：`offersWaitedDuration` 与 `offersKeepWaiting` ' +
      '集合完全一样却刻意分开，理由写在它们自己的注释里。先问「这两处问的是不是同一个问题」。\n' +
      'Mock 侧照后端演（`handleGetActiveOrder` / `handleGetVolunteerLocation`）**本就该**用字面量：' +
      '耦合到客户端判定会毁掉「两边不对称才被看见」这个价值，那几处行尾加 `// guard:allow status-set-literal`。',
  },
};
