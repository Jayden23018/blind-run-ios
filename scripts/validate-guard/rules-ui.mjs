// `scripts/hooks/guard/rules-ui.mjs` 的自测用例：内容规则 · 界面与交互。
// 用例格式与运行方式见 `scripts/validate-guard.mjs`（exit 2 = 拦下，exit 0 = 放行）。

export const cases = [

  // motion-not-gated（2026-08-15）。这条被漏过两轮 review，因为它没有任何运行时症状：
  // 开发者自己不开「减弱动态效果」就永远看不见。下面六条把两个方向都钉住 ——
  // 光拦不放行会逼出一堆 `guard:allow`，那等于把规则关掉。
  {
    name: '滑入过渡没看减弱动态效果（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'struct V { var body: some View { Text("x").transition(.move(edge: .top)) } }'
  },
  {
    name: '弹簧动画没看减弱动态效果（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'struct V { var body: some View { Text("x").animation(.spring(response: 0.32), value: v) } }'
  },
  {
    name: 'withAnimation 没看减弱动态效果（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'struct V { func f() { withAnimation(.easeInOut(duration: 0.25)) { x = 1 } } }'
  },
  {
    name: '滑入过渡已降级为淡入（放行）',
    mode: 'post',
    expect: 0,
    swift: 'struct V { var body: some View { Text("x").transition(reduceMotion ? .opacity : .move(edge: .top)) } }'
  },
  {
    // SwiftUI 常把动画曲线折到下一行。只看当前行会把已经降级的写法误判成违规，
    // 而误报比漏报更致命：下一个人会直接加 `guard:allow` 把规则关掉。
    name: '曲线折到下一行的降级写法（放行）',
    mode: 'post',
    expect: 0,
    swift: 'struct V { var body: some View { Text("x")\n      .animation(\n        reduceMotion ? nil : .spring(response: 0.32),\n        value: v\n      ) } }'
  },
  {
    // 纯淡入淡出不该被拦：它正是降级之后该有的样子，拦它等于没有正确写法。
    name: '纯淡入淡出（放行）',
    mode: 'post',
    expect: 0,
    swift: 'struct V { var body: some View { Text("x").transition(.opacity) } }'
  },
  {
    // 同一条曲线用在三处时会被收敛成一个具名属性（`VolunteerHomeView.demandPanelAnimation`）。
    // 降级判断在属性定义处，那里写的字面量照样过这条规则 —— 检查点只是挪了位置，没有漏掉。
    name: '传具名动画属性（放行，判断在属性定义处）',
    mode: 'post',
    expect: 0,
    swift: 'struct V { func f() { withAnimation(demandPanelAnimation) { x = 1 } } }'
  },

  // scenephase-not-active（2026-09-07）。系统权限弹窗只会让 scenePhase 走一趟 `.inactive`，
  // 把它当成「进后台」去清理，毁的正是那个在等授权回调的会话。
  // 这条守卫的存在理由是纯函数保不住调用点 —— 判定改回去的话它只会变成死代码，用例全绿。
  {
    name: 'scenePhase != .active 当成进后台（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/blindRunApp.swift',
    swift: 'struct A { func f() { if phase != .active { speechInputService.cancelRecognitionForLifecycle() } } }'
  },
  {
    name: '写全 ScenePhase.active 也要拦',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/App.swift',
    swift: 'struct A { func f() { guard scenePhase != ScenePhase.active else { return } } }'
  },
  {
    name: 'phase == .background（正解，放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/blindRunApp.swift',
    swift: 'struct A { func f() { if phase == .background { speechInputService.cancelRecognitionForLifecycle() } } }'
  },
  {
    name: 'else if phase == .active（回前台分支，放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/blindRunApp.swift',
    swift: 'struct A { func f() { if x { y() } else if phase == .active { z() } } }'
  },
  {
    name: 'scenephase 违规行带 guard:allow 标注（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/blindRunApp.swift',
    swift: 'struct A { func f() { if phase != .active { dimScreen() } } } // guard:allow scenephase-not-active'
  },

  // bordered-frame-hit-area（2026-10-14，#383）。bordered 按钮外挂 frame 撑不大可点区。
  {
    name: 'bordered 按钮外挂 frame(minHeight:)（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'Button("重复当前状态", action: f)\n    .buttonStyle(.bordered)\n    .frame(minHeight: 64)\n'
  },
  {
    name: '中间隔一层 frame(maxWidth:) 也要拦',
    mode: 'post',
    expect: 2,
    swift: 'Button("去设置") { f() }\n    .buttonStyle(.bordered)\n    .frame(maxWidth: .infinity)\n    .frame(minHeight: 64)\n'
  },
  {
    name: 'frame 挂在 label 里（正解，放行）',
    mode: 'post',
    expect: 0,
    swift: 'Button { f() } label: {\n    Text("重复当前状态")\n        .frame(minHeight: 64)\n}\n.buttonStyle(.bordered)\n.accessibilityHint("x")\n'
  },
  {
    name: 'bordered 违规行带 guard:allow 标注（放行）',
    mode: 'post',
    expect: 0,
    swift: 'Button("x", action: f)\n    .buttonStyle(.bordered) // guard:allow bordered-frame-hit-area\n    .frame(minHeight: 64)\n'
  },

  // blind-side-escort-term（2026-10-28，#527）。盲人端对陪跑一方一律叫「陪跑员」。
  {
    name: '盲人端字符串里写「志愿者」（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/BlindRunner/BlindOrderStatusView.swift',
    swift: 'Text("打电话给志愿者")'
  },
  {
    name: '盲人端写「陪跑员」（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/BlindRunner/BlindOrderStatusView.swift',
    swift: 'Text("打电话给陪跑员")'
  },
  {
    name: '盲人端调试按钮「模拟志愿者接单」（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/BlindRunner/BlindOrderStatusView.swift',
    swift: 'Button("模拟志愿者接单") { simulate() }'
  },
  {
    name: '盲人端注释里写「志愿者」（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/BlindRunner/BlindOrderStatusView.swift',
    swift: '// 原先叫「打电话给志愿者」\nlet a = 1'
  },
  {
    // 反向哨兵：路径闸真的在生效 —— 共享目录里的身份类用法不该被拦。
    name: '角色选择页「我是志愿者」（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Role/RoleSelectionView.swift',
    swift: 'Text("我是志愿者")'
  },

  // bordered-prominent（2026-10-28，#527）。白字压环境 tint：标签页里暗色是白底白字，标签页外是系统蓝。
  // 上面 bordered-frame-hit-area 的用例因此都改写成 `.bordered`，免得两条规则互相替对方「拦下」。
  {
    name: '.buttonStyle(.borderedProminent)（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'Button("重试恢复") { f() }\n    .buttonStyle(.borderedProminent)\n'
  },
  {
    name: '括号里带空格的 .borderedProminent 也要拦',
    mode: 'post',
    expect: 2,
    swift: 'Button("重试恢复") { f() }\n    .buttonStyle( .borderedProminent )\n'
  },
  {
    name: '改用 PrimaryButtonStyle（正解，放行）',
    mode: 'post',
    expect: 0,
    swift: 'Button("重试恢复") { f() }\n    .buttonStyle(PrimaryButtonStyle())\n'
  },
  {
    // 反向哨兵：前缀相同的 `.bordered` 不该被 `\b` 之外的写法误伤。
    name: '.buttonStyle(.bordered)（放行）',
    mode: 'post',
    expect: 0,
    swift: 'Button("去设置") { f() }\n    .buttonStyle(.bordered)\n'
  },
  {
    name: '注释里解释为什么不用 .buttonStyle(.borderedProminent)（放行）',
    mode: 'post',
    expect: 0,
    swift: '/// 不要换回 `.buttonStyle(.borderedProminent)`，标签页里暗色是白底白字。\nstruct A {}\n'
  },
  {
    name: 'bordered-prominent 违规行带 guard:allow 标注（放行）',
    mode: 'post',
    expect: 0,
    swift: 'Button("x") { f() }\n    .buttonStyle(.borderedProminent) // guard:allow bordered-prominent tint 固定为 primary\n'
  },

  // logout-without-confirmation（2026-10-28，#561）。启动恢复失败页按下「退出登录」就退，没有确认。
  {
    name: '按钮里直接调 appState.logout()（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/ContentView.swift',
    swift: 'Button("退出登录", role: .destructive) {\n    Task { await appState.logout() }\n}\n'
  },
  {
    // view model 多半 weak 持有 appState：可选链是最常见的绕过写法。
    name: 'view model 里 appState?.logout()（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Profile/ProfileViewModel.swift',
    swift: 'func signOut() async {\n    await appState?.logout()\n}\n'
  },
  {
    name: '按钮只置开关、弹窗走 logoutConfirmation（正解，放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/ContentView.swift',
    swift: 'Button("退出登录", role: .destructive) { showLogoutConfirmation = true }\n    .logoutConfirmation(isPresented: $showLogoutConfirmation)\n'
  },
  {
    name: '共用确认弹窗自己的文件里调 appState.logout()（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Auth/LogoutConfirmation.swift',
    swift: 'Button("确认退出", role: .destructive) {\n    Task { await appState.logout() }\n}\n'
  },
  {
    // 反向哨兵：AppState 内部调接口的 `auth.logout()` 不是界面入口。
    name: 'AppState 里调 auth.logout()（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/AppState+SessionRevocation.swift',
    swift: '_ = try await auth.logout()\n'
  },
  {
    name: 'logout-without-confirmation 违规行带 guard:allow 标注（放行）',
    mode: 'post',
    expect: 0,
    swift: 'Task { await appState.logout() } // guard:allow logout-without-confirmation 服务端已吊销，不经用户\n'
  }
];
