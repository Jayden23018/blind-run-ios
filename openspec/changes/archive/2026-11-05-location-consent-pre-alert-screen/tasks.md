## 1. 实现

- [x] 1.1 `PrivacyConsent+LocationPreAlert.swift`：两个位置目的的说明页标题、三条用途（只点名 `disclosures` 已有内容）、保存期限与关闭方式、朗读文本
- [x] 1.2 `LocationTrackPreAlertView`：整页说明、「查看详细说明」、唯一「继续」；系统定位已决定时才另给「不同意」；系统框的回答映射成同意 / 拒绝
- [x] 1.3 `LocationService.requestPermission(fromTrackConsentScreen:)`：说明页弹系统框时不撞「授权框不早于同意」的调试断言
- [x] 1.4 三处接入：`BlindBookingTrackConsentGate`、`VolunteerTabView.trackConsentScreen`、`ContentView.EscortTrackConsentOverlay`
- [x] 1.5 `ConsentDisclosureView` 与 `PrivacyConsentGateView` 按钮上下排、整行铺满、同意在上；去掉位置目的的小弹窗摘要
- [x] 1.6 定位用途文字按 HIG 改（主动句、说清用途、句号结尾）
- [x] 1.7 单测与 UI 测试跟随改动（按钮 identifier、弹窗朗读文本用例换目的）

## 2. 验证

- [x] 2.1 `build-for-testing` 编译通过（负责人 11-05 定：不跑真机测试，界面由负责人自己验）
- [x] 2.2 SwiftLint 棘轮通过
