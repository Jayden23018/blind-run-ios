#!/usr/bin/env node
//
// scripts/hooks/guard.mjs 的回归测试。
//
// 为什么需要它：2026-08-05 把 project.pbxproj 从「整文件冻结」改成了「行级冻结」，
// 好让 SPM 依赖能加进去，同时把签名团队号永久锁死。这个放宽本身就是风险点 ——
// 万一哪次改动把行级判断改坏了，工程文件就等于完全敞开，而没有任何东西会报警。
// AGENTS.md 第 1 节要求这类事落到机器归宿，这就是那个归宿。

import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const guard = path.join(scriptDir, 'hooks', 'guard.mjs');

const PBXPROJ = '/x/blindRun.xcodeproj/project.pbxproj';

// 拼出来而不是写字面量：本文件自己也要过守卫，而守卫拦的就是这个键名。
const ARCH_KEY = ['EXCLUDED', 'ARCHS'].join('_');

// exit 2 = 守卫拦下（Claude Code 的 PreToolUse 约定），exit 0 = 放行。
const cases = [
  {
    name: 'pbxproj 加 SPM 依赖段',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: PBXPROJ,
        old_string: '/* Begin PBXBuildFile section */',
        new_string:
          '/* Begin PBXBuildFile section */\n\t\t0A0 /* OpenAPIRuntime in Frameworks */ = {isa = PBXBuildFile; productRef = 0A1 /* OpenAPIRuntime */; };'
      }
    }
  },
  {
    name: 'pbxproj 写入签名团队号',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: { file_path: PBXPROJ, old_string: 'A', new_string: 'DEVELOPMENT_TEAM = ZW39BS8NXT;' }
    }
  },
  {
    // 只查 new_string 会漏掉这种：把那 12 行整段删掉，新内容里干干净净。
    name: 'pbxproj 删掉签名团队行',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: { file_path: PBXPROJ, old_string: 'DEVELOPMENT_TEAM = R6PH2TFB3Q;', new_string: '' }
    }
  },
  {
    name: 'pbxproj 整文件重写（Write 带全文，必然含签名团队号）',
    expect: 2,
    input: {
      tool_name: 'Write',
      tool_input: { file_path: PBXPROJ, content: '// !$*UTF8*$!\nDEVELOPMENT_TEAM = R6PH2TFB3Q;\n' }
    }
  },
  {
    name: 'Podfile 任何改动仍整文件冻结',
    expect: 2,
    input: { tool_name: 'Edit', tool_input: { file_path: '/x/Podfile', old_string: 'a', new_string: 'b' } }
  },
  {
    // 这条规则对所有构建相关文件生效，不只 pbxproj。模拟器通道靠它保命。
    name: '任何文件写入架构排除设置',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: { file_path: '/x/anything.xcconfig', old_string: 'a', new_string: ARCH_KEY + ' = arm64' }
    }
  },
  {
    // s.resources 是平铺复制到 App bundle 根目录 —— 那是主 App 自己的清单槽位。
    name: 'podspec 把 PrivacyInfo.xcprivacy 列进 s.resources',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/x/Vendor/AliyunCloudAuth/2.3.51/AliyunCloudAuth.podspec',
        old_string: 'a',
        new_string: "  s.resources = [\n    'Resources/BioAuthEngine.bundle',\n    'PrivacyInfo.xcprivacy'\n  ]"
      }
    }
  },
  {
    name: 'podspec 显式标注后放行（例如改用 s.resource_bundles）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/x/Vendor/AliyunCloudAuth/2.3.51/AliyunCloudAuth.podspec',
        old_string: 'a',
        new_string: "  s.resource_bundles = { 'AliyunCloudAuth' => ['PrivacyInfo.xcprivacy'] } # guard:allow vendor-privacy-manifest"
      }
    }
  },
  {
    // podspec 里解释「为什么不要加回来」的注释必须能写出这个文件名，否则该文件自己改不动。
    name: 'podspec 注释里提到 PrivacyInfo.xcprivacy',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/x/Vendor/AliyunCloudAuth/2.3.51/AliyunCloudAuth.podspec',
        old_string: 'a',
        new_string: '  # ⚠️ 不要把 PrivacyInfo.xcprivacy 加回 s.resources'
      }
    }
  },
  {
    // Apple 逐字写着 "may only be declared by third-party SDKs"，主 App 填了换来 ITMS-91055。
    name: '主 App 清单填第三方专用 reason code 3B52.1',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/x/blindRun/PrivacyInfo.xcprivacy',
        old_string: 'a',
        new_string: '\t\t\t<array>\n\t\t\t\t<string>3B52.1</string>\n\t\t\t</array>'
      }
    }
  },
  {
    name: '主 App 清单填第三方专用 reason code 1C8F.1',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/x/blindRun/PrivacyInfo.xcprivacy',
        old_string: 'a',
        new_string: '<string>1C8F.1</string>'
      }
    }
  },
  {
    // 主 App 该用的对应项，必须放行 —— 否则这条规则会把正确修法一起拦掉。
    name: '主 App 清单填 App 可用的 DDA9.1',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/x/blindRun/PrivacyInfo.xcprivacy',
        old_string: 'a',
        new_string: '<string>DDA9.1</string>'
      }
    }
  },
  {
    // 第三方 SDK **自己的**清单里 3B52.1 是合法的，不能连它一起拦。
    name: 'Vendor 下第三方 SDK 自己的清单填 3B52.1',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/x/Vendor/AliyunCloudAuth/2.3.50/PrivacyInfo.xcprivacy',
        old_string: 'a',
        new_string: '<string>3B52.1</string>'
      }
    }
  },
  {
    // 2026-08-06：这条规则曾拦住 AGENTS.md 第 9 节自己 —— 那节的正文就得写出这个键名。
    // 文档设不了构建设置，放行零风险；不放行的话，记录规则的文档反而改不动。
    name: 'Markdown 文档可以提及架构排除设置',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/x/AGENTS.md',
        old_string: 'a',
        new_string: `任何文件都不得写入 \`${ARCH_KEY}\` —— 真机是唯一 XCTest 通道。`
      }
    }
  },
  {
    // 同一天它还拦住了 guard.mjs 自己的注释。行尾标注是留给这类场景的口子。
    name: '代码里带 guard:allow 标注时可以提及',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/x/build-helper.sh',
        old_string: 'a',
        new_string: `echo "别设 ${ARCH_KEY}" # guard:allow excluded-archs`
      }
    }
  },
  {
    // MainActor 默认隔离 vs OpenAPI 类型的冲突已发作两次，第二次之后把生成代码
    // 搬进了独立包。这条守卫防的是有人把它又拽回 App target。
    name: 'App target 里 import OpenAPIRuntime',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Core/Foo.swift',
        old_string: 'a',
        new_string: 'import Foundation\nimport OpenAPIRuntime'
      }
    }
  },
  {
    name: '包内 import OpenAPIRuntime（正当用法，放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/Packages/AidRunAPI/Sources/AidRunAPI/Foo.swift',
        old_string: 'a',
        new_string: 'import Foundation\nimport OpenAPIRuntime'
      }
    }
  },
  {
    name: 'App target 里 import AidRunAPI（推荐用法，放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/blindRun/Core/Foo.swift',
        old_string: 'a',
        new_string: 'import Foundation\nimport AidRunAPI'
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
    // 2026-08-06：verify.yml 里两处 `if: ${{ secrets.X != '' }}` 让 workflow 连续 9 次
    // 启动失败 —— 0 个 job、0 条日志，UI 上看不出红在哪，只有邮件。这条守卫防的就是它。
    name: 'workflow step 的 if 里用 secrets',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/.github/workflows/verify.yml',
        old_string: 'a',
        new_string: "      - name: Checkout backend\n        if: ${{ secrets.BACKEND_REPO_TOKEN != '' }}"
      }
    }
  },
  {
    // job 级 if 的可用上下文更窄（只有 github/needs/vars/inputs），同样炸。
    name: 'workflow job 的 if 里用 secrets',
    expect: 2,
    input: {
      tool_name: 'Write',
      tool_input: {
        file_path: '/repo/.github/workflows/deploy.yml',
        content: "jobs:\n  ship:\n    if: ${{ secrets.DEPLOY_KEY != '' }}\n    runs-on: ubuntu-latest"
      }
    }
  },
  {
    // job 级 env 允许 secrets —— 这就是那条规则的正解，不能被误伤。
    name: 'job 级 env 里读 secrets（正解，放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/.github/workflows/verify.yml',
        old_string: 'a',
        new_string: "    env:\n      HAS_TOKEN: ${{ secrets.BACKEND_REPO_TOKEN != '' }}\n    steps:\n      - if: env.HAS_TOKEN == 'true'"
      }
    }
  },
  {
    // steps.with 也允许 secrets，token 就得这么传。
    name: 'step 的 with 里传 secrets（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/.github/workflows/verify.yml',
        old_string: 'a',
        new_string: '        with:\n          token: ${{ secrets.BACKEND_REPO_TOKEN }}'
      }
    }
  },
  {
    // 规则按路径生效：workflow 之外的 YAML 没有这个上下文限制，不该被拦。
    name: '非 workflow 的 YAML 不受此规则约束（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/fastlane/config.yml',
        old_string: 'a',
        new_string: "if: ${{ secrets.SOMETHING }}"
      }
    }
  },
  {
    // 2026-08-07：dual-device-validation.sh 与 device-test-safety.sh 里 7 处 xcodebuild
    // 一处都没传 DEVELOPMENT_TEAM —— 这两个脚本是发布验证的入口，却在任何非原开发者的
    // 机器上必然签名失败。报错是 `No Account for Team "R6PH2TFB3Q"`，字面上不提团队号
    // 从哪来，很容易被当成证书问题查半天。
    name: '脚本里打真机的 xcodebuild 没传 DEVELOPMENT_TEAM',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/scripts/dual-device-validation.sh',
        old_string: 'a',
        new_string:
          'xcodebuild test \\\n  -workspace blindRun.xcworkspace \\\n  -scheme blindRun \\\n  -destination "platform=iOS,name=${BLIND_DEVICE}"'
      }
    }
  },
  {
    // 传了就该放行。续行要先粘成一条命令再判，否则 DEVELOPMENT_TEAM 在下一行会被判成「没传」。
    name: '真机 xcodebuild 传了 DEVELOPMENT_TEAM（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/scripts/dual-device-validation.sh',
        old_string: 'a',
        new_string:
          'xcodebuild test \\\n  -destination "platform=iOS,name=${BLIND_DEVICE}" \\\n  -allowProvisioningUpdates \\\n  DEVELOPMENT_TEAM="${TEAM}"'
      }
    }
  },
  {
    // 编译门禁走 generic destination + CODE_SIGNING_ALLOWED=NO，本就不需要团队号。
    // 拦它是误报，而误报是这类守卫的死因。
    name: '编译门禁（generic destination，不签名）不该被拦',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/scripts/ci-build.sh',
        old_string: 'a',
        new_string:
          "xcodebuild -workspace blindRun.xcworkspace -scheme blindRun \\\n  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build-for-testing"
      }
    }
  },
  {
    // 规则只管 shell 脚本。文档里必须能写出反例，否则这条规则自己的说明就落不了地。
    name: 'Markdown 里出现同样的命令（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/docs/08-ios-architecture.md',
        old_string: 'a',
        new_string: 'xcodebuild test -destination "platform=iOS,name=111"'
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
  },
  {
    // 脚本顶部的用法说明常常原样贴着这条命令。注释掉的命令不会执行。
    name: 'shell 注释里贴真机 xcodebuild 命令（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/scripts/device-test.sh',
        old_string: 'a',
        new_string: '#!/usr/bin/env bash\n# 用法：xcodebuild test -destination "platform=iOS,name=111"'
      }
    }
  },
  // placeholder-promise：起因是「积分商城」占位页在仓库里躺了很久，没有任何检查说过一句话。
  //
  // sos-copy 此前**一条自测都没有** —— 规则在 guard.mjs 里躺了很久，却没人验过它拦不拦得住。
  // 2026-08-13 补上，起因是行程告知功能用「家人」这个称呼，整条从原词表旁边绕了过去。
  //
  // 这几条走 post 模式：内容级规则是从磁盘读改动后的真实文件再查的（比解析 diff 可靠），
  // 所以用 `swift` 字段声明文件内容，由下面的 runner 落成临时文件。
  {
    name: '出货代码里承诺「敬请期待」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let title = "积分商城即将上线，敬请期待" }'
  },
  {
    name: '出货代码里承诺「即将上线」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let title = "该功能即将上线" }'
  },
  {
    // 占位 UI 本身不该被禁，如实说明当前不可用才是正确写法 ——
    // 规则拦的是「会兑现」的暗示，不是占位本身。
    name: '如实说明功能不可用（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let title = "这个功能还没有开放" }'
  },
  {
    name: 'SOS 文案宣称已通知紧急联系人（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let done = "已通知紧急联系人" }'
  },
  {
    // 换个称呼就穿过去，正是这条规则最容易被绕开的方式 —— 也正是它 2026-08-13 被绕开的方式。
    name: 'SOS 文案换用「家人」称呼（同样拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let sent = "已通知家人" }'
  },
  {
    name: 'SOS 文案说「家人已收到」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let sent = "家人已收到你的行程" }'
  },
  {
    // 进行时文案必须放行 —— 否则这条规则会把唯一正确的写法也堵死，
    // 逼着后来的人去加 guard:allow，那等于把规则关掉。
    name: '进行时文案「已交给系统短信」（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let sent = "短信已交给系统，请在短信里确认已发出。" }'
  },
  {
    name: '按钮文案「把这次行程告诉家人」（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let buttonTitle = "把这次行程告诉家人" }'
  },
  {
    // 注释里引用坏文案来解释「为什么要覆盖它」是我们希望留在代码里的东西。
    name: '注释里出现坏文案（放行）',
    mode: 'post',
    expect: 0,
    swift: '// 后端 body 写的是「已通知家人」，客户端必须用自己的进行时文案覆盖它。'
  },

  // volunteer-hours-credential：成就页把时长/星级说成凭据是违规（民政部令第 67 号），
  // 不是措辞问题。这条规则最容易出的错是把注册流程里合法的「资质证书」「实名认证」
  // 一起堵死 —— 下面四条放行用例就是钉这条边界的，删了它规则会变成噪音源。
  {
    name: '成就页把时长说成「服务证明」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let title = "志愿服务证明" }'
  },
  {
    name: '成就页把时长说成「时长证书」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let title = "导出你的服务时长证书" }'
  },
  {
    name: '成就页宣称「时长已认证」（拦下）',
    mode: 'post',
    expect: 2,
    swift: 'enum C { static let subtitle = "你的服务时长已认证" }'
  },
  {
    // 注册流程里的资质证书是真实动作，与服务时长的法律效力无关。堵死它等于把这条规则关掉。
    name: '注册流程的「资质证书」（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let title = "上传资质证书" }'
  },
  {
    name: '注册流程的「实名认证」（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let title = "请先完成实名认证" }'
  },
  {
    name: '注册流程的「培训证书」（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let hint = "上传助盲陪跑相关资质或培训证书" }'
  },
  {
    // 成就页真正该用的措辞。它必须放行，否则唯一正确的写法也过不去。
    name: '成就页的展示性措辞（放行）',
    mode: 'post',
    expect: 0,
    swift: 'enum C { static let d = "以上数据来自平台记录，供你自己查看。向学校或单位申报星级需要通过全国志愿服务信息系统办理。" }'
  },

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

