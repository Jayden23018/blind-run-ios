import SwiftUI

/// 盲人端与陪跑员端共用。法律条款入口放在这里，两个角色的设置页各挂一次「关于」即可覆盖。
/// 版式是负责人 2026-11-05 批准的定稿（#755，`docs/ui/mockups/blind-shared-pages-20261105/about-final.png`）：
/// 顶部图标、名字、版本居中，下面仍是分组列表。
struct AboutAidRunView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            AppIdentitySection()
            AppFilingSection(mapApprovalNumber: AMapManager.mapContentApprovalNumber())
            GenerativeModelDisclosureSection()
            LegalDocumentsSection(links: appState.legalLinks)
        }
        // 原来底部留的 96pt 空白是给常驻求助条让位的；求助条 #605 已删、这一页又藏了标签栏，空白一起去掉。
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏：悬浮的栏会盖住最后一行（记忆 `tab-bar-clips-the-last-line-of-secondary-pages`）。
        .toolbar(.hidden, for: .tabBar)
        // 进页面才拉，不在启动时打这个请求：它只影响这一页，而且失败了也有回退文案。
        .task { await appState.loadLegalLinksIfNeeded() }
    }
}
