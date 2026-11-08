// pre 段 · Swift 写法：weak 依赖传临时对象、UI 测试敲屏幕正中、绕开 EmergencyDialer 开 URL、
// 盲人端触达低于 64pt、前台通知播报丢档位、新增 weak appState。
// 每个函数命中即 `fail()` 退出 2；没命中就返回。调用顺序由 `guard.mjs` 决定。

import { fail, nonCommentLines, readFileOrEmpty } from './common.mjs';

export function checkWeakTemporary({ filePath, body }) {
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
    ? nonCommentLines(body).find(
        (l) => WEAK_DEP_LABELS.test(l) && !l.includes('guard:allow weak-temporary')
      )
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
}

export function checkBlindTapCenter({ filePath, body }) {
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
    ? nonCommentLines(body).find(
        (l) => /\bapp\.tap\(\)/.test(l) && !l.includes('guard:allow blind-tap-center')
      )
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
}

export function checkRawOpenURL({ filePath, body }) {
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
  // 已登记：ExternalMapNavigation.swift:145、BlindBookingView.swift:1717。
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
    ? nonCommentLines(body).find(
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
}

export function checkSmallTouchTarget({ filePath, body }) {
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
  //
  // 2026-10-28 扩到 `.frame(height:)` / `.frame(width:height:)`（#527）：静态审查在盲人端扫出 19 处
  // 低于 64pt，其中删除常用地点、退出登录、语音输入麦克风都是写死的 `height: 44` / `52`，
  // 原规则只认 `minHeight`，一处也没拦到。`height:` 也大量用在装饰上（进度条、分隔线、图片），
  // 所以它只在**本行及前 8 行内出现可点控件**（Button / Link / Menu / `label: {` / onTapGesture）时才算触达目标；
  // `minHeight:` 维持原判据，不看上下文。
  const smallTargetLines = isBlindFacingSwift ? nonCommentLines(body) : [];
  const tappableNearby = /\bButton\b|\bLink\b|\bMenu\b|\blabel:\s*\{|\.onTapGesture/;
  const smallTargetLine = smallTargetLines.find((l, i) => {
    if (l.includes('guard:allow small-touch-target')) return false;
    const m = l.match(/\.frame\((?:[^)]*,\s*)?(minHeight|height):\s*(\d+(?:\.\d+)?)\b/);
    if (!m || Number(m[2]) >= 64) return false;
    if (m[1] === 'minHeight') return true;
    return smallTargetLines.slice(Math.max(0, i - 8), i + 1).some((x) => tappableNearby.test(x));
  });
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
}

export function checkBannerSpeechPriority({ filePath, body }) {
  // 7.6 前台通知的播报丢了档位（2026-11-02，#653）
  //
  // 安全通知必须走 `.alert`，否则会被轮询念的通用句切断，通话中还会被丢弃。档位在根视图那一行传进去，
  // 而根视图的 `onReceive` 单测够不着：把这个参数删掉，所有用例照样绿，真机上也只是偶发听不全。
  const bannerSpeechLine = /\/blindRun\/.*\.swift$/.test(filePath)
    ? body
        .split('\n')
        .find(
          (l) =>
            /\bspeak\(.*notification\.speechText/.test(l) &&
            !l.includes('notification.announcementPriority') &&
            !l.includes('guard:allow banner-speech-priority')
        )
    : undefined;
  if (bannerSpeechLine) {
    fail(
      'banner-speech-priority',
      `${filePath}\n  ${bannerSpeechLine.trim().slice(0, 160)}\n\n` +
        `前台通知的播报要带 \`priority: notification.announcementPriority\`：安全通知走警示档，才不会被切断或在通话中丢弃（#653）。\n` +
        `确需例外，行尾加 \`guard:allow banner-speech-priority\`。`
    );
  }
}

export function checkNewWeakAppState({ input, filePath, body }) {
  // 7.7 新增 `weak var appState`（2026-11-08，#894 试点结论）
  //
  // 两步构造（`init` 里 `ViewModel()`、`.task` 里 `configure(with: appState)`、`appState` 是 weak）
  // 会造出两类只在真机上才露馅的错：忘了 `configure` 时页面静默不做事；用例里 weak 依赖被提前释放，
  // 断言假绿（记忆 `location-service-test-seam-and-weak-viewmodel-deps` 记了 4 次）。
  // 试点 `RunRecordViewModel` 改成构造时传入窄依赖（`RunRecordDependencies`），负责人定：
  // 旧页面不批量迁，但**不再新增**这种写法。
  //
  // 只拦「变多」：Edit 比新旧片段，Write 比磁盘上的原文件。把已有的声明搬个位置不拦。
  if (!/\/blindRun\/.*\.swift$/.test(filePath)) return;
  const WEAK_APPSTATE = /\bweak\s+var\s+appState\b/;
  const count = (text) =>
    nonCommentLines(text || '').filter((l) => WEAK_APPSTATE.test(l) && !l.includes('guard:allow weak-appstate')).length;
  const before = input.new_string !== undefined ? count(input.old_string) : count(readFileOrEmpty(filePath));
  const after = count(body);
  if (after <= before) return;
  const line = nonCommentLines(body).find((l) => WEAK_APPSTATE.test(l) && !l.includes('guard:allow weak-appstate'));
  fail(
    'weak-appstate',
    `${filePath}\n  ${line.trim()}\n\n` +
      `不再新增 \`weak var appState\` + \`configure(with:)\` 的两步构造（#894）。\n` +
      `改法：构造 view model 时传入它真正要的窄依赖（协议或闭包），照 \`RunRecordDependencies\`（blindRun/Shared/RunRecordPresentation.swift）。\n` +
      `View 的 \`init\` 里拿不到 \`@EnvironmentObject\`：用一个外壳在 \`body\` 里取，再构造内层页面（例：VolunteerRunRecordView）。\n` +
      `结论与代价见 docs/review/architecture-20261108.md §6。确需例外，行尾加 \`// guard:allow weak-appstate\`。`
  );
}
