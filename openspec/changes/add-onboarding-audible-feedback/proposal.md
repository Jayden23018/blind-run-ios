## Why

2026-11-02 上线前真实使用审计（iOS #657，审计编号 B-6、B-7、B-8、B-10、B-11、B-12、B-32、V-25）发现：全盲用户第一次登录和建档时，有多处「点了没反应」，还有两处不可逆或高代价的误操作。完成标准是全盲用户闭眼能完成登录和建档。

## What Changes

- 登录：验证码发送成功要播报；验证码为空、不足 6 位、填错三种失败都要播报，并把焦点放回验证码输入框；「正在登录」提示要真的显示出来。
- 选角色：点角色卡片后先弹确认，念出所选身份和「选定后不能更改」，确认后才提交；页面上的不可更改警示放到角色卡片前面，并用正文字号。
- 个人资料：保存成功后播报「资料已保存」，并在保存按钮上方显示同一句。
- 紧急联系人表单：加「从通讯录选择」（系统联系人选择器，进程外运行，不申请通讯录权限），保留手动输入；输入框之间有「下一项」；保存提示按新增 / 编辑两种情况换说法。
- 实名认证：网络原因没提交成功时保留内存中的输入；切到后台被清空后，回到前台时上屏并播报说明；身份证号用数字键盘，键盘上方有「输入 X」；加「逐位朗读身份证号」。
- 使用帮助：加一条，教用户用 iPhone 侧边按钮的系统紧急 SOS。只教学，不做 Siri 入口。

## Capabilities

### New Capabilities
- `onboarding-audible-feedback`: 首启登录、选角色、建档、实名、紧急联系人录入的可听反馈与防误触，以及帮助页的系统 SOS 教学。

### Modified Capabilities

## Impact

- 代码：`blindRun/Auth/LoginViewModel.swift`、`blindRun/Auth/LoginView.swift`、`blindRun/Role/RoleSelectionView.swift`、`blindRun/Profile/ProfileModule.swift`、`blindRun/Profile/EmergencyContactFormView.swift`、`blindRun/Profile/BlindIdentityVerificationView.swift`、`blindRun/BlindRunner/BlindRunnerHelpView.swift`，新增联系人选择器桥接文件。
- 契约：不改，不新增接口。
- 隐私：联系人选择器不需要通讯录权限，App 只拿到用户选中的那一个人的姓名和号码；身份证号仍只在内存里，进后台照样清空。
- 不在本次范围：开跑前的系统 SOS 提醒要改 `BlindOrderStatusView.swift`，留给后续。
