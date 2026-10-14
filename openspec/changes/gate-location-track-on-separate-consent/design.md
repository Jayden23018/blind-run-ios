## Context

安卓 #55 / PR #201 已定稿（含两轮安全审查）。iOS 的现状：盲人首页与志愿者 tab 进页即请求系统定位授权并开始定位；
志愿者在暂停接单时仍由根视图与首页刷新循环两条路为派单上报位置；同行定位由 `LiveEscortSessionCoordinator` 统一开关，没有同意闸。

## Goals / Non-Goals

**Goals:** 四个持续定位入口（预约、接单开关、自动恢复待命、同行态）在没有本机同意记录时先问；拒绝后不收集、不上报、求助不附位置；文案与安卓逐字一致。

**Non-Goals:** App 内撤回入口（安卓 #202 另做）；后端存同意记录；改变已同意用户的任何行为。

## Decisions

1. **存储复用 `PrivacyConsentStore`，按账号记**（`.user(userId)`）。拿不到 userId 时不读盘，只记本次登录的内存同意 —— 宁可多问，不继承别人的同意。读写入口只有 `AppState.hasLocationTrackConsent` / `recordLocationTrackConsent`。
2. **预约闸挂在路由上**（`BlindBookingTrackConsentGate` 包住 `.voiceBooking` 的目的地），不挂在按钮上：以后加的入口自动过闸。同意页没有返回按钮，读屏「返回」手势等同拒绝。
3. **志愿者同意页挂在 `VolunteerTabView`**（fullScreenCover + `PresenterAccessibilityHider`），因为自动恢复发生时人可能在任何 tab。view model 持 `trackConsentRequest`（`.turnOn` / `.resumeStandby`），系统授权框由视图在按「同意」时传进来的闭包弹。
4. **派单上报总闸 = 开关开着 ∧ 有同意**。`isAvailable` 的 `didSet` 同步到 `AppState.volunteerWantsDispatch`，根视图定时上报与首页刷新循环读同一个判据。暂停时不报也不算失败（清掉「定位暂不可用」）。
5. **同行闸在协调器里**：`evaluateSession` 在开定位之前查同意；没有就清掉运行时会话、发布 `pendingTrackConsent`。根视图 `EscortTrackConsentOverlay` 以 `@ObservedObject` 持协调器（嵌套 ObservableObject 不经 AppState 重新发布），盖同意页并隐藏背后的 UIKit 宿主树。拒绝记在内存里的订单号集合（「这一单不再问」，重启会再问一次）。健康状态新增 `.trackConsentRequired`（不出横幅）与 `.locationSharingDeclined`（横幅 + 根视图已有的状态播报）。`sendLatestLocation` 也查一次同意，作为纵深防御。
6. **协调器的同意依赖默认放行，只给直接构造它的单测用**；`AppState` 装配时换成真实的，用例钉住这一点。
7. **求助**：新增 `LocationError.locationSharingNotConsented`，`EmergencyCoordinator` 两个静态助手多一个 `sharingBlocked` 参数，盲人端三处、志愿者端两处求助入口都读 `liveEscortCoordinator.isLocationSharingBlocked`。

## Risks / Trade-offs

- 暂停接单的志愿者不再上报位置 → 后端估算出发时间用的是最后一次上报（与安卓相同取舍；文案第 5 条已如实写「最后一次上报的位置会一直保留」）。
- 根视图 overlay 在系统模态（sheet / fullScreenCover）之下：同行态切换那一刻若正弹着别的模态，同意页要等它收起才看得见（安卓审查 B 档同款）。
- 拒绝只记在内存：App 重启后同一单会再问一次。比持久化「拒绝」更保守，不会让人永远看不到这一页。
