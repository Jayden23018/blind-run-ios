// `scripts/hooks/guard/scripts-and-ci.mjs` 的自测用例：workflow if 里的 secrets、真机 xcodebuild 团队号、文档里写死团队号。
// 用例格式与运行方式见 `scripts/validate-guard.mjs`（exit 2 = 拦下，exit 0 = 放行）。

export const cases = [
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
  }
];
