#!/usr/bin/env node
//
// scripts/hooks/guard.mjs 的回归测试。
//
// 为什么需要它：2026-08-05 把 project.pbxproj 从「整文件冻结」改成了「行级冻结」，
// 好让 SPM 依赖能加进去，同时把签名团队号永久锁死。这个放宽本身就是风险点 ——
// 万一哪次改动把行级判断改坏了，工程文件就等于完全敞开，而没有任何东西会报警。
// AGENTS.md 第 1 节要求这类事落到机器归宿，这就是那个归宿。

import { spawnSync } from 'node:child_process';
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
  }
];

let failed = false;

for (const testCase of cases) {
  const result = spawnSync('node', [guard, 'pre'], {
    input: JSON.stringify(testCase.input),
    encoding: 'utf8'
  });
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
