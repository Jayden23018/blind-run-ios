// `scripts/hooks/guard/test-target.mjs` 的自测用例：无障碍审计类型全集、测试 helper 漏交 weak 依赖。
// 用例格式与运行方式见 `scripts/validate-guard.mjs`（exit 2 = 拦下，exit 0 = 放行）。

export const cases = [
  // weak-helper（#450）：helper 的局部依赖没随返回值交出去。上面的 weak-temporary 管第一次现场（内联临时对象），
  // 这一组管第二、三次（传的是变量名，weak-temporary 抓不到）。两次的真实代码都用检测器复验过：
  // 修复前那版被拦、修复后那版放行（FaceVerifyDeclineTests 5d64c9a5~1 → 5d64c9a5，BlindIntroCallMeetupPlanTests a32f245b → 982d8ee1）。
  {
    // 第二次现场（2026-09-08）原样：元组里有 view model 和 speech，唯独没有 appState。
    name: 'helper 的局部 AppState 没进返回的元组（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func makeViewModel(client: MockAPIClient) -> (FaceVerifyViewModel, SpeechService) {',
      '        let appState = AppState(apiClient: client)',
      '        let speech = SpeechService()',
      '        let viewModel = FaceVerifyViewModel()',
      '        viewModel.configure(appState: appState, speechService: speech)',
      '        return (viewModel, speech)',
      '    }',
      '}'
    ].join('\n')
  },
  {
    // 第三次现场（2026-10-16，PR #447）原样：Harness 装了三样，唯独没装 appState；configure 折成多行。
    name: 'helper 返回的 Harness 漏装 AppState（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private struct Harness { let viewModel: VM; let safety: FakeSafetyService; let speech: SpeechService }',
      '    private func makeHarness(_ safety: FakeSafetyService) -> Harness {',
      '        let appState = AppState(safety: safety)',
      '        let speech = SpeechService()',
      '        let viewModel = VM()',
      '        viewModel.configure(',
      '            with: appState,',
      '            speechService: speech',
      '        )',
      '        return Harness(viewModel: viewModel, safety: safety, speech: speech)',
      '    }',
      '}'
    ].join('\n')
  },
  {
    // 同一个坑换成 init：Harness 自己建 AppState、交给 view model，却没存进自己的字段。
    name: 'Harness 的 init 建了 AppState 却没存下（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'private final class Harness {',
      '    let viewModel = VM()',
      '    init() {',
      '        let location = LocationService()',
      '        viewModel.configureForTesting(locationService: location)',
      '    }',
      '}'
    ].join('\n')
  },
  {
    name: '返回值里带上 AppState（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func makeHarness(_ safety: FakeSafetyService) -> Harness {',
      '        let appState = AppState(safety: safety)',
      '        let viewModel = VM()',
      '        viewModel.configure(with: appState, speechService: SpeechService())',
      '        return Harness(',
      '            viewModel: viewModel,',
      '            appState: appState',
      '        )',
      '    }',
      '}'
    ].join('\n')
  },
  {
    // VolunteerStartConsentGateTests 现有写法：赋给测试类的属性同样算持有。
    name: '赋给测试类属性持有（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private var retainedAppState: AppState?',
      '    private func makeViewModel() -> (VM, FakeOrderService) {',
      '        let service = FakeOrderService()',
      '        let appState = AppState(orders: service)',
      '        retainedAppState = appState',
      '        let viewModel = VM()',
      '        viewModel.configure(with: appState, speechService: SpeechService(), initialOrder: nil)',
      '        return (viewModel, service)',
      '    }',
      '}'
    ].join('\n')
  },
  {
    // 测试方法本身没有返回值：局部变量活到方法结束，这正是正确写法。注释与字符串里的同形文字也不算。
    name: '测试方法里的局部 AppState、注释与字符串（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    /// 别在 helper 里写 `let appState = AppState()` 再 `return (vm, speech)`。',
      '    func testSomething() async {',
      '        let appState = AppState()',
      '        let viewModel = VM()',
      '        viewModel.configure(appState: appState, speechService: SpeechService())',
      '        XCTAssertEqual(viewModel.title, "return (vm) let appState = AppState()")',
      '    }',
      '}'
    ].join('\n')
  },
  {
    // #601 现场原样：不传参时走的是 `??` 右边那个临时对象，函数一返回就释放。
    name: 'helper 的 `X ?? 类型()` 默认值没被持有（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func makeWizard(bookingViewModel: BlindBookingViewModel? = nil) -> VoiceOrderWizard {',
      '        let bookingViewModel = bookingViewModel ?? BlindBookingViewModel()',
      '        let wizard = VoiceOrderWizard()',
      '        wizard.configure(bookingViewModel: bookingViewModel, speechService: SpeechService())',
      '        return wizard',
      '    }',
      '}'
    ].join('\n')
  },
  {
    name: 'helper 的 `X ?? 类型()` 默认值交给 teardown 持有（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func makeWizard(bookingViewModel: BlindBookingViewModel? = nil) -> VoiceOrderWizard {',
      '        let bookingViewModel = bookingViewModel ?? BlindBookingViewModel()',
      '        addTeardownBlock { _ = bookingViewModel }',
      '        let wizard = VoiceOrderWizard()',
      '        wizard.configure(bookingViewModel: bookingViewModel, speechService: SpeechService())',
      '        return wizard',
      '    }',
      '}'
    ].join('\n')
  },
  {
    // #556 现场原样：丢的是 AppState，view model 对它是 weak。
    name: '元组解构用 _ 丢掉 weak 依赖（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private static func makeHome(orders: FakeOrderService) -> (AppState, HomeViewModel) { fatalError() }',
      '    func testA() async {',
      '        let (_, viewModel) = Self.makeHome(orders: FakeOrderService())',
      '        await viewModel.load()',
      '    }',
      '}'
    ].join('\n')
  },
  {
    // #551 现场原样：丢的是 view model，协调器的 `[weak self]` 订阅没人接。夹具在 `类型.helper(` 上，带标签的元组。
    name: '元组解构用 _ 丢掉 view model（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'enum HomeFixture {',
      '    static func makeHome() -> (viewModel: VolunteerHomeViewModel, appState: AppState, speech: SpeechService) { fatalError() }',
      '}',
      'final class FooTests: XCTestCase {',
      '    func testA() {',
      '        let (_, appState, speech) = HomeFixture.makeHome()',
      '        XCTAssertNil(speech.lastSpoken ?? appState.name)',
      '    }',
      '}'
    ].join('\n')
  },
  {
    // 丢的是强持有的替身：判据要看类型，不能见 `_` 就拦。全仓有几十处这种正确写法。
    name: '元组解构用 _ 丢掉无关的一项（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func makeViewModel() -> (FaceVerifyViewModel, AppState, SpeechService) { fatalError() }',
      '    func testA() {',
      '        let (viewModel, appState, _) = makeViewModel()',
      '        XCTAssertEqual(viewModel.name, appState.name)',
      '    }',
      '}'
    ].join('\n')
  },
  {
    name: '元组解构那一行标注 guard:allow weak-helper（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func makeHome() -> (AppState, HomeViewModel) { fatalError() }',
      '    func testA() {',
      '        let (_, viewModel) = makeHome() // guard:allow weak-helper 这条就是要测 appState 释放后的早退',
      '        viewModel.load()',
      '    }',
      '}'
    ].join('\n')
  },
  {
    name: '声明行标注 guard:allow weak-helper（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func makeOrphan() -> VM {',
      '        let appState = AppState() // guard:allow weak-helper 这条就是要测 appState 释放后的早退',
      '        let viewModel = VM()',
      '        viewModel.configure(appState: appState, speechService: SpeechService())',
      '        return viewModel',
      '    }',
      '}'
    ].join('\n')
  },
  {
    // 生产代码不归这条管：App 里的局部依赖由别的对象持有，判据不成立。
    name: '同样的写法在生产 target 里（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Shared/Factory.swift',
    swift: [
      'enum Factory {',
      '    static func make() -> VM {',
      '        let appState = AppState()',
      '        let viewModel = VM()',
      '        viewModel.configure(appState: appState, speechService: SpeechService())',
      '        return viewModel',
      '    }',
      '}'
    ].join('\n')
  },
  // 2026-10-28 #543 审查补的回归：每条对应一个曾经判错的形状。
  {
    // `.init(` / `super.init(` 是调用不是声明：当成声明会把后面整个类当成它的函数体。
    name: '`.init(` 调用后面紧跟别的测试类（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class ATests: XCTestCase {',
      '    func testA() {',
      '        XCTAssertEqual(Row.caption(), .init(title: "a", detail: nil))',
      '    }',
      '}',
      'final class BTests: XCTestCase {',
      '    func testB() {',
      '        let appState = AppState()',
      '        let vm = VM()',
      '        vm.configure(appState: appState)',
      '        XCTAssertTrue(vm.ready)',
      '    }',
      '}'
    ].join('\n')
  },
  {
    name: '协议里没有函数体的声明后面紧跟测试类（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'protocol Maker { init(x: Int) }',
      'protocol Fake { func make() -> Int }',
      'final class BTests: XCTestCase {',
      '    func testB() {',
      '        let appState = AppState()',
      '        let vm = VM()',
      '        vm.configure(appState: appState)',
      '        XCTAssertTrue(vm.ready)',
      '    }',
      '}'
    ].join('\n')
  },
  {
    name: '赋给 view model 自己的 weak 属性不算持有（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func make() -> VM {',
      '        let appState = AppState()',
      '        let vm = VM()',
      '        vm.appState = appState',
      '        vm.configure(appState: appState)',
      '        return vm',
      '    }',
      '}'
    ].join('\n')
  },
  {
    // 没有它，去掉「剥离注释与字符串」这一步也没有任何用例会红（审查做过变异实测）。
    name: '注释里写着 return appState 不算交出去（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func make() -> VM {',
      '        let appState = AppState()',
      '        let vm = VM()',
      '        vm.configure(appState: appState)',
      '        // return (vm, appState)',
      '        return vm',
      '    }',
      '}'
    ].join('\n')
  },
  {
    name: '字符串里写着 return appState 不算交出去（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func make() -> VM {',
      '        let appState = AppState()',
      '        let vm = VM()',
      '        vm.configure(appState: appState)',
      '        vm.note = "return appState"',
      '        return vm',
      '    }',
      '}'
    ].join('\n')
  },
  {
    name: 'return 里只有同名实参标签不算交出去（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func makeHarness(other: AppState) -> Harness {',
      '        let appState = AppState()',
      '        let vm = VM()',
      '        vm.configure(appState: appState)',
      '        return Harness(vm: vm, appState: other)',
      '    }',
      '}'
    ].join('\n')
  },
  {
    // setUp 没有返回值，但局部变量照样在它结束时释放，而 vm 存在测试类上活到每条用例。
    name: 'setUp 里建的 AppState 没存下（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private var vm: VM!',
      '    override func setUp() {',
      '        super.setUp()',
      '        let appState = AppState()',
      '        vm = VM()',
      '        vm.configure(appState: appState)',
      '    }',
      '}'
    ].join('\n')
  },
  {
    name: 'return 跨行链式调用里带上了 AppState（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func makeHarness() -> Harness {',
      '        let appState = AppState()',
      '        let vm = VM()',
      '        vm.configure(appState: appState)',
      '        return Harness(vm: vm)',
      '            .with(appState: appState)',
      '    }',
      '}'
    ].join('\n')
  },
  {
    name: '经实参标签交给强持有的 Harness、再经局部变量返回（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunTests/FooTests.swift',
    swift: [
      'final class FooTests: XCTestCase {',
      '    private func makeHarness() -> Harness {',
      '        let appState = AppState()',
      '        let h = Harness(vm: VM(), appState: appState)',
      '        return h',
      '    }',
      '}'
    ].join('\n')
  },

  // ---- a11y-audit-types（2026-09-02）----
  //
  // 起因：`.textClipped` 与 `.trait` 从未被启用，而同文件注释宣称
  // 「审计里真正抓这件事的是 `.textClipped`」，并把三条横屏用例定为
  // 「唯一能验横屏裁切的通道」。三条用例一直是绿的 —— 绿的是另外五项。
  // 少一项不会让任何东西变红，所以只能靠静态守卫抓。
  //
  // 第 3 条是这里最关键的一条：它复现缺陷的**确切形状**（注释里有、参数列表里没有）。
  // 判据一旦退回「全文包含」，第 3 条立刻变绿而缺陷原样溜过去。
  {
    name: 'a11y 审计类型齐全（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunUITests/AccessibilityAuditTests.swift',
    swift:
      'try app.performAccessibilityAudit(for: [.contrast, .dynamicType, .elementDetection,\n' +
      '  .hitRegion, .sufficientElementDescription, .textClipped, .trait])\n'
  },
  {
    name: 'a11y 审计缺 .textClipped（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunUITests/AccessibilityAuditTests.swift',
    swift:
      'try app.performAccessibilityAudit(for: [.contrast, .dynamicType, .elementDetection,\n' +
      '  .hitRegion, .sufficientElementDescription, .trait])\n'
  },
  {
    name: 'a11y 审计类型只写在注释里（仍然拦下 —— 这就是 2026-09-02 那次的形状）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunUITests/AccessibilityAuditTests.swift',
    swift:
      '// 审计里真正抓这件事的是 .textClipped 与 .hitRegion：矮窗口下被挤扁的文本。\n' +
      'try app.performAccessibilityAudit(for: [.contrast, .dynamicType, .elementDetection,\n' +
      '  .hitRegion, .sufficientElementDescription, .trait])\n'
  },
  {
    // 2026-09-02 code review 抓到的绕过，已复现：`codeOnly` 只剥**整行**注释，
    // 于是「缺项 + 行尾一句 TODO」会让规则反向失效 —— 注释里的类型名把缺项补上了。
    // 这是本规则要堵的那个形状的最常见写法，判据退回文本级包含时这条会立刻变绿。
    name: 'a11y 审计缺项 + 行尾注释里提到缺的类型（仍然拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunUITests/AccessibilityAuditTests.swift',
    swift:
      'try app.performAccessibilityAudit(for: [.contrast, .dynamicType, .elementDetection,\n' +
      '  .hitRegion, .sufficientElementDescription]) // TODO: 补 .textClipped 和 .trait\n'
  },
  {
    // 反方向的误伤（同轮自查发现）：不传实参时默认就是 `.all`，是完全正确、
    // 甚至更好的写法（自动跟随 SDK 新增类型）。初版把它判成「七项全缺」。
    name: 'performAccessibilityAudit() 不传实参即默认 .all（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunUITests/AccessibilityAuditTests.swift',
    swift: 'try app.performAccessibilityAudit()\n'
  },
  {
    name: 'a11y 审计缺项但列表内带 guard:allow（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunUITests/AccessibilityAuditTests.swift',
    swift:
      'try app.performAccessibilityAudit(for: [.contrast, .dynamicType, .elementDetection,\n' +
      '  .hitRegion, .sufficientElementDescription, .trait // guard:allow a11y-audit-types\n' +
      '])\n'
  },
  {
    // 抑制标记的作用域：必须落在**这个列表**里。写在列表外（哪怕同一行的 `])` 之后）
    // 不算数 —— 否则在文件任意角落写一次就能让整条规则失效，这是初版的第二个洞。
    name: 'guard:allow 写在列表外（仍然拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunUITests/AccessibilityAuditTests.swift',
    swift:
      'try app.performAccessibilityAudit(for: [.contrast, .dynamicType, .elementDetection,\n' +
      '  .hitRegion, .sufficientElementDescription, .trait]) // guard:allow a11y-audit-types\n'
  },
  {
    // 同名文件里还有一堆辅助代码，不该因为「文件名对上了」就要求它含审计类型。
    name: 'AccessibilityAuditTests 里没有 audit 调用（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunUITests/AccessibilityAuditTests.swift',
    swift: 'private static let readableContentWidth: CGFloat = 700\n'
  },
  {
    // 触发面按**内容**而不是文件名：审计调用哪天拆到别的文件里，规则要照样管得住。
    // 初版按文件名匹配，新文件不叫这个名字就完全不被检查、且没有任何提示 ——
    // 那正是这条规则想避免的「少了什么但看不出来」，只是换了个面。
    name: '缺项出现在别的测试文件里（同样拦下 —— 触发面按内容不按文件名）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRunUITests/SomeOtherAuditTests.swift',
    swift: 'try app.performAccessibilityAudit(for: [.contrast])\n'
  },
  {
    // 反向哨兵：确认上面那些 expect: 0 不是「规则压根没跑」造成的假通过。
    // 无关文件里放一份缺项内容，必须**不**被这条规则碰到（它不含 audit 调用）。
    name: '无关文件不含 audit 调用（放行 —— 证明前面的放行不是恒过）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRunUITests/UnrelatedTests.swift',
    swift: 'let types = [".contrast", ".textClipped"]\n'
  }
];
