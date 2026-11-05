// 内容规则 · 界面与交互：减弱动态效果、scenePhase、按钮可点区与配色、盲人端用词、退出登录确认。
// 规则表的字段约定（pattern / check / files / exceptFiles / why）与扫描逻辑见 `content-scan.mjs`。

export const uiRules = {
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
  'scenephase-not-active': {
    // 2026-09-07 立。系统权限弹窗（麦克风 / 语音识别 / 定位 / 通知）由独立进程呈现，
    // 宿主 App 的 `scenePhase` 会短暂离开 `.active` 变成 `.inactive` —— 把这一刻当成
    // 「进后台」去清理状态，清掉的正是那个在等授权回调的会话。
    //
    // 本仓库的真实事故：`blindRunApp.swift` 的 `if phase != .active` 调
    // `cancelRecognitionForLifecycle()`，用户点完「允许」之后授权回调恢复时
    // `isCurrentRecognitionSession` 判 false ⇒ 静默 return，麦克风从未启动，
    // 一个字都不播。表现是「点了说话按钮完全没反应，要退出重进两次」。
    //
    // ⚠️ 这条守卫存在的理由是**纯函数保不住调用点**：判定已经抽成
    // `RecognitionLifecyclePolicy.cancelsRecognition(on:isListening:)` 并有用例钉着，
    // 但把调用点改回 `phase != .active`，那个纯函数只会变成没人调的死代码，用例照样全绿。
    //
    // 真进后台用 `phase == .background`；要区分「暂时失焦」与「真的走了」时，
    // 再看一眼业务自己的状态（我们看的是 `isListening`）。
    pattern: /\bphase\s*!=\s*(ScenePhase\.)?\.?active\b|\bscenePhase\s*!=\s*(ScenePhase\.)?\.?active\b/,
    check: () => true,
    why: '不要用 `scenePhase != .active` 当「App 进后台」：系统权限弹窗只会让它走一趟 `.inactive`，在那一刻清理会把正在等授权回调的会话静默毁掉（2026-09-07 真机事故：点完「允许」按钮完全没反应，要重启两次）。真进后台用 `phase == .background`；需要区分「暂时失焦」的，再看一眼业务状态（例如 `isListening`）。确实要拦下全部非活跃态，行尾加 `// guard:allow scenephase-not-active` 并写清为什么权限弹窗那一刻清理是安全的。',
  },
  'bordered-frame-hit-area': {
    // 2026-10-14 立（#383）。`.buttonStyle(.bordered*)` 之后再挂 `.frame(minHeight: 64)`，
    // 按钮看起来是 64pt，真机量到的可点区只有 34.7pt：外面那层 frame 只撑大布局，
    // bordered 样式的可点区仍按 label 尺寸算。PR #380 在下单页量出来一次，
    // 之后又扫出两处同样写法 —— 第三次出现，按 AGENTS.md §1 落成守卫。
    //
    // 只认 `.buttonStyle` **之后** 3 行内、作为按钮修饰符的 `.frame(…minHeight…)`。
    // frame 挂在 label 里（正解）时它出现在 `.buttonStyle` 之前，不会被扫到。
    pattern: /\.buttonStyle\(\s*\.bordered/,
    check: (_line, statement) =>
      statement.split('\n').slice(1).some((l) => /^\s*\.frame\([^)]*minHeight/.test(l)),
    why: 'bordered 按钮外挂 `.frame(minHeight:)` 撑不大可点区（真机实测 34.7pt，盲人端要求 ≥64pt）。把 frame 挪进 label：`Button { … } label: { Text(…).frame(minHeight: 64) }`。记忆 `button-frame-outside-label-does-not-grow-hit-area`。确实不是可点区问题，行尾加 `// guard:allow bordered-frame-hit-area`。',
  },
  'blind-side-escort-term': {
    // 2026-10-28 立（#527）。陪跑一方原有 6 种叫法（志愿者 151 处 / 陪跑员 68 处 / 搭档 / 陪跑志愿者 / 陪跑伙伴…），
    // 盲人端同一段旅程先听到「志愿者」再看到「陪跑员」，语音词表又只认「联系志愿者」。
    // 界面用词定在 GLOSSARY.md「界面用词」：盲人端一律「陪跑员」。只盯 `BlindRunner/` —— 那里只有盲人端；
    // `Core/` `Shared/` `Voice/` 两端共用，身份类用法（「我是志愿者」）合法，静态分不清，靠表与评审。
    // 只看字符串字面量；调试用的「模拟志愿者…」按钮是 UI 测试按标签点的入口，放行。
    files: /\/blindRun\/BlindRunner\//,
    pattern: /"[^"]*志愿者[^"]*"/,
    check: (line) => !/模拟志愿者/.test(line),
    why: '盲人端对陪跑一方一律叫「陪跑员」（GLOSSARY.md「界面用词」）：同一段旅程先听「志愿者」再看「陪跑员」，用户会以为是两个人；语音「问一句」也按屏幕上的叫法教用户说。身份类用法（角色、认证）不在这个目录。确实要用，行尾加 `// guard:allow blind-side-escort-term` 并写清为什么。',
  },
  'bordered-prominent': {
    // 2026-10-28 立（#527）。`.borderedProminent` 的字恒为白，底色取环境 tint，而 tint 在本 App 里
    // 有三个值：标签页容器里是 `Flow.tabSelected`（暗色档纯白 ⇒ 白底白字，2026-09-25 截图撞过一次），
    // 标签页外是 `AccentColor`（没定义时是系统蓝，白字亮 4.02:1、暗 3.65:1）。一共 8 处，两端都有 ——
    // 同一个错第二次以上，按 AGENTS.md §1 落成守卫。替代品 `PrimaryButtonStyle` 把底色与字色成对给出。
    pattern: /\.buttonStyle\(\s*\.borderedProminent\b/,
    check: () => true,
    why: '不用 `.borderedProminent`：它的白字压在环境 tint 上，标签页里暗色是白底白字，标签页外是系统蓝（白字亮 4.02:1、暗 3.65:1）。实心主按钮改用 `.buttonStyle(PrimaryButtonStyle())` 或 `PrimaryButton`（`Core/DesignSystem/PrimaryButton.swift`），底色与字色在那里成对给出并有对比度用例。确实要用（例如明确设了不变的 `.tint`），行尾加 `// guard:allow bordered-prominent` 并写清 tint 从哪来。',
  },
  'logout-without-confirmation': {
    // 2026-10-28 立（#561）。退出登录是危险操作，要二次确认。四个页面各抄一份同样的确认弹窗，
    // 第五处（启动恢复失败页）漏抄，按下就退 —— 复制粘贴式的安全约束总会漏一处。
    // 弹窗收成 `logoutConfirmation(isPresented:)` 一份，只有它所在的文件可以调 `appState.logout()`。
    // 认可选链：view model 多半 weak 持有 appState，写成 `appState?.logout()`。
    pattern: /\bappState[?!]?\.logout\(\)/,
    check: () => true,
    exceptFiles: /\/Auth\/LogoutConfirmation\.swift$/,
    why: '不要在按钮里直接调 `appState.logout()`：退出登录必须二次确认（skill `aidrun-a11y-voice`），读屏用户滑过按钮时双击一下就会被退出。按钮只把开关置真，弹窗用 `.logoutConfirmation(isPresented: $showLogoutConfirm)`（`blindRun/Auth/LogoutConfirmation.swift`）。确有不经用户的退出路径（例如服务端吊销），行尾加 `// guard:allow logout-without-confirmation` 并写清为什么。',
  },
};
