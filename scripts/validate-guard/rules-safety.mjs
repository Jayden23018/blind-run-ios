// `scripts/hooks/guard/rules-safety.mjs` 的自测用例：内容规则 · 数据、安全与状态机。
// 用例格式与运行方式见 `scripts/validate-guard.mjs`（exit 2 = 拦下，exit 0 = 放行）。

export const cases = [

  // server-addr 的 scheme 那一半（2026-09-14 补）。
  // 原判据只看主机名，于是「主机对、scheme 退回明文」整类改动能原样穿过去 —— 实测 exit 0。
  // 下面头两条就是那个洞的形状；主机拼成字符串是为了本文件自己也过得了守卫。
  {
    name: '真实主机退回明文 http（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "htt' + 'p://blindrun.culiu-tech.com")!'
  },
  {
    name: '真实主机退回明文 ws（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/WebSocketService.swift',
    swift: 'let a = URL(string: "w' + 's://blindrun.culiu-tech.com/ws/blind")!'
  },
  {
    name: '真实主机走 https（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://blindrun.culiu-tech.com")!'
  },
  {
    name: '真实主机走 wss（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/WebSocketService.swift',
    swift: 'let a = URL(string: "wss://blindrun.culiu-tech.com/ws/blind")!'
  },
  {
    // 反向哨兵：证明上面两条放行不是「规则压根没跑」造成的假通过。
    name: '别的主机（原判据就该拦的那一半，仍拦）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://localhost:8080")!'
  },
  // 2026-10-31 域名切换（#621）。裸 IP 时代用子串比较没出过事，换成域名后长主机和别的子域都能穿过去。
  // 旧 IP 拼成字符串，本文件才不会变成「全库搜旧地址」的噪声。
  {
    name: '写回旧 IP（https，拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://47.114' + '.113.171")!'
  },
  {
    name: '写回旧 IP（wss，拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/WebSocketService.swift',
    swift: 'let a = URL(string: "wss://47.114' + '.113.171/ws/blind")!'
  },
  {
    name: '旧 IP 的裸字符串（没有 scheme 也拦）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/WebSocketService.swift',
    swift: 'components.host = "47.114' + '.113.171"'
  },
  {
    name: '旧 IP 只出现在注释行（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: '// 2026-10-31 之前这里是 47.114' + '.113.171\nlet a = URL(string: "https://blindrun.culiu-tech.com")!'
  },
  {
    name: '主机以备案域名开头的长主机（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://blindrun.culiu-tech.com.evil.net")!'
  },
  {
    name: '主机以备案域名结尾的别的主机（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://staging-blindrun.culiu-tech.com")!'
  },
  {
    name: '备案域名带端口（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://blindrun.culiu-tech.com:8443")!'
  },
  // 主机要按 URL 解析后比较。正则截断在 `@` 时，下面第一条的实际主机是 evil.net，却被读成备案域名。
  {
    name: '备案域名放在 userinfo 里（实际主机是别处，拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://blindrun.culiu-tech.com@evil.net")!'
  },
  {
    name: '备案域名带账号密码（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://user:pw@blindrun.culiu-tech.com")!'
  },
  {
    name: '备案域名带路径（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://blindrun.culiu-tech.com/api/orders")!'
  },
  {
    name: '文档域名开头的长主机（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://example.com.evil.net")!'
  },
  {
    name: '文档域名带路径（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://www.example.org/x")!'
  },
  {
    name: '明文地址只出现在注释里（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: '// 2026-09-08 之前这里是 htt' + 'p://blindrun.culiu-tech.com，切 https 后 ATS 例外已删\nlet a = URL(string: "https://blindrun.culiu-tech.com")!'
  },

  // token-in-userdefaults（2026-09-14）。AGENTS.md 第 8 节逐字禁令，此前零覆盖。
  // 立它的起因是 docs/ui/ui-review-checklist.md 有一条勾在**教人**这么写。
  {
    name: 'token 写进 UserDefaults（具名 key 常量，拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/AppState.swift',
    swift: 'func f() { persistence.set(token, forKey: AppConstants.UserDefaultsKeys.accessToken) }'
  },
  {
    name: 'token 写进 UserDefaults（字面量 key，拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/AppState.swift',
    swift: 'func f() { UserDefaults.standard.set(token, forKey: "accessToken") }'
  },
  {
    // 这条是整条规则的存在前提：迁移路径本身在**清除** UserDefaults 里的 Token，
    // 拦住它等于把迁移堵死，老用户升级后集体掉登录态。
    name: 'restoredToken() 的一次性迁移只读取 + 删除（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/AppState.swift',
    swift:
      'func f() -> String? {\n' +
      '  guard let legacy = persistence.string(forKey: AppConstants.UserDefaultsKeys.accessToken) else { return nil }\n' +
      '  tokenStore.save(legacy)\n' +
      '  persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.accessToken)\n' +
      '  return legacy\n}'
  },
  {
    name: '往 UserDefaults 写别的东西（放行 —— 规则只管 token）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/AppState.swift',
    swift: 'func f() { persistence.set(role.rawValue, forKey: AppConstants.UserDefaultsKeys.activeRole) }'
  },
  {
    name: 'token 存 Keychain（正解，放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/AppState.swift',
    swift: 'func f() { tokenStore.save(token) }'
  },

  // invite-code-reward-flag（2026-09-14）。契约逐字：「不要因为它是 false 就把邀请码输入框藏掉」——
  // 关着时邀请关系照样落库，藏掉会让这批用户在开关打开后永久拿不到奖励。
  // 这条是本文件里第一条带 `files` 路径闸的内容规则，所以反向用例要盖两个方向：
  // 被盯的文件里不含这个字段（规则没理由响），以及别的文件里含它（合法，声明处就在那儿）。
  {
    name: '邀请码输入框读 invitationRewardEnabled（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Role/RoleSelectionView.swift',
    swift: 'struct A { var body: some View { if flags.invitationRewardEnabled == true { inviteCodeSection } } }'
  },
  {
    name: '邀请码展示页读 invitationRewardEnabled（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Shared/InviteCodeView.swift',
    swift: 'struct A { var body: some View { if appState.features?.invitationRewardEnabled ?? true { rulesCard } } }'
  },
  {
    // 反向哨兵一：字段的声明处与 Mock 必须照常能写，否则这条规则会把契约模型本身锁死。
    name: '别的文件里出现 invitationRewardEnabled（放行 —— 证明路径闸真的在生效）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/Models/FeatureFlagsModels.swift',
    swift: 'struct FeatureFlagsResponse: Decodable { let invitationRewardEnabled: Bool? }'
  },
  {
    // 反向哨兵二：被盯的文件本身不含这个字段时必须放行，否则上面两条的「拦下」说明不了什么。
    name: '邀请码输入框不读这个开关（放行 —— 当前实现就是这样）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Role/RoleSelectionView.swift',
    swift: 'struct A { var body: some View { if showsInviteCodeField { inviteCodeField } } }'
  },
  // #502：EmergencyCoordinator 拆文件后求助状态的 setter 只能是 internal，这条替编译器拦「别处直接写」。
  {
    name: '别的文件直接写求助状态 state（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Safety/SafetyHubView.swift',
    swift: 'func f(appState: AppState) { appState.emergencyCoordinator.state = .idle }'
  },
  {
    name: '别的文件给合并计数 += 1（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/BlindRunner/BlindOrderStatusView.swift',
    swift: 'func f() { coordinator.mergedRetriggerCount += 1 }'
  },
  {
    name: '别的文件经可选链改告警字段（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Volunteer/VolunteerOrderFlowPage.swift',
    swift: 'func f() { coordinator.volunteerAlert?.isAcknowledged = true }'
  },
  {
    name: '别的文件调内部收尾方法 finish（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Safety/SafetyHubView.swift',
    swift: 'func f() { _ = appState.emergencyCoordinator.finish(.idle) }'
  },
  {
    // 反向哨兵：coordinator 自己的文件必须照常能写，否则规则一落地就锁死状态机本身。
    name: 'EmergencyCoordinator+Trigger.swift 里写 state（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Safety/EmergencyCoordinator+Trigger.swift',
    swift: 'extension EmergencyCoordinator { func f() { emergencyCoordinator.state = .idle; coordinator.mergedRetriggerCount += 1 } }'
  },
  {
    // 读要放行：界面上到处在读告警与合并计数（`== true` 不是赋值）。
    name: '别的文件只读求助状态（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Volunteer/VolunteerOrderFlowPage.swift',
    swift: 'let a = coordinator.volunteerAlert?.isAcknowledged == true\nlet b = appState.emergencyCoordinator.state == .idle\nlet c = coordinator.mergedRetriggerCount'
  },
  {
    // `state` 太常见：别的协调器写自己的 state 不能被误拦。
    name: '别的协调器写自己的 state（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/LiveEscortSessionCoordinator.swift',
    swift: 'func f() { coordinator.state = .idle }'
  },
  {
    // 视图里持有 EmergencyCoordinator 的属性多半就叫 `coordinator`（#539 审查 B1）。
    name: '持有 EmergencyCoordinator 的视图写 coordinator.state（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Safety/EmergencyCountdownView.swift',
    swift: 'struct V: View {\n    @ObservedObject var coordinator: EmergencyCoordinator\n    func f() { coordinator.state = .idle }\n}'
  },
  {
    name: '持有 EmergencyCoordinator 的视图写 coordinator.activeEvent（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Volunteer/VolunteerOrderFlowPage.swift',
    swift: 'struct V: View {\n    @ObservedObject var coordinator: EmergencyCoordinator\n    func f() { coordinator.activeEvent = nil }\n}'
  },
  {
    name: '持有 EmergencyCoordinator 的视图只读 coordinator.state（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Safety/EmergencyCountdownView.swift',
    swift: 'struct V: View {\n    @ObservedObject var coordinator: EmergencyCoordinator\n    var busy: Bool { coordinator.state == .idle || coordinator.state.isBusy }\n}'
  },
  // #451：存储型 async 闭包不标隔离 = `nonisolated(nonsending)`，经转换 thunk 时真机会交出已释放的参数（#449 的崩溃）。
  {
    // #449 原样：带 String 的请求体经闭包到服务层时已释放。
    name: '存储型 async 闭包没标隔离（拦下，#449 原样）',
    mode: 'post',
    expect: 2,
    swift: 'struct Form: View {\n    let onSubmit: (IntroCallPlanRequest, Double?) async -> Outcome\n}'
  },
  {
    name: '无参 async 闭包同样要标（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'struct Hub: View {\n    let onReload: () async -> Void\n}'
  },
  {
    name: '可选的 async 闭包（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'final class VM {\n    private var onSave: ((String) async throws -> String?)?\n}'
  },
  {
    // #540 审查 B3：可选闭包的括号里写 @Sendable，此前整条漏掉。
    name: '可选闭包括号里只写 @Sendable（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'struct Sheet: View {\n    let onX: (@Sendable () async -> Void)?\n}'
  },
  {
    name: '可选闭包括号里标了 @MainActor（放行）',
    mode: 'post',
    expect: 0,
    swift: 'struct Sheet: View {\n    let onX: (@MainActor () async -> Void)?\n}'
  },
  {
    // 只写 @Sendable 不算标了隔离：它照样是 nonisolated(nonsending)。
    name: '只写 @Sendable 的 async 闭包（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'struct Sheet: View {\n    let geocode: @Sendable (CLLocationCoordinate2D) async -> String?\n}'
  },
  {
    // 标在属性上不等于标在函数类型上：`@MainActor let` 只管谁能读这个属性。
    name: '@MainActor 写在 let 前面而不是类型上（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'struct Sheet: View {\n    @MainActor let onSave: (String) async -> String?\n}'
  },
  {
    name: '标成 @MainActor 的存储型 async 闭包（放行）',
    mode: 'post',
    expect: 0,
    swift: 'struct Sheet: View {\n    let onSave: @MainActor (String) async -> String?\n    let onCancel: @MainActor () async -> Void\n    let serverAddress: @MainActor (Int64) async -> OrderLocationAddressResponse?\n}'
  },
  {
    // 同步闭包不在这条的管辖内；init 参数标了 `@MainActor` 就放行。
    name: '同步闭包属性与 async 函数声明（放行）',
    mode: 'post',
    expect: 0,
    swift: 'struct Sheet: View {\n    let onClose: () -> Void\n    func load() async -> String? { nil }\n    init(onSave: @escaping @MainActor (String) async -> String?) {}\n}'
  },
  {
    name: '确需非 MainActor 时行尾标注（放行）',
    mode: 'post',
    expect: 0,
    swift: 'struct W {\n    let work: () async -> Void // guard:allow unannotated-async-closure 后台任务，不碰 UI\n}'
  },
  // #550：函数 / init 参数同样要标。转换 thunk 在「传参」那一刻就生成，存不存起来不是条件。
  {
    // #550 原样（通话磨合页）：非逃逸参数，实参带引用计数的服务对象。
    name: '函数参数没标隔离（拦下，#550 原样）',
    mode: 'post',
    expect: 2,
    swift: 'final class VM {\n    private func perform(_ call: (any SafetyServing, Int64) async throws -> Void) async {}\n}'
  },
  {
    // #550 原样（紧急联系人）：多行签名里单独一行的 @escaping 参数。
    name: '多行签名里的 @escaping 参数没标隔离（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'final class VM {\n    private func mutate(\n        successMessage: String,\n        operation: @escaping (AppState, Int64) async throws -> Void\n    ) async -> Bool { true }\n}'
  },
  {
    // 只写 @Sendable 不算标了隔离（与存储属性那半同一判据）。
    name: '只写 @escaping @Sendable 的参数（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C {\n    nonisolated static func run<T>(operation: @escaping @Sendable () async throws -> T) async throws -> T { try await operation() }\n}'
  },
  {
    name: 'init 参数没标隔离（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'struct Sheet: View {\n    init(onSave: @escaping (String) async -> String?) {}\n}'
  },
  {
    // 两种显式写法算标了：MainActor、离开调用方（`@concurrent`）。
    name: '参数标了 @MainActor / @concurrent（放行）',
    mode: 'post',
    expect: 0,
    swift: 'final class VM {\n    private func perform(_ call: @MainActor (any SafetyServing, Int64) async throws -> Void) async {}\n    func mutate(operation: @escaping @MainActor (AppState, Int64) async throws -> Void) async {}\n    nonisolated static func race<T>(operation: @escaping @concurrent @Sendable () async throws -> T) async throws -> T { try await operation() }\n}'
  },
  {
    // #592 审查：显式 nonisolated(nonsending) 与不写是同一个类型，传 MainActor 函数值进去照样生成 ImplicitActor thunk。
    name: '参数显式写 nonisolated(nonsending)（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C {\n    nonisolated static func run<T>(operation: nonisolated(nonsending) @escaping @Sendable () async throws -> T) async throws -> T { try await operation() }\n}'
  },
  {
    name: '存储属性显式写 nonisolated(nonsending)（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'struct Sheet: View {\n    let onSave: nonisolated(nonsending) (String) async -> String?\n}'
  },
  {
    // #592 审查 B1：同一行第二个及以后的参数只靠逗号分支命中（RunRecordHistoryView 的 monthSwitchRow 原样）。
    name: '同一行第二个参数没标隔离（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'struct V: View {\n    private func row(title: String, identifier: String, action: @escaping () async -> Void) -> some View { EmptyView() }\n}'
  },
  {
    // 先清字符串再切注释：按 `//` 一刀切会把 URL 之后的参数一起切掉。用保留域名，免得撞上「写死服务端地址」那条。
    name: '带 URL 默认值的参数后面跟着没标隔离的参数（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'final class C {\n    func f(url: String = "https://example.com", op: () async -> Void) async {}\n}'
  },
  {
    name: '字符串里的参数示例（放行）',
    mode: 'post',
    expect: 0,
    swift: 'struct S {\n    let doc = "func f(op: () async -> Void)"\n}'
  },
  {
    name: 'sending 修饰的参数没标隔离（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'final class C {\n    func f(op: sending () async -> Void) async {}\n}'
  },
  {
    name: 'inout 修饰的参数没标隔离（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'final class C {\n    func f(op: inout () async -> Void) async {}\n}'
  },
  {
    name: '@autoclosure 参数没标隔离（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'final class C {\n    func f(_ value: @autoclosure () async -> Int) async {}\n}'
  },
  {
    name: '反引号参数名没标隔离（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'final class C {\n    func f(`op`: () async -> Void) async {}\n}'
  },
  {
    // 参数那半不锚行首：行尾注释里写的示例不能被当成声明。
    name: '行尾注释里的参数示例（放行）',
    mode: 'post',
    expect: 0,
    swift: 'struct S {\n    func f() {} // 旧写法 perform(_ call: (Int) async -> Void) 已改\n}'
  },
  {
    // 同步闭包参数、传闭包字面量的调用点都不是 async 函数类型声明。
    name: '同步闭包参数与传字面量的调用点（放行）',
    mode: 'post',
    expect: 0,
    swift: 'final class VM {\n    func f(done: @escaping (Int) -> Void) {}\n    func g() async {\n        _ = try? await HomeLoadCoordinator.run(timeout: 1, operation: { try await load() })\n        await perform { safety, id in try await safety.report(id) }\n    }\n}'
  },

  // status-set-literal（2026-09-21）。全仓量出来 69 处订单状态判定有三种写法，
  // 只有穷举 switch 那一种会在后端加状态时说话，另两种静默答 false。
  //
  // 这一组用例的**分辨力**在于：不能只证明「含状态名的字面量会红」——
  // 那样把 `withinSwitchBlock` 整个删掉，用例照样全绿。所以必须有第 3、4 条
  // （迁移表放行）和第 5 条（别的枚举放行）来钉住判据本身。
  {
    name: '陪跑会话资格写成状态数组字面量（拦下 —— 这一处答 false = 跑步中不推位置）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/LiveEscortSessionCoordinator.swift',
    swift:
      'final class C {\n' +
      '  var isSessionEligible: Bool {\n' +
      '    guard let activeStatus else { return false }\n' +
      '    return [.driverEnRoute, .driverArrived, .inProgress].contains(activeStatus)\n' +
      '  }\n}'
  },
  {
    name: '视图里按状态集合决定显不显示（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/BlindRunner/BlindOrderStatusView.swift',
    swift:
      'struct V {\n' +
      '  func peerMapSection(_ order: OrderDetailResponse) -> some View {\n' +
      '    if [.driverEnRoute, .driverArrived, .inProgress].contains(order.status) { map }\n' +
      '  }\n}'
  },
  {
    // 这条与上一条的唯一差别就是外面多了一层 switch —— 它是 withinSwitchBlock 的验红点。
    // 把那个函数改成恒 false，这条立刻变红。
    name: '迁移表逐态列出后继状态（放行 —— 每一行已被外层 switch 穷举过）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/AppRealtimeCoordinator.swift',
    swift:
      'extension RunOrderStatus {\n' +
      '  func isDirectlyFollowed(by candidate: RunOrderStatus) -> Bool {\n' +
      '    switch self {\n' +
      '    case .pendingMatch:\n' +
      '      return [.pendingIntroCall, .pendingAccept, .cancelled].contains(candidate)\n' +
      '    case .pendingAccept:\n' +
      '      return [.driverEnRoute, .cancelled, .rematching].contains(candidate)\n' +
      '    default:\n' +
      '      return false\n' +
      '    }\n' +
      '  }\n}'
  },
  {
    // 迁移表可以很长：真实的 isDirectlyFollowed 里最后一个 case 距 `switch` 30 行开外。
    // 这条钉住「前向窗口必须走到函数声明为止」，把窗口改成固定 N 行就会红。
    name: '很长的迁移表，最后一行离 switch 30 行开外（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/AppRealtimeCoordinator.swift',
    swift:
      'extension RunOrderStatus {\n' +
      '  func f(_ candidate: RunOrderStatus) -> Bool {\n' +
      '    switch self {\n' +
      '    case .pendingMatch:\n' +
      '      return true\n' +
      Array.from({ length: 30 }, (_, i) => `    // 填充注释行 ${i}`).join('\n') +
      '\n    case .inProgress:\n' +
      '      return [.completed, .rematching].contains(candidate)\n' +
      '    default:\n' +
      '      return false\n' +
      '    }\n' +
      '  }\n}'
  },
  {
    // 分辨力哨兵：规则只认订单状态。去掉 ORDER_STATUS_CASES 那道判断，这条会红。
    name: '别的枚举的集合字面量（放行 —— 这条规则只管订单状态）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/Models/OrderModels.swift',
    swift: 'func f() -> Bool { return [.totalBlind, .lowVision].contains(level) }'
  },
  {
    name: '改成具名的穷举 switch 判定（正解，放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/LiveEscortSessionCoordinator.swift',
    swift:
      'final class C {\n' +
      '  var isSessionEligible: Bool {\n' +
      '    guard let activeStatus else { return false }\n' +
      '    return activeStatus.runsLiveEscortSession\n' +
      '  }\n}'
  },
  {
    // Mock 照后端演，字面量在那儿是对的 —— 但必须显式标注，不能靠路径白名单。
    name: 'Mock 侧带行尾标注的状态字面量（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/MockAPIClient.swift',
    swift:
      'final class M {\n' +
      '  func f() {\n' +
      '    let s = orders.first {\n' +
      '      [.driverEnRoute, .driverArrived, .inProgress].contains($0.status) // guard:allow status-set-literal\n' +
      '    }\n' +
      '  }\n}'
  },
  {
    // 反向哨兵：同一个 Mock 文件里**没有**标注的那一处照样要拦 ——
    // 否则「Mock 可以用字面量」就退化成「MockAPIClient.swift 整个文件豁免」。
    name: 'Mock 侧没标注的状态字面量（拦下 —— 豁免跟标注走，不跟文件走）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/MockAPIClient.swift',
    swift:
      'final class M {\n' +
      '  func f() {\n' +
      '    let s = orders.first { [.driverEnRoute, .inProgress].contains($0.status) }\n' +
      '  }\n}'
  },

  // unknown-fallback-handwritten（2026-11-08，#847）：手写的「未知值降级」解码要改用协议。
  {
    name: '新枚举手写未知值降级的 init(from:)（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/Models/NewModels.swift',
    swift:
      'enum NewKind: String, Decodable {\n' +
      '    case a = "A"\n' +
      '    case unknown = "UNKNOWN"\n' +
      '    init(from decoder: Decoder) throws {\n' +
      '        let rawValue = try decoder.singleValueContainer().decode(String.self)\n' +
      '        self = NewKind(rawValue: rawValue) ?? .unknown\n' +
      '    }\n}'
  },
  {
    // 订单状态机按 #847 不动；判据是最近的 enum 声明，不靠文件名或标注。
    name: 'RunOrderStatus 的手写降级解码（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/Models/OrderModels.swift',
    swift:
      'enum RunOrderStatus: String, Codable {\n' +
      '    case pendingMatch = "PENDING_MATCH"\n' +
      '    case unknown = "UNKNOWN"\n' +
      '    init(from decoder: Decoder) throws {\n' +
      '        let rawValue = try decoder.singleValueContainer().decode(String.self)\n' +
      '        self = RunOrderStatus(rawValue: rawValue) ?? .unknown\n' +
      '    }\n}'
  },
  {
    // 反向哨兵：RunOrderStatus 的豁免不能扩到同一文件里排在它后面的别的枚举。
    name: '同文件 RunOrderStatus 之后的另一个枚举手写降级（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/Models/OrderModels.swift',
    swift:
      'enum RunOrderStatus: String, Codable {\n' +
      '    case unknown = "UNKNOWN"\n' +
      '    init(from decoder: Decoder) throws {\n' +
      '        let rawValue = try decoder.singleValueContainer().decode(String.self)\n' +
      '        self = RunOrderStatus(rawValue: rawValue) ?? .unknown\n' +
      '    }\n}\n' +
      'enum PacePreference: String, Codable {\n' +
      '    case unknown = "UNKNOWN"\n' +
      '    init(from decoder: Decoder) throws {\n' +
      '        let rawValue = try decoder.singleValueContainer().decode(String.self)\n' +
      '        self = PacePreference(rawValue: rawValue) ?? .unknown\n' +
      '    }\n}'
  },
  {
    // `try?` 的宽容写法让非字符串也落 .unknown，和协议行为不同，不归这条管。
    name: 'try? 宽容写法的降级解码（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/Models/OrderModels.swift',
    swift:
      'enum RunRhythmSignal: String, Decodable {\n' +
      '    case unknown = "UNKNOWN"\n' +
      '    init(from decoder: Decoder) throws {\n' +
      '        let rawValue = try? decoder.singleValueContainer().decode(String.self)\n' +
      '        self = rawValue.flatMap(RunRhythmSignal.init(rawValue:)) ?? .unknown\n' +
      '    }\n}'
  },
  {
    name: '协议自己的默认实现 Self(rawValue:)（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/Models/UnknownFallbackDecodable.swift',
    swift:
      'nonisolated extension UnknownFallbackDecodable {\n' +
      '    init(from decoder: Decoder) throws {\n' +
      '        let rawValue = try decoder.singleValueContainer().decode(String.self)\n' +
      '        self = Self(rawValue: rawValue) ?? .unknown\n' +
      '    }\n}'
  },
  {
    name: '带行尾标注的手写降级解码（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/Models/NewModels.swift',
    swift:
      'enum NewKind: String, Decodable {\n' +
      '    case unknown = "UNKNOWN"\n' +
      '    init(from decoder: Decoder) throws {\n' +
      '        let rawValue = try decoder.singleValueContainer().decode(String.self)\n' +
      '        self = NewKind(rawValue: rawValue) ?? .unknown // guard:allow unknown-fallback-handwritten\n' +
      '    }\n}'
  }
];
