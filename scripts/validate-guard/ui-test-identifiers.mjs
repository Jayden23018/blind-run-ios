// `scripts/hooks/guard/ui-test-identifiers.mjs` 的自测用例：UI 测试与 App 的 accessibilityIdentifier 漂移（mode: 'repo'，造最小仓库）。
// 用例格式与运行方式见 `scripts/validate-guard.mjs`（exit 2 = 拦下，exit 0 = 放行）。

export const cases = [

  // ---- stale-ui-test-identifier（2026-08-22）----
  //
  // `30b0770` 删掉 `blindRunnerHomeAuxiliaryMap` 时漏改了一处 UI 测试，那条用例红了 8 天
  // 才被查出来 —— 本仓库 CI 跑不了 XCTest，这类漂移没有任何运行时信号。
  // 下面两个方向各有正反用例，外加三条「不许误报」的边界。
  {
    name: 'UI 测试引用 App 侧存在的 identifier（放行）',
    mode: 'repo',
    expect: 0,
    repoFiles: {
      'blindRun/Home.swift': 'Text("x").accessibilityIdentifier("blindHomeStartButton")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString: 'XCTAssertTrue(app.buttons["blindHomeStartButton"].exists)'
  },
  {
    name: 'UI 测试引用 App 侧不存在的 identifier（拦）',
    mode: 'repo',
    expect: 2,
    repoFiles: {
      'blindRun/Home.swift': 'Text("x").accessibilityIdentifier("blindHomeStartButton")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString: 'XCTAssertTrue(app.descendants(matching: .any)["blindRunnerHomeAuxiliaryMap"].exists)'
  },
  {
    // App 侧大量 identifier 是拼出来的（`"\(purpose.rawValue)Consent"`、
    // `"volunteerRegistrationStep.\(step.displayIndex)"`）。不把插值段当通配的话，
    // 光这两类就会造出十几条误报，规则当天就会被关掉。
    name: '插值拼出来的 identifier 能匹配上（放行）',
    mode: 'repo',
    expect: 0,
    repoFiles: {
      'blindRun/Step.swift':
        'Text("x").accessibilityIdentifier("volunteerRegistrationStep.\\(step.displayIndex)")\n' +
        'Text("y").accessibilityIdentifier("\\(identifierPrefix)AgreeButton")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString:
      'app.descendants(matching: .any)["volunteerRegistrationStep.1"].tap()\n' +
      'app.buttons["appLaunchConsentAgreeButton"].tap()'
  },
  {
    // #412：辅助视图把 id 当 `identifier:` 参数收下再挂修饰符，调用点只有字面量。
    // 只认 a11y 的 `identifier:`，系统 API 的同名标签（`Locale(identifier:)`）不算。
    name: 'identifier: 参数传入的 id 能匹配上（放行）',
    mode: 'repo',
    expect: 0,
    repoFiles: {
      // 配一个真 id：App 侧一个 id 都没读到时守卫按「扫描失败」整体放行，用例会变成恒过。
      'blindRun/History.swift':
        'Text("x").accessibilityIdentifier("blindHomeStartButton")\n' +
        'monthSwitchRow(title: "上个月", identifier: "runRecordHistoryPreviousMonth") { }\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString: 'XCTAssertTrue(app.buttons["runRecordHistoryPreviousMonth"].exists)'
  },
  {
    // 反向：参数写法只放行真传了的 id；没传的照拦。
    name: 'identifier: 参数里没有的 id 仍拦',
    mode: 'repo',
    expect: 2,
    repoFiles: {
      // 配一个真 id：App 侧一个 id 都没读到时守卫按「扫描失败」整体放行，用例会变成恒过。
      'blindRun/History.swift':
        'Text("x").accessibilityIdentifier("blindHomeStartButton")\n' +
        'monthSwitchRow(title: "上个月", identifier: "runRecordHistoryPreviousMonth") { }\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString: 'XCTAssertTrue(app.buttons["runRecordHistoryNextMonth"].exists)'
  },
  {
    // `Locale(identifier: "...")` 是系统 API，不能当成 a11y id 算进匹配器，
    // 否则测试引用同名字符串会被错误放行。
    name: 'Locale(identifier:) 不算 a11y id（仍拦）',
    mode: 'repo',
    expect: 2,
    repoFiles: {
      // 配一个真 id：App 侧一个 id 都没读到时守卫按「扫描失败」整体放行，用例会变成恒过。
      'blindRun/Fmt.swift':
        'let f = Locale(identifier: "enUSPosix")\nText("x").accessibilityIdentifier("blindHomeStartButton")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString: 'XCTAssertTrue(app.buttons["enUSPosix"].exists)'
  },
  {
    // 系统键盘的收键盘按钮，App 侧永远不会有。白名单只有这两个。
    name: '系统键盘按键 Done / Return（放行）',
    mode: 'repo',
    expect: 0,
    repoFiles: {
      'blindRun/Home.swift': 'Text("x").accessibilityIdentifier("blindHomeStartButton")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString: 'app.buttons["Done"].tap()\napp.buttons["Return"].tap()'
  },
  {
    // 中文文案键**不判**：它们大量是插值拼出来的 a11y label，实测误报 93%。
    // 这条用例是那个决定的锚 —— 有人以后想把中文也纳进来，会先在这里看到为什么没纳。
    name: '中文文案键不参与判定（放行）',
    mode: 'repo',
    expect: 0,
    repoFiles: {
      'blindRun/Home.swift': 'Text("x").accessibilityIdentifier("blindHomeStartButton")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString: 'XCTAssertTrue(app.staticTexts["张三，关系家人，电话139****9001，主联系人"].exists)'
  },
  {
    // 「断言这个 id 不存在」是合法用法（`blindRunUITests.swift:54` 就是），靠行内标注放行。
    name: '带 guard:allow 标注的失效 id（放行）',
    mode: 'repo',
    expect: 0,
    repoFiles: {
      'blindRun/Home.swift': 'Text("x").accessibilityIdentifier("blindHomeStartButton")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString:
      'XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "blindRunnerHomeAuxiliaryMap").count, 0) // guard:allow stale-ui-test-identifier'
  },
  {
    // 方向 B：`30b0770` 的那个形状 —— 删 App 侧 identifier，漏改测试。
    name: 'App 删掉 UI 测试还在用的 identifier（拦）',
    mode: 'repo',
    expect: 2,
    repoFiles: {
      'blindRun/Home.swift': 'Text("x").accessibilityIdentifier("blindRunnerHomeAuxiliaryMap")\n',
      'blindRunUITests/T.swift': 'app.descendants(matching: .any)["blindRunnerHomeAuxiliaryMap"].tap()\n'
    },
    editPath: 'blindRun/Home.swift',
    oldString: 'Text("x").accessibilityIdentifier("blindRunnerHomeAuxiliaryMap")',
    newString: 'Text("x").accessibilityHidden(true)'
  },
  {
    name: 'App 删掉没有测试引用的 identifier（放行）',
    mode: 'repo',
    expect: 0,
    repoFiles: {
      'blindRun/Home.swift': 'Text("x").accessibilityIdentifier("nobodyQueriesThis")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRun/Home.swift',
    oldString: 'Text("x").accessibilityIdentifier("nobodyQueriesThis")',
    newString: 'Text("x")'
  },

  // ---- #274：accessibilityIdentifier 的实参不止「单个字面量」----
  // 三元里的两支都是真实产出的 id（`FlowV2Components.swift` 的 `isCloud ? … : …`）。
  // 收集只认「括号里恰好一个字面量」时，三元那一支被判不存在，而方向 B 又会把
  // 「挪进三元」当成删除。两个方向要一起对。
  {
    name: '三元里的字面量算 App 已定义（放行）',
    mode: 'repo',
    expect: 0,
    repoFiles: {
      'blindRun/Flow.swift':
        'Text("x").accessibilityIdentifier(isCloud ? "volunteerServiceSOSButton" : "volunteerOrderHelpPill")\n' +
        // 多放一个直接字面量：matchers 为空时规则整体跳过（见 guard/ui-test-identifiers.mjs「一个都没读到」），
        // 没有它「放行」用例是恒过的，验不了红。
        'Text("y").accessibilityIdentifier("blindHomeStartButton")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString:
      'app.buttons["volunteerServiceSOSButton"].tap()\n' +
      'app.buttons["volunteerOrderHelpPill"].tap()'
  },
  {
    // 放宽后规则不能被架空：三元之外的 id 照样拦。
    name: '三元收集之外的 identifier 仍然拦',
    mode: 'repo',
    expect: 2,
    repoFiles: {
      'blindRun/Flow.swift':
        'Text("x").accessibilityIdentifier(isCloud ? "volunteerServiceSOSButton" : "volunteerOrderHelpPill")\n' +
        // 多放一个直接字面量：matchers 为空时规则整体跳过（见 guard/ui-test-identifiers.mjs「一个都没读到」），
        // 没有它「放行」用例是恒过的，验不了红。
        'Text("y").accessibilityIdentifier("blindHomeStartButton")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString: 'app.buttons["volunteerNoSuchButton"].tap()'
  },
  {
    // 方向 B：id 从直接字面量挪进了另一个文件的三元 —— 那是挪动，不是删除。
    name: 'App 把 identifier 挪进别处的三元（放行）',
    mode: 'repo',
    expect: 0,
    repoFiles: {
      'blindRun/Old.swift': 'Text("x").accessibilityIdentifier("movedIntoTernaryButton")\n',
      'blindRun/New.swift':
        'Text("x").accessibilityIdentifier(flag ? "movedIntoTernaryButton" : "otherButton")\n',
      'blindRunUITests/T.swift': 'app.buttons["movedIntoTernaryButton"].tap()\n'
    },
    editPath: 'blindRun/Old.swift',
    oldString: 'Text("x").accessibilityIdentifier("movedIntoTernaryButton")',
    newString: 'Text("x")'
  },
  {
    // 方向 B：三元收成单支，被丢掉的那一支 UI 测试还在用。
    name: 'App 三元删掉一支而 UI 测试还在用（拦）',
    mode: 'repo',
    expect: 2,
    repoFiles: {
      'blindRun/Flow.swift': 'Text("x").accessibilityIdentifier(flag ? "keptButton" : "droppedButton")\n',
      'blindRunUITests/T.swift': 'app.buttons["droppedButton"].tap()\n'
    },
    editPath: 'blindRun/Flow.swift',
    oldString: 'Text("x").accessibilityIdentifier(flag ? "keptButton" : "droppedButton")',
    newString: 'Text("x").accessibilityIdentifier("keptButton")'
  },

  // ---- 规则 8 的注释判定（2026-08-22，与本文件上面那批同一个洞）----
  //
  // 这条规则五处取 identifier 的地方原本都把注释当代码。两个方向的正确行为**相反**，
  // 所以下面成对钉：注释里的引用不算查询（不该拦），而 App 侧被注释掉的 identifier
  // 也不算还在（该拦）—— 否则把它注释掉就能让这条规则闭嘴。
  {
    name: '注释里讲「这个 id 已被删掉」（放行）',
    mode: 'repo',
    expect: 0,
    repoFiles: {
      'blindRun/Home.swift': 'Text("x").accessibilityIdentifier("blindHomeStartButton")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString: '// 这里以前是 app.buttons["blindRunnerHomeAuxiliaryMap"]，30b0770 把它删了'
  },
  {
    name: '注释解释 + 下面仍有真查询（照拦）',
    mode: 'repo',
    expect: 2,
    repoFiles: {
      'blindRun/Home.swift': 'Text("x").accessibilityIdentifier("blindHomeStartButton")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString:
      '// 这里以前是 app.buttons["blindRunnerHomeAuxiliaryMap"]\n' +
      'app.buttons["blindRunnerHomeAuxiliaryMap"].tap()'
  },
  {
    // 方向 B 的读取面：UI 测试里只剩注释提到它，就不算「还有人在用」。
    name: 'UI 测试只在注释里提到，App 侧可以删（放行）',
    mode: 'repo',
    expect: 0,
    repoFiles: {
      'blindRun/Home.swift': 'Text("x").accessibilityIdentifier("blindRunnerHomeAuxiliaryMap")\n',
      'blindRunUITests/T.swift': '// 装饰地图对读屏隐藏后，"blindRunnerHomeAuxiliaryMap" 就没了\n'
    },
    editPath: 'blindRun/Home.swift',
    oldString: 'Text("x").accessibilityIdentifier("blindRunnerHomeAuxiliaryMap")',
    newString: 'Text("x").accessibilityHidden(true)'
  },
  {
    // 反过来：App 侧只在注释里挂着的 identifier，运行时根本不存在，测试查它必然红。
    name: 'App 侧 identifier 只存在于注释里，测试还在查（拦）',
    mode: 'repo',
    expect: 2,
    repoFiles: {
      'blindRun/Home.swift':
        '// Text("x").accessibilityIdentifier("blindHomeStartButton")\n' +
        'Text("y").accessibilityIdentifier("someOtherRealId")\n',
      'blindRunUITests/T.swift': '// seed\n'
    },
    editPath: 'blindRunUITests/T.swift',
    newString: 'app.buttons["blindHomeStartButton"].tap()'
  },
  {
    // 把它注释掉而不是删掉，等于删掉 —— 否则这条规则用一个 `//` 就能被绕过。
    name: '把 App 侧 identifier 注释掉（等同删除，照拦）',
    mode: 'repo',
    expect: 2,
    repoFiles: {
      'blindRun/Home.swift': 'Text("x").accessibilityIdentifier("blindRunnerHomeAuxiliaryMap")\n',
      'blindRunUITests/T.swift': 'app.descendants(matching: .any)["blindRunnerHomeAuxiliaryMap"].tap()\n'
    },
    editPath: 'blindRun/Home.swift',
    oldString: 'Text("x").accessibilityIdentifier("blindRunnerHomeAuxiliaryMap")',
    newString: '// Text("x").accessibilityIdentifier("blindRunnerHomeAuxiliaryMap")'
  },
  {
    // 「挪了位置不算删」那条豁免同样不能被注释骗过：别处只剩注释 = 别处也没有。
    name: '别的 App 文件里只剩注释，不算「挪了位置」（照拦）',
    mode: 'repo',
    expect: 2,
    repoFiles: {
      'blindRun/Home.swift': 'Text("x").accessibilityIdentifier("sharedId")\n',
      'blindRun/Other.swift':
        '// Text("z").accessibilityIdentifier("sharedId")\n' +
        'Text("w").accessibilityIdentifier("someOtherRealId")\n',
      'blindRunUITests/T.swift': 'app.buttons["sharedId"].tap()\n'
    },
    editPath: 'blindRun/Home.swift',
    oldString: 'Text("x").accessibilityIdentifier("sharedId")',
    newString: 'Text("x")'
  }
];
