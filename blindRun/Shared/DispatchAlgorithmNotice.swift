import SwiftUI

// MARK: - Copy

/// 派单算法的「显著告知」文案。
///
/// **依据**：《互联网信息服务算法推荐管理规定》（四部门令第9号）**第十六条**——
/// 「算法推荐服务提供者应当**以显著方式告知用户**其提供算法推荐服务的情况，
/// 并**以适当方式公示**算法推荐服务的基本原理、目的意图和主要运行机制等。」
/// 该条**不带**「具有舆论属性或者社会动员能力」前提，对我们直接生效。
///
/// 两个动作分在两端：**「公示」由后端做**（隐私政策 §四《我们怎么给你匹配同行伙伴》，
/// 已发布），**「显著告知」只能客户端做** —— 它要求 App 里有用户看得见的地方说明这里用了算法，
/// 而不是只藏在隐私政策全文里。本文件是后者。
///
/// **文案是隐私政策 §四 的压缩版，事实一条不改，只改口径**（长句拆成可逐条听的短句）。
/// 🔴 两处口径必须与后端 §四 和 `PrivacyConsentPurpose.blindVisionProfile` 一致，改一处要三处一起改：
/// 「视力状况不参与排序」「是否带导盲犬只参与筛选不参与排序」。
///
/// 🚩 **不许写具体权重或百分比**（后端红线：公开权重等于告诉人怎么把分数刷上去，
/// 最终被挤掉的是老实排队的志愿者）。`DispatchAlgorithmNoticeTests` 会拦。
///
/// 🚩 **这一页不自动朗读**。依据 `docs/research/help-screen-autoread-and-policy-20260907.md`：
/// VoiceOver 通道下「不自动全念」不是缺陷（官方口径是「光标移进新内容区」由用户自己浏览），
/// 而自动播 >3 秒会触发 WCAG 2.2 SC 1.4.2（Level A）「必须给停止手段」——
/// 一个用户主动点进来的说明页没有理由去背那个包袱。
enum DispatchAlgorithmNoticeCopy {

    /// 订单等待页上那一行的标题。
    static let entryTitle = "匹配规则说明"

    static let entryAccessibilityHint = "查看系统怎么为你挑选陪跑志愿者"

    static let pageTitle = "怎么为你匹配志愿者"

    static let notice = "系统会自动为你挑选陪跑志愿者。这一页说明它按什么规则挑，以及哪些信息不参与。"

    /// 复用 `LegalFallbackCopy.Section`（`heading` + `bullets`）而不是另定义一个同形状的类型：
    /// 这两处的渲染规则（每条 bullet 各自成为独立 VoiceOver 焦点）是同一条合规约束，
    /// 类型分家迟早会带着渲染一起分家。
    static let sections: [LegalFallbackCopy.Section] = [
        LegalFallbackCopy.Section(
            heading: "系统为什么要排序",
            bullets: [
                "系统会把你的订单派给最可能顺利完成这次同行的志愿者：离得近、时间对得上、跑得住、过往评价好。",
                "不是随机分配，也不是先到先得。"
            ]
        ),
        LegalFallbackCopy.Section(
            heading: "系统怎么挑人",
            bullets: [
                "第一步，先筛出此刻能接的人：在线、开着接单、在这一轮的距离范围内、通过了平台资质审核、完成了必修培训。如果对方设置了可服务时间，还要求和你的订单时段有足够重叠；没设置的不会因此被排除。",
                "如果你这一单带导盲犬，只会筛选接受与导盲犬同行的志愿者。",
                "第二步，把筛出来的人排先后。看五样：离你起点多远、他的可服务时间和你的订单时间吻合到什么程度、历史评价、历史接单情况、配速匹配程度。",
                "第三步，按这个先后逐个问，每人有一段有限的应答时间。对方拒绝或者没在时间内回应，就问下一位。",
                "第四步，一轮问完还没有人接，系统会自动扩大距离范围重来，最多三轮。"
            ]
        ),
        LegalFallbackCopy.Section(
            heading: "哪些信息不参与排序",
            bullets: [
                "你的视力状况不参与排序。",
                // 后端隐私政策 §四 原文是「牵引方式偏好」；这里去掉「偏好」二字，
                // 与相邻三条保持同一句式（「你的姓名不参与排序」也没写「姓名信息」）。
                // 语义不变，而 `testNoticeCopyListsFieldsExcludedFromRanking` 断言的是
                // 「<字段>不参与排序」这个整体，多两个字就对不上。
                "你的牵引方式不参与排序。",
                "你的姓名不参与排序。",
                "你的手机号不参与排序。",
                "是否携带导盲犬只用在第一步的筛选，为的是不把你安排给不方便与导盲犬同行的人。它不影响先后次序。"
            ]
        ),
        LegalFallbackCopy.Section(
            heading: "最后两件事",
            bullets: [
                "我们不公示各个维度的具体权重。公开权重等于告诉人怎么有针对性地把自己的分数刷上去，最终被挤掉的是老实排队的志愿者，等更久的是你。",
                "排序只决定先问谁，不会对你做任何资格判定，也不决定你能不能使用这个服务。三轮都没找到人时，你可以继续等待、取消订单，或者联系客服。"
            ]
        )
    ]

    /// 组装成 `LegalFallbackDocumentView` 能直接渲染的文档。
    static var document: LegalFallbackCopy.Document {
        LegalFallbackCopy.Document(
            title: pageTitle,
            notice: notice,
            sections: sections
        )
    }
}

// MARK: - View

/// 派单规则说明页。
///
/// 渲染直接复用 `LegalFallbackDocumentView` —— 逐条 bullet 独立成为 VoiceOver 焦点这一条
/// 是合规约束不是排版偏好，两处各写一份迟早会漂移（与 `ConsentDisclosureView` 同一条理由）。
/// 页脚给隐私政策全文入口：本页是「显著告知」，权威的「公示」文本在隐私政策 §四。
struct DispatchAlgorithmNoticeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        LegalFallbackDocumentView(document: DispatchAlgorithmNoticeCopy.document) {
            legalRow(.privacyPolicy)
        }
        .task {
            // 免鉴权、只拉一次；拿不到就走内置全文，两条分支都保证「可点且有内容」。
            await appState.loadLegalLinksIfNeeded()
        }
    }

    /// 与 `PrivacyConsentGateView.legalRow` 同形：外链交给系统浏览器，
    /// 拿不到合法地址就走内置文案页，绝不出现空白页或禁用的灰按钮。
    @ViewBuilder
    private func legalRow(_ kind: LegalDocumentKind) -> some View {
        let title = "\(kind.title)全文"
        switch kind.destination(in: appState.legalLinks) {
        case .remote(let url):
            Link(destination: url) {
                legalRowLabel(title)
            }
            .accessibilityLabel(title)
            .accessibilityHint("在浏览器中打开\(kind.title)，派单说明在第四节")
        case .builtInFallback:
            NavigationLink {
                LegalFallbackDocumentView(kind: kind)
            } label: {
                legalRowLabel(title)
            }
            .accessibilityLabel(title)
            .accessibilityHint("查看\(kind.title)")
        }
    }

    private func legalRowLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .foregroundColor(AppColors.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 64)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        DispatchAlgorithmNoticeView()
            .environmentObject(AppState())
    }
}
#endif
