## 1. 同意文案与存储

- [x] 1.1 `PrivacyConsentPurpose` 新增 `blindLocationTrack` / `volunteerLocationTrack`（version 1），文案与安卓逐字一致，指纹用例钉住
- [x] 1.2 `AppState.hasLocationTrackConsent` / `recordLocationTrackConsent`（按账号，UI 测试可跳过）与派单上报总闸

## 2. 发起前的闸

- [x] 2.1 盲人预约向导路由过闸，拒绝回首页并留下后果说明；首页无同意时不弹授权框、不开定位
- [x] 2.2 志愿者接单开关与自动恢复待命过闸，拒绝时替他关服务端开关；同意页挂在 tab 容器上
- [x] 2.3 派单定位只在开关开着且有同意时上报（根视图与首页刷新循环），志愿者订单页无同意不开定位

## 3. 同行态

- [x] 3.1 协调器没有同意不开定位、不上报，发布待回答的同意；拒绝这一单不再问并进 `.locationSharingDeclined`
- [x] 3.2 根视图盖同意页并隐藏背后的读屏树；同意时才弹系统授权框

## 4. 求助

- [x] 4.1 同行态没有同意时两端求助不附位置、不发，文案说清原因并给 120 / 110

## 5. 验证

- [ ] 5.1 单测覆盖存储、协调器、志愿者开关、求助；UI 用例覆盖两端发起前的同意页；在已提交的基线上验红
- [ ] 5.2 编译门禁 `build-for-testing` 通过；真机跑覆盖到的 suite，`passed=N failed=0`
