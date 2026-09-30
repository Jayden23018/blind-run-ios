## 1. 措辞与版本

- [x] 1.1 `PrivacyConsent.swift`：`appLaunch` 加运动数据一条；删除账户那句补跑步记录
- [x] 1.2 `appLaunch.disclosureVersion` 1 → 2，注释写清判据与「从未对外分发」
- [x] 1.3 `LegalLinksModels.swift`：内置隐私政策补收集项、权限关闭说明、删除账户

## 2. 隐私清单

- [x] 2.1 `PrivacyInfo.xcprivacy` 加注释：CoreMotion 不在 required-reason 类别；健身数据类型归 ASC 隐私标签

## 3. 验证

- [x] 3.1 `PrivacyConsentTests`：指纹换新值并写明理由；内置政策用例加「运动与健身」「步数」
- [x] 3.2 `build-for-testing` 编译门禁通过
- [x] 3.3 `openspec validate --all --strict --no-interactive` 通过
- [x] 3.4 真机 / 可用通道跑 `PrivacyConsentTests`，或如实标注没跑
