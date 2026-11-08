// `scripts/hooks/guard/swift-edits.mjs` 的自测用例：weak 临时对象、UI 测试敲正中、裸 open URL、盲人端触达 64pt、通知播报档位。
// 用例格式与运行方式见 `scripts/validate-guard.mjs`（exit 2 = 拦下，exit 0 = 放行）。

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

// `weak-appstate` 的 Write 用例要和磁盘上的原文件比：先落一个已有一处声明的文件。
// 路径里要有 `/blindRun/`（规则只查生产代码）；放临时目录，不碰真实工程。
const weakAppStateFixture = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-guard-weak-')), 'blindRun', 'Old.swift');
fs.mkdirSync(path.dirname(weakAppStateFixture), { recursive: true });
fs.writeFileSync(weakAppStateFixture, 'final class Old {\n    private weak var appState: AppState?\n}\n', 'utf8');

export const cases = [
  {
    // 2026-11-08（#894）：不再新增两步构造。
    name: '生产代码 Edit 新增 weak var appState（拦下）',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Foo/FooViewModel.swift',
        old_string: 'final class FooViewModel {',
        new_string: 'final class FooViewModel {\n    private weak var appState: AppState?'
      }
    }
  },
  {
    // 搬动已有声明：新旧片段各一处，数量没变多。
    name: 'Edit 搬动已有的 weak var appState（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Foo/FooViewModel.swift',
        old_string: '    private weak var appState: AppState?\n    let id: Int',
        new_string: '    let id: Int\n    private weak var appState: AppState?'
      }
    }
  },
  {
    name: 'Write 新文件里带 weak var appState（拦下）',
    expect: 2,
    input: {
      tool_name: 'Write',
      tool_input: {
        file_path: '/repo/blindRun/Foo/NewViewModel.swift',
        content: 'final class NewViewModel {\n    weak var appState: AppState?\n}'
      }
    }
  },
  {
    // 和磁盘上的原文件比：原来就有一处，重写后还是一处。
    name: 'Write 重写已有一处声明的文件（放行）',
    expect: 0,
    input: {
      tool_name: 'Write',
      tool_input: {
        file_path: weakAppStateFixture,
        content: 'final class Old {\n    // 改了别处\n    private weak var appState: AppState?\n}\n'
      }
    }
  },
  {
    name: 'Write 重写时多加一处（拦下）',
    expect: 2,
    input: {
      tool_name: 'Write',
      tool_input: {
        file_path: weakAppStateFixture,
        content: 'final class Old {\n    private weak var appState: AppState?\n}\nfinal class Other {\n    private weak var appState: AppState?\n}\n'
      }
    }
  },
  {
    name: '测试 target 里的 weak var appState（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRunTests/FooTests.swift',
        old_string: 'a',
        new_string: '    weak var appState: AppState?'
      }
    }
  },
  {
    name: 'weak var appState 行尾 guard:allow（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Foo/FooViewModel.swift',
        old_string: 'a',
        new_string: '    private weak var appState: AppState? // guard:allow weak-appstate'
      }
    }
  },
  {
    name: '注释里写 weak var appState（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Foo/FooViewModel.swift',
        old_string: 'a',
        new_string: '    // 别再写 weak var appState，构造时传依赖'
      }
    }
  },
  {
    // 2026-08-06：weak 依赖收到临时对象 = 收到 nil，测试照样绿。
    name: '把当场构造的 LocationService 传给 weak 依赖',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRunTests/FooTests.swift',
        old_string: 'a',
        new_string: 'viewModel.configureForTesting(speechService: SpeechService(), locationService: LocationService())'
      }
    }
  },
  {
    // `x ?? Type()` 是同一个陷阱换了件衣服：默认分支同样没人持有。
    name: '?? 兜底构造出的临时对象也要拦',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRunTests/FooTests.swift',
        old_string: 'a',
        new_string: 'wizard.configure(speechInputService: speechInputService ?? SpeechInputService())'
      }
    }
  },
  {
    name: '先 let 住再传（正确用法，放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRunTests/FooTests.swift',
        old_string: 'a',
        new_string: 'let location = LocationService()\nviewModel.configureForTesting(locationService: location)'
      }
    }
  },
  {
    // 显式 nil 是表达「这项依赖不存在」的正当写法，不能被这条规则逼成别的样子。
    name: '显式传 nil（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRunTests/FooTests.swift',
        old_string: 'a',
        new_string: 'viewModel.configureForTesting(locationService: nil, appState: appState)'
      }
    }
  },
  {
    // speechService 在十几个 view model 里是强引用，按标签名拦会全是误报，故意不在名单里。
    name: 'speechService 临时对象不在名单内（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRunTests/FooTests.swift',
        old_string: 'a',
        new_string: 'viewModel.configure(with: appState, speechService: SpeechService())'
      }
    }
  },
  {
    // #653：根视图的 `onReceive` 单测够不着，删掉档位只有这条守卫会报。
    name: '前台通知播报丢了档位',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/ContentView.swift',
        old_string: 'a',
        new_string: 'speechService.speak(notification.speechText)'
      }
    }
  },
  {
    name: '前台通知播报带档位（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/ContentView.swift',
        old_string: 'a',
        new_string: 'speechService.speak(notification.speechText, priority: notification.announcementPriority)'
      }
    }
  },
  {
    // 2026-08-14：误触让真机 UI 测试走到了 tel://110，只有双卡选号单挡了一下。
    // 拨号已收敛到 EmergencyDialer.dial（DEBUG 下可拦截），这条守卫防的是有人再开一个出口。
    name: '生产代码里裸的 UIApplication.shared.open（绕开拨号拦截）',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/BlindRunner/FooView.swift',
        old_string: 'a',
        new_string: '        UIApplication.shared.open(telURL)'
      }
    }
  },
  {
    name: '改走 EmergencyDialer.dial（正解，放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/BlindRunner/FooView.swift',
        old_string: 'a',
        new_string: '        EmergencyDialer.dial(telURL)'
      }
    }
  },
  {
    // 2026-08-20：志愿者端两处拨号用的是 SwiftUI 的 `@Environment(\.openURL)`，
    // 而不是 `UIApplication.shared.open` —— 同一个洞换一种拼法，从旧规则底下整整走了两处。
    // 现在按 URL 本身登记：`tel://` 只允许出现在 `EmergencyDialer.telURL` 里。
    name: 'openURL 拼 tel:// 绕开 EmergencyDialer（拦）',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Volunteer/VolunteerOrderFlowViews.swift',
        old_string: 'a',
        new_string: '                    if let url = URL(string: "tel://\\(phone)") {'
      }
    }
  },
  {
    // 地图 / 系统设置这些别的 scheme 是正当出口，标注就是那份出口清单。
    name: '别的 scheme 带 guard:allow 标注（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Map/ExternalMapNavigation.swift',
        old_string: 'a',
        new_string: '            UIApplication.shared.open(url) // guard:allow raw-open-url 地图 App scheme'
      }
    }
  },
  {
    // 拦截实现本身就住在这个文件里，拦它等于让这条规则自己改不动。
    name: 'SafetyModule.swift 里的那唯一一处（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Safety/SafetyModule.swift',
        old_string: 'a',
        new_string: '    static func dial(_ url: URL, open: (URL) -> Void = { UIApplication.shared.open($0) }) {'
      }
    }
  },
  {
    // 测试代码不受此规则约束：UI 测试自己没有 UIApplication.shared 可用，
    // 而单测里出现这行只可能是在写反例。
    name: '测试代码里出现同一行（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRunTests/FooTests.swift',
        old_string: 'a',
        new_string: '        // 别写成 UIApplication.shared.open(url)'
      }
    }
  },
  {
    // 2026-08-15：UI 审计只量逐页点名的主按钮，次级控件（跳过评价 52pt、查看大图路线 44pt、
    // 收藏地点三处 52pt）一路漏过去。盲人端 44pt 读得到按不中，表现是「点了没反应」。
    name: '盲人端次级控件只有 52pt（拦下）',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/BlindRunner/BlindOrderStatusView.swift',
        old_string: 'a',
        new_string: '                .frame(minHeight: 52)'
      }
    }
  },
  {
    name: '同一行写成 .frame(maxWidth: .infinity, minHeight: 44)（拦下）',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Shared/CompletedTrackSummaryView.swift',
        old_string: 'a',
        new_string: '                .frame(maxWidth: .infinity, minHeight: 44)'
      }
    }
  },
  {
    name: '改到 64pt（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/BlindRunner/BlindBookingView.swift',
        old_string: 'a',
        new_string: '                    .frame(minHeight: 64)'
      }
    }
  },
  // #527：`.frame(height:)` / `.frame(width:height:)` 在可点控件里也算触达目标（原规则只认 minHeight）。
  {
    name: '按钮 label 里 .frame(width: 44, height: 44)（拦下）',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/BlindRunner/BlindBookingView.swift',
        old_string: 'a',
        new_string: 'Button {\n    remove()\n} label: {\n    Image(systemName: "trash")\n        .frame(width: 44, height: 44)\n}'
      }
    }
  },
  {
    name: '按钮 label 里 .frame(height: 52)（拦下）',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Voice/VoiceTextField.swift',
        old_string: 'a',
        new_string: 'Button { start() } label: {\n    Image(systemName: "mic")\n        .frame(height: 52)\n}'
      }
    }
  },
  {
    name: 'Link 里 .frame(height: 44)（拦下）',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Core/LegalDocumentsView.swift',
        old_string: 'a',
        new_string: 'Link(destination: url) {\n    Text(title)\n        .frame(maxWidth: .infinity, height: 44)\n}'
      }
    }
  },
  {
    name: '没有可点控件的 .frame(height: 8) 进度条（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/BlindRunner/BlindOrderStatusView.swift',
        old_string: 'a',
        new_string: 'Capsule()\n    .fill(AppColors.primary)\n    .frame(height: 8)'
      }
    }
  },
  {
    name: '按钮里 .frame(width: 64, height: 64)（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Profile/ProfileModule.swift',
        old_string: 'a',
        new_string: 'Button { logout() } label: {\n    Image(systemName: "rectangle.portrait.and.arrow.right")\n        .frame(width: 64, height: 64)\n}'
      }
    }
  },
  {
    name: '按钮里 .frame(maxHeight: 40) 不是触达下限（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Profile/ProfileModule.swift',
        old_string: 'a',
        new_string: 'Button { f() } label: {\n    Image(systemName: "x")\n        .frame(maxHeight: 40)\n}'
      }
    }
  },
  {
    name: '按钮 9 行之后的 .frame(height: 8)（放行 —— 证明上下文窗口真的在生效）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/BlindRunner/BlindOrderStatusView.swift',
        old_string: 'a',
        new_string: 'Button("x") { f() }\nlet a = 1\nlet b = 2\nlet c = 3\nlet d = 4\nlet e = 5\nlet g = 6\nlet h = 7\nlet k = 8\nCapsule().frame(height: 8)'
      }
    }
  },
  {
    // 志愿者端是明眼人用的，走 Apple 的 44pt 线，不受这条约束。
    name: '志愿者端 52pt（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Volunteer/VolunteerOrderFlowViews.swift',
        old_string: 'a',
        new_string: '                .frame(minHeight: 52)'
      }
    }
  },
  {
    // 非交互元素确实用得着小数值，标注本身就是「这不是触达目标」的声明。
    name: '非触达目标带 guard:allow 标注（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/BlindRunner/BlindRunHistoryView.swift',
        old_string: 'a',
        new_string: '            .frame(minHeight: 24) // guard:allow small-touch-target 纯文本行，不可点'
      }
    }
  },
  {
    name: 'UI 测试里 app.tap() 敲屏幕正中（会点到盲人端主按钮）',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRunUITests/AccessibilityAuditTests.swift',
        old_string: 'a',
        new_string: '        app.launch()\n        app.tap()'
      }
    }
  },
  {
    name: '改敲顶部无动作区域（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRunUITests/AccessibilityAuditTests.swift',
        old_string: 'a',
        new_string:
          '        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()'
      }
    }
  },
  {
    // 显式标注过的放行 —— 否则这条规则会把「确实要点正中」的场景堵死。
    name: 'app.tap() 带 guard:allow 标注（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRunUITests/SomeOtherTests.swift',
        old_string: 'a',
        new_string: '        app.tap() // guard:allow blind-tap-center'
      }
    }
  },
  {
    // 2026-08-22：这条规则拦住了 AccessibilityAuditTests.swift 的整份 Write ——
    // 那个文件的注释里写着「不能用 app.tap()」，即守卫拦住了解释自己的那段文档。
    // 下面两条成对：注释放行、同一文件里真调用照拦，缺一条都验不出这次修的东西。
    name: '注释里写「不能用 app.tap()」（放行）',
    expect: 0,
    input: {
      tool_name: 'Write',
      tool_input: {
        file_path: '/repo/blindRunUITests/AccessibilityAuditTests.swift',
        content: '        // **不能用 `app.tap()`** —— 它敲的是屏幕正中，会点进下单页。\n'
      }
    }
  },
  {
    name: '注释解释 + 下面仍有真调用（照拦）',
    expect: 2,
    input: {
      tool_name: 'Write',
      tool_input: {
        file_path: '/repo/blindRunUITests/AccessibilityAuditTests.swift',
        content: '        // **不能用 `app.tap()`** —— 它敲的是屏幕正中。\n        app.tap()\n'
      }
    }
  },
  {
    // 同一个洞在几条规则上都有。这三条各钉一条，防止只修 blind-tap-center 一处。
    name: '注释里举反例 UIApplication.shared.open（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/BlindRunner/FooView.swift',
        old_string: 'a',
        new_string: '        // 不要写 UIApplication.shared.open(telURL)，走 EmergencyDialer.dial'
      }
    }
  },
  {
    name: '注释里举反例 .frame(minHeight: 44)（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/BlindRunner/BlindOrderStatusView.swift',
        old_string: 'a',
        new_string: '        // 这里曾经是 .frame(minHeight: 44)，盲人端按不中'
      }
    }
  },
  {
    name: '注释里举反例 appState: AppState()（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRunTests/FooTests.swift',
        old_string: 'a',
        new_string: '        // 别写成 appState: AppState()：它是 weak，出了这行就是 nil'
      }
    }
  },
  {
    // `#` 后面直接跟字母的是 Swift 编译指令，不是注释 —— 别把它当注释跳过。
    name: '#Preview 一行里塞 44pt（仍拦下）',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/BlindRunner/BlindBookingView.swift',
        old_string: 'a',
        new_string: '#Preview("Blind") { Button("x") {}.frame(minHeight: 44) }'
      }
    }
  }
];
