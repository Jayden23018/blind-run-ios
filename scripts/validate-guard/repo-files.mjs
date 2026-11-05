// `scripts/hooks/guard/repo-files.mjs` 的自测用例：归档契约、冻结文件与架构排除设置、隐私清单、高德 key、OpenAPI 运行时。
// 用例格式与运行方式见 `scripts/validate-guard.mjs`（exit 2 = 拦下，exit 0 = 放行）。

const PBXPROJ = '/x/blindRun.xcodeproj/project.pbxproj';

// 拼出来而不是写字面量：本文件自己也要过守卫，而守卫拦的就是这个键名。
const ARCH_KEY = ['EXCLUDED', 'ARCHS'].join('_');

export const cases = [
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
  }
];
