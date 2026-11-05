import SwiftUI

/// 盲人端与志愿者端共用。法律条款入口放在这里，两个角色的设置页各挂一次「关于」即可覆盖。
struct AboutAidRunView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            AppIdentitySection()
            AppFilingSection(mapApprovalNumber: AMapManager.mapContentApprovalNumber())
            GenerativeModelDisclosureSection()
            LegalDocumentsSection(links: appState.legalLinks)
        }
        .aboutPageClearsBlindSOSBar()
        .navigationTitle("关于")
        // 进页面才拉，不在启动时打这个请求：它只影响这一页，而且失败了也有回退文案。
        .task { await appState.loadLegalLinksIfNeeded() }
    }
}
