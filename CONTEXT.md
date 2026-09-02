# CONTEXT.md — 领域词 ↔ 模块名

**用途只有一个**：断言「这个功能仓库里没有」之前，先在这张表里换一组同义词再搜。

2026-08 发生过实际损失：搜「注销 / deleteAccount」0 命中，据此写下「iOS 零调用点，需从头做账号注销」，
而代码里写的是「删除账户 / `deleteCurrentAccount`」—— 两端入口、两道确认、单测 UI 测试全都在。
checklist 作者与模型先后中招两次。同义词错开不是记性问题，是这张表缺失。

新增领域词时补一行，**不要写散文**。

| 领域词 | 别名 / 易搜错的写法 | 代码里的名字（类型 · 方法） | 主要文件 |
|---|---|---|---|
| 订单 | order、预约、下单、行程 | `RunOrderStatus` · `OrderDetailResponse` · `PagedOrderResponse` · `CreateOrderRequest` | `Core/Models/OrderModels.swift` · `BlindRunner/BlindBookingView.swift` · `BlindRunner/BlindOrderStatusView.swift` · `Volunteer/VolunteerOrderFlowViews.swift` |
| 派单 | dispatch、接单推送、抢单、`NEW_ORDER` | `VolunteerDispatchSummaryResponse` · `DispatchStatusRequest` · `VolunteerDispatchNotAvailableReason` · `respondToDispatch` | `Core/Models/VolunteerDispatchSummaryModels.swift` · `Volunteer/VolunteerHomeView.swift` |
| 通话磨合 | intro call、接单前通话、先聊聊、`PENDING_INTRO_CALL` | `IntroCallDecision` · `IntroCallView`（后端响应模型，不是 SwiftUI View） · `RunOrderStatus.pendingIntroCall` | `Core/Models/IntroCallModels.swift` · `Volunteer/VolunteerIntroCallView.swift` |
| 求助 | SOS、紧急、emergency、报警、一键求助 | `EmergencyCoordinator` · `EmergencyTriggerRequest` · `BlindHomeSOSMode` · `EmergencyDialer` | `Safety/SafetyModule.swift` · `Safety/EmergencyCoordinator.swift` |
| 陪跑 | escort、陪跑中、实时位置、轨迹、走散告警 | `LiveEscortSessionCoordinator` · `OrderTrackResponse` · `ESCORT_DISTANCE_ALERT` / `ESCORT_SIGNAL_LOST`（WS 事件名） | `Core/LiveEscortSessionCoordinator.swift` · `Core/Models/OrderTrackModels.swift` · `Core/AppRealtimeCoordinator.swift`（WS 事件） |
| 激励 | 积分、成就、勋章、固定搭档、邀请码、incentive | `VolunteerPointsResponse` · `VolunteerAchievementsResponse` · `PartnerStreakResponse` · `InviteCodeResponse` | `Volunteer/VolunteerPoints.swift` · `Volunteer/VolunteerAchievements.swift` · `Shared/PartnerStreaks.swift` · `Shared/InviteCode.swift` |
| 认证（登录） | auth、登录、验证码、会话、JWT、token | `AuthServing` · `AuthService` · `AuthEndpoint` · `LoginViewModel` · `AppState.restoreSession` | `Core/Services/AuthService.swift` · `Auth/LoginViewModel.swift` · `Core/AppState.swift` |
| 认证（实名） | 实名、身份核验、identity、人脸、活体 | `BlindIdentityVerificationViewModel` · `BlindVerifyStatus` · `FaceVerifyInitRequest` | `Profile/BlindIdentityVerificationView.swift` |
| 认证（资质） | 资质、证书、审核、verification、注册流程 | `VolunteerCertificateStatus` · `VolunteerRegistrationStatus` · `VolunteerVerificationStatusResponse` | `Volunteer/VolunteerCertificateUploadView.swift` · `Volunteer/VolunteerRegistrationFlowView.swift` |
| 注销账号 | 删除账户、销户、deleteAccount、closeAccount | `deleteCurrentAccount` · `DeleteAccountResponse` · `AccountDeletionViewModel` | `Core/AppState.swift` |
| 退出登录 | 登出、logout、signOut | `AppState.logout` · `LogoutResponse` · `confirmLocalOnlySignOut` | `Core/AppState.swift` |

> 「认证」在本仓库有**三个**互不相干的意思（登录 / 实名 / 资质），是最容易搜串的一个词。
> 三行分开列就是为了这个：搜「认证」命中的很可能不是你要的那一层。
