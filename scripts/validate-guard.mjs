#!/usr/bin/env node
//
// scripts/hooks/guard.mjs 的回归测试。
//
// 为什么需要它：守卫的每条规则都是「改坏了没有任何东西会报警」的类型，
// AGENTS.md 第 1 节要求这类事落到机器归宿，这就是那个归宿。
// （2026-10-03 起 project.pbxproj 已解冻，只剩 Podfile 整文件冻结与内容级规则。）

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
    // 2026-10-03 解冻（#302）：团队号改为 QW8R457UHN，pbxproj 不再有任何行被拦。
    name: 'pbxproj 改签名团队号（已解冻，放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: { file_path: PBXPROJ, old_string: 'DEVELOPMENT_TEAM = R6PH2TFB3Q;', new_string: 'DEVELOPMENT_TEAM = QW8R457UHN;' }
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
    // 2026-10-15（#441）：CLAUDE.md 教人命令行传某个写死的团队号，三个并行会话照抄、全部
    // `No Account for Team`。团队号用 10 位占位串，拦的是「NAME=十位大写字母数字」这个形状。
    name: 'Markdown 里教人传写死的 DEVELOPMENT_TEAM=<团队号>',
    expect: 2,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/CLAUDE.md',
        old_string: 'a',
        new_string: '- 命令行跑测试要显式传 team id：`DEVELOPMENT_TEAM=ABCDE12345`'
      }
    }
  },
  {
    // 覆盖变量 AIDRUN_TEAM 同样是「会被照抄的号」，只拦 DEVELOPMENT_TEAM 会让它从旁边穿过去。
    name: 'Markdown 里教人传写死的 AIDRUN_TEAM=<团队号>',
    expect: 2,
    input: {
      tool_name: 'Write',
      tool_input: {
        file_path: '/repo/docs/some-note.md',
        content: '# 跑测\n\n```bash\nAIDRUN_TEAM=ABCDE12345 scripts/device-test.sh -only-testing:blindRunTests/Foo\n```\n'
      }
    }
  },
  {
    // 占位符、pbxproj 带空格的写法、报错原文都不是「可原样粘贴的命令行」，拦它们是误报。
    // 这条与上面两条成对：只有「该拦的拦、不该拦的放」同时成立，才说明规则的边界落在对的位置。
    name: 'Markdown 里的占位符、pbxproj 写法、报错原文（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/CLAUDE.md',
        old_string: 'a',
        new_string:
          '`AIDRUN_TEAM=<你的个人团队> scripts/device-test.sh`；pbxproj 里是 `DEVELOPMENT_TEAM = ABCDE12345;`；报错 `No Account for Team "ABCDE12345"`；守卫拦 `DEVELOPMENT_TEAM=<10 位团队号>`'
      }
    }
  },
  {
    // 引用历史原文时留的口，与其它规则的 `guard:allow <id>` 一致。
    name: 'Markdown 里写死团队号但行尾带 guard:allow（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/docs/research/some-report.md',
        old_string: 'a',
        new_string: '当时的原话：`DEVELOPMENT_TEAM=ABCDE12345` guard:allow hardcoded-team-id'
      }
    }
  },
  {
    // 脚本得有默认团队号（device-test.sh 就是），规则只管文档，不管脚本。
    name: '脚本里写团队号（放行）',
    expect: 0,
    input: {
      tool_name: 'Edit',
      tool_input: {
        file_path: '/repo/scripts/some-wrapper.sh',
        old_string: 'a',
        new_string: 'AIDRUN_TEAM=ABCDE12345 scripts/device-test.sh -only-testing:blindRunTests/Foo'
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
        // 多放一个直接字面量：matchers 为空时规则整体跳过（见 guard.mjs「一个都没读到」），
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
        // 多放一个直接字面量：matchers 为空时规则整体跳过（见 guard.mjs「一个都没读到」），
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
    swift: 'Button("重复当前状态", action: f)\n    .buttonStyle(.borderedProminent)\n    .frame(minHeight: 64)\n'
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
    swift: 'Button { f() } label: {\n    Text("重复当前状态")\n        .frame(minHeight: 64)\n}\n.buttonStyle(.borderedProminent)\n.accessibilityHint("x")\n'
  },
  {
    name: 'bordered 违规行带 guard:allow 标注（放行）',
    mode: 'post',
    expect: 0,
    swift: 'Button("x", action: f)\n    .buttonStyle(.bordered) // guard:allow bordered-frame-hit-area\n    .frame(minHeight: 64)\n'
  },

  // server-addr 的 scheme 那一半（2026-09-14 补）。
  // 原判据只看主机名，于是「主机对、scheme 退回明文」整类改动能原样穿过去 —— 实测 exit 0。
  // 下面头两条就是那个洞的形状；主机拼成字符串是为了本文件自己也过得了守卫。
  {
    name: '真实主机退回明文 http（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "htt' + 'p://47.114.113.171")!'
  },
  {
    name: '真实主机退回明文 ws（拦下）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/WebSocketService.swift',
    swift: 'let a = URL(string: "w' + 's://47.114.113.171/ws/blind")!'
  },
  {
    name: '真实主机走 https（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://47.114.113.171")!'
  },
  {
    name: '真实主机走 wss（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/WebSocketService.swift',
    swift: 'let a = URL(string: "wss://47.114.113.171/ws/blind")!'
  },
  {
    // 反向哨兵：证明上面两条放行不是「规则压根没跑」造成的假通过。
    name: '别的主机（原判据就该拦的那一半，仍拦）',
    mode: 'post',
    expect: 2,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: 'let a = URL(string: "https://localhost:8080")!'
  },
  {
    name: '明文地址只出现在注释里（放行）',
    mode: 'post',
    expect: 0,
    swiftPath: 'blindRun/Core/EnvironmentConfig.swift',
    swift: '// 2026-09-08 之前这里是 htt' + 'p://47.114.113.171，切 https 后 ATS 例外已删\nlet a = URL(string: "https://47.114.113.171")!'
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
