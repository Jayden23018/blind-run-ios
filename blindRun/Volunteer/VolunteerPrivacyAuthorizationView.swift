import SwiftUI

// MARK: - 陪跑员端「隐私与授权」（#530）

/// 陪跑员只有位置轨迹这一项单独同意（#368）。交互与盲人端（#393）同一套：管什么、当前状态、撤回按钮、结果留在页面上并朗读。
enum VolunteerPrivacyCopy {
    static let locationTitle = "接单和陪跑时的位置共享"
    static let locationPurpose = "打开接单开关后，为派单获取你的位置；接单后从出发到跑步结束，你的位置会显示给这一单的视障跑者。"
    static let locationNotGranted = "当前：没有同意。下次打开接单开关、或已接的陪跑出发前会先问你。"
    static let locationRevokeButtonTitle = "撤回位置共享的同意"
    static let locationRevokeLabel = "撤回接单和陪跑时位置共享的同意。撤回后不再获取你的位置，接单开关会关闭"
    static let revokedAndPausedDispatch = "已撤回。不再获取你的位置，接单开关已关闭；想再接单，打开开关时会重新问你。"
    static let revoked = "已撤回。不再获取你的位置；想接单时，打开接单开关会重新问你。"
    static let dispatchOffFailed = "没有撤回：接单开关没能关闭（网络或服务器暂时有问题），同意还在。请稍后再点一次「\(locationRevokeButtonTitle)」。"
}

/// 撤回的流程（抽出来只为可测）：
/// 1. 陪跑进行中拒绝（同盲人端：撤回会让对方立刻看不到位置、同意页马上再弹）。
/// 2. 接单开关开着就先在服务端关掉，**等它成功**：否则服务端一直当他在线，却再也收不到他的位置。
///    关不掉就不撤，如实说（审查 A：此前只把 PUT 丢进 Task 就照撤，失败时页面说「已关闭」而开关回滚成开着）。
/// 3. 撤回同意记录，停掉为派单要的定位（`AppState.revokeLocationTrackConsent` 内重算定位意图）。
enum VolunteerLocationConsentRevocation {
    /// - Returns: 要上屏并朗读的那一句。
    static func revoke(appState: AppState, homeViewModel: VolunteerHomeViewModel) async -> String {
        guard appState.canRevokeLocationTrackConsentNow else {
            return PrivacyAuthorizationCopy.locationBlockedDuringEscort
        }
        let wasDispatching = homeViewModel.isAvailable
        if wasDispatching {
            do {
                try await appState.orders.setDispatchStatus(wantsDispatch: false)
            } catch {
                return VolunteerPrivacyCopy.dispatchOffFailed
            }
            // 首页那份跟着服务端：`isAvailable` 的 didSet 同步 `AppState.volunteerWantsDispatch`，下一拍刷新摘要再对账。
            homeViewModel.isAvailable = false
        }
        appState.revokeLocationTrackConsent(.volunteerLocationTrack)
        return wasDispatching ? VolunteerPrivacyCopy.revokedAndPausedDispatch : VolunteerPrivacyCopy.revoked
    }
}

struct VolunteerPrivacyAuthorizationView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    /// 由 `VolunteerTabView` 注入：撤回时要关掉同一个接单开关。
    @EnvironmentObject private var homeViewModel: VolunteerHomeViewModel
    /// 同意记录是现读的计算属性，撤回后自增一次让页面重读（不拿它当 `.id`：换 id 会让读屏焦点跳回页首）。
    @State private var refreshTick = 0
    @State private var notice: String?
    @State private var isRevoking = false

    var body: some View {
        let _ = refreshTick
        let granted = appState.hasLocationTrackConsent(.volunteerLocationTrack)
        ScrollView {
            PrivacyConsentRow(
                title: VolunteerPrivacyCopy.locationTitle,
                purpose: VolunteerPrivacyCopy.locationPurpose,
                status: granted ? PrivacyAuthorizationCopy.granted : VolunteerPrivacyCopy.locationNotGranted,
                revoke: granted ? PrivacyRevokeAction(
                    title: VolunteerPrivacyCopy.locationRevokeButtonTitle,
                    label: VolunteerPrivacyCopy.locationRevokeLabel,
                    identifier: "volunteerPrivacyRevokeLocationTrackConsent",
                    isDisabled: isRevoking || homeViewModel.isUpdatingAvailability,
                    perform: revoke
                ) : nil,
                notice: notice
            )
            .padding(20)
        }
        .navigationTitle(PrivacyAuthorizationCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏：悬浮胶囊会切掉页面最后一行（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
        .toolbar(.hidden, for: .tabBar)
    }

    private func revoke() {
        isRevoking = true
        Task {
            let text = await VolunteerLocationConsentRevocation.revoke(appState: appState, homeViewModel: homeViewModel)
            isRevoking = false
            notice = text
            refreshTick += 1
            speechService.speak(text)
        }
    }
}