// post 模式的内容规则是**从磁盘读改动后的真实文件**再查的，所以这类用例得落一个真文件。
//
// 路径放在临时目录里，但要造出 `/blindRun/` 这一段 —— 守卫用它区分生产代码与测试代码
// （`guard.mjs` 末尾的路径过滤）。**不要**写进真实的 `blindRun/` 目录：本工程是文件系统
// 同步式的（`PBXFileSystemSynchronizedRootGroup`），那里多一个 .swift 会直接被编进 target，
// 用例中断时残留文件会让整个工程编译不过。
// `stale-ui-test-identifier` 是本文件里唯一的**跨文件**规则：它要同时读 blindRun/ 与
// blindRunUITests/ 才判得了。所以这类用例得先造一个最小仓库出来，再对里面某个文件发 Edit。
// 用 `/x/...` 那种假路径不行 —— 守卫读不到两侧目录时会按「宁可漏不可误」直接放行，
// 于是所有用例都变成恒过，测不出任何东西。
function materializeRepo(testCase) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-guard-repo-'));
  for (const [relative, contents] of Object.entries(testCase.repoFiles)) {
    const full = path.join(dir, relative);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, contents, 'utf8');
  }
  return {
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: path.join(dir, testCase.editPath),
        old_string: testCase.oldString ?? 'PLACEHOLDER_OLD',
        new_string: testCase.newString ?? ''
      }
    },
    cleanup: () => fs.rmSync(dir, { recursive: true, force: true })
  };
}

