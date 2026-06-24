# AidRun 上线版执行计划

## 当前项目状态

AidRun 当前仓库是原生 iOS 客户端，采用 SwiftUI + MVVM，后端为仓库外云端服务 `http://47.114.113.171`，WebSocket 使用 `ws://47.114.113.171`，地图能力来自高德 iOS SDK。Mock 仍保留为离线 UI 和单元测试设施，但不能作为上线验收依据。

已经具备的上线基础：

- 手机号验证码登录、JWT 会话、角色选择与切换。
- 盲人预约、志愿者接单、出发、到达、完成、取消、紧急事件等核心订单流程。
- 高德地图桥接、定位、POI 搜索、逆地理编码、地图 marker。
- WebSocket 服务、志愿者位置上报、订单状态轮询降级。
- VoiceOver 标注、TTS 播报、语音输入入口。
- 云端后端 E2E 脚本 `scripts/cloud-e2e.mjs`。

## 上线阻塞项

以下事项必须在对真实用户发布前处理或由项目负责人书面接受风险：

- 登录验证码仍为固定 `000000`，未接入真实短信或等价验证机制。
- Token 当前存储在 `UserDefaults`，需要迁移到 Keychain。
- 真实服务地址仍为 HTTP 明文 IP，缺少 HTTPS 域名与证书。
- 志愿者认证和管理员审核仍是简化流程，真实身份审核能力需要后端合同与产品规则。
- 真实高德地图、真实定位、真实后端、WebSocket 派单必须在真机 `111` 上完成验收。
- 后端生产数据策略、测试账号策略、订单清理策略需要确认。
- App Store 隐私说明、定位/语音权限说明、无障碍验收和紧急事件责任边界需要确认。

## 真实联调测试

上线验收必须覆盖三类测试：

- **基础真机回归**：在设备 `111` 上运行完整 XCTest，验证 Mock 单元/界面流程仍稳定。
- **真实高德 smoke**：不设置 `AIDRUN_UI_TEST_DISABLE_MAP`，确认高德地图容器渲染且不会回退到 API Key 缺失占位。
- **真实后端 smoke/E2E**：使用 Demo Cloud 构建登录真实账号、创建并取消订单；使用 `scripts/cloud-e2e.mjs` 覆盖登录、资料、WebSocket、位置、派单、接单、状态流转、紧急事件。

推荐一键命令：

```bash
AIDRUN_DEVICE_NAME=111 AIDRUN_RUN_REAL_AMAP=1 AIDRUN_RUN_CLOUD_UI=1 AIDRUN_RUN_CLOUD_E2E=1 scripts/production-readiness-check.sh
```

单项命令：

```bash
node scripts/validate-docs.mjs
openspec validate remove-local-backend-use-cloud-only --strict --no-interactive
xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=111'
AIDRUN_UI_TEST_REAL_AMAP=1 xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun -destination 'platform=iOS,name=111' -only-testing:blindRunUITests/blindRunUITests/testRealAMapEnabledSmoke
AIDRUN_UI_TEST_RUN_CLOUD_SMOKE=1 xcodebuild test -workspace blindRun.xcworkspace -scheme blindRun-Demo -destination 'platform=iOS,name=111' -only-testing:blindRunUITests/blindRunUITests/testCloudBackendBlindRunnerBookingSmoke
node scripts/cloud-e2e.mjs
```

## 功能完善路线

优先级按上线风险排序：

1. 真实后端联调失败项修复：接口字段、错误码、WebSocket 消息、订单状态流转。
2. 高德地图真机渲染与定位权限异常处理。
3. Token Keychain 迁移。
4. HTTPS 域名与 ATS 策略收敛。
5. 志愿者认证、管理员审核、真实短信等生产能力接入。
6. 积分商城、支付、聊天、路线导航、实时轨迹、风险控制等扩展能力。

## 人工确认项

- 是否允许固定验证码 `000000` 随首个公开版本上线。
- 是否允许 HTTP 明文 IP 随首个公开版本上线。
- 是否已有可长期使用的真实后端测试账号和测试数据清理策略。
- 是否已有高德生产 key、Bundle ID 白名单和隐私合规材料。
- 是否需要在本仓库接入真实短信、实名认证、管理员审核等后端已具备能力。
