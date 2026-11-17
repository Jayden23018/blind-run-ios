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

    static let entryAccessibilityHint = "查看系统怎么为你挑选陪跑员"

    static let pageTitle = "怎么为你匹配陪跑员"

    static let notice = "系统会自动为你挑选陪跑员。这一页说明它按什么规则挑，以及哪些信息不参与。"

    /// 复用 `LegalFallbackCopy.Section`（`heading` + `bullets`）而不是另定义一个同形状的类型：
    /// 这两处的渲染规则（每条 bullet 各自成为独立 VoiceOver 焦点）是同一条合规约束，
    /// 类型分家迟早会带着渲染一起分家。
    static let sections: [LegalFallbackCopy.Section] = [
        LegalFallbackCopy.Section(
            heading: "系统为什么要排序",
            bullets: [
                "系统会把你的订单派给最可能顺利完成这次同行的陪跑员：离得近、时间对得上、跑得住、过往评价好。",
                "不是随机分配。系统按下面的先后，分批同时邀请。"
            ]
        ),
        // 2026-11-17（#979）：旧文案写「逐个问」「不是先到先得」，而后端一直是每批同时邀请
        // `app.dispatch.invite-batch-size`（3）人、先接先得。负责人定「改文字，保留同时邀请 3 人」，
        // 隐私政策 §四 照代码重写（后端 Jayden23018/blind-run-backend#998、法律页 Jayden23018/blindrun-legal#8），这里跟着改。
        // 🔴 3 人、60 / 15 分钟、20 分钟、累计 3 次、截止时间都是后端配置的镜像，后端改了这里要跟。
        // 「一天」是政策原文「24 小时」的说法：`SupportEntryAndVolunteerHelpTests.assertNoPromise` 拦「24 小时」「分钟内」，
        // 那是防「客服多久回复」这类承诺的，这里是派单事实，换说法不换意思。
        LegalFallbackCopy.Section(
            heading: "系统怎么挑人",
            bullets: [
                "第一步，先筛出此刻能接的人：在线、开着接单、在这一轮的距离范围内、通过了平台资质审核、完成了必修培训。如果对方设置了可服务时间，还要求和你的订单时段有足够重叠；没设置的不会因此被排除。",
                "如果此次陪跑带导盲犬，只会筛选接受与导盲犬同行的陪跑员。",
                "这些人不会被邀请：这个时段已经接了别的订单的人；和你通过电话、有一方说过不合适的人；和你之间有拉黑关系的人。",
                "第二步，把筛出来的人排先后。看五样：离你起点多远、他的可服务时间和你的订单时间吻合到什么程度、历史评价、历史接单情况、配速匹配程度。你设为固定搭档的陪跑员，排序时会额外加分。",
                "第三步，按这个先后分批邀请，每批最多 3 位，同时发出。同一批里先接先得：第一个接下的人得到这个订单，同批其他人的邀请随即作废。",
                "每条邀请有回复期限。离开跑超过一天的订单，期限是 60 分钟；不到一天的，期限是 15 分钟。期限不会晚于这个订单的派单截止时间。",
                "一批里每个人都拒绝了、超时没回复，或邀请作废了，才发下一批。",
                "第四步，排好的人都问完还没有人接，系统会自动扩大距离范围，重新筛选和排序，最多扩大到第三轮。之后在最大范围里继续找新出现的人，直到派单截止。已经问过的人不会再问。"
            ]
        ),
        LegalFallbackCopy.Section(
            heading: "需要先通话的情况",
            bullets: [
                "你和这位陪跑员之前没有通过电话、双方都说过合适，而且离开跑还有 20 分钟以上，对方就不能直接接单。他要先点「有意向」，意思是想先和你聊聊，然后你们通一次电话。",
                "你按时间段下的订单，不管之前有没有通过电话，一律先通话。",
                "通话后，你和陪跑员双方都说合适，才算接下。任何一方说不合适，或过了 20 分钟还没有结果，这次通话就算没成。",
                "同一批里第一个点「有意向」的人先和你通话，同批其他人的邀请先作废。通话没成时，订单回到派单，这些人还可能再收到邀请；没成的那一位不会再收到这个订单的邀请。",
                "这个订单的通话累计 3 次没成，订单自动结束，并告诉你结果。"
            ]
        ),
        LegalFallbackCopy.Section(
            heading: "哪些信息不参与排序",
            bullets: [
                // 后端隐私政策 §四 原文是「牵引方式偏好」；这里去掉「偏好」二字，与同句其他字段一致。
                "你的视力状况、牵引方式、姓名和手机号都不参与排序。",
                "是否携带导盲犬只用在第一步的筛选，为的是不把你安排给不方便与导盲犬同行的人。它不影响先后次序。"
            ]
        ),
        LegalFallbackCopy.Section(
            heading: "最后几件事",
            bullets: [
                "各项的具体权重不公开。",
                "派单期间你随时可以取消订单，也可以在「我的」→「联系客服」里留言。",
                "派单有截止时间。准点订单在开跑前 30 分钟；按时间段下的订单在时间段结束前 90 分钟，但不早于开始前 30 分钟。到截止时还没人接，系统会自动顺延几次；顺延用完还没人接，订单自动结束，并告诉你结果。",
                "排序只决定先问谁，不决定你能不能使用这个服务。"
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