function materialize(testCase) {
  if (testCase.mode === 'repo') return materializeRepo(testCase);
  if (testCase.mode !== 'post') return { input: testCase.input, cleanup: () => {} };

  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'aidrun-guard-'));
  // 默认落进生产 target —— 内容级规则只查那里（post 段有一道 `/blindRun/` 过滤）。
  // 少数规则按**文件名**匹配且被查的文件住在测试 target（`a11y-audit-types` 只认
  // `AccessibilityAuditTests.swift`），这类用例用 `swiftPath` 指定相对路径。
  // 名字写错会静默变成「规则没触发」= 恒过，所以每条这样的用例都要配一条反向用例。
  const relative = testCase.swiftPath ?? path.join('blindRun', 'Shared', 'GuardSelfTest.swift');
  const filePath = path.join(dir, relative);
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, `${testCase.swift}\n`, 'utf8');

  return {
    input: { tool_name: 'Edit', tool_input: { file_path: filePath } },
    cleanup: () => fs.rmSync(dir, { recursive: true, force: true })
  };
}

let failed = false;

for (const testCase of cases) {
  const { input, cleanup } = materialize(testCase);
  // `mode` 说的是**用例怎么搭台子**（假路径 / 落一个真文件 / 造一个最小仓库），
  // 不是守卫的运行模式。只有 'post' 两者同名 —— 其余一律按 pre 跑。
  // 混用过一次：`mode: 'repo'` 被原样传成 argv，`guard.mjs` 把它归成 post，
  // 整个 pre 段（含被测的那条规则）压根没执行，两条「该拦」的用例安静地返回 0。
  const guardMode = testCase.mode === 'post' ? 'post' : 'pre';
  const result = spawnSync('node', [guard, guardMode], {
    input: JSON.stringify(input),
    encoding: 'utf8'
  });
  cleanup();
  const status = result.status ?? -1;
  if (status !== testCase.expect) {
    console.error(
      `[validate-guard] ${testCase.name}：期望 exit=${testCase.expect}，实际 exit=${status}` +
        (result.stderr ? `\n  守卫输出：${result.stderr.trim().split('\n')[0]}` : '')
    );
    failed = true;
  }
}

if (failed) {
  process.exitCode = 1;
} else {
  console.log(`[validate-guard] ${cases.length} 条守卫用例全部通过`);
}
