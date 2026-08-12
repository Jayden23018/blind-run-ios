import SwiftUI

// MARK: - Legal Documents Entry

/// 隐私政策 / 用户协议入口。放在「设置 → 关于」里，盲人端和志愿者端共用同一个 `AboutAidRunView`，
/// 所以这里写一份两边都覆盖。
///
/// **这是 App Store 审核 5.1.1 / 5.1.2 的阻塞项**：审核员必须能在应用内找到隐私政策，
/// 而他们是**未登录**状态 —— 所以入口不能藏在登录后的页面里，请求也不能带鉴权。
///
/// 落点由 `LegalDocumentKind.destination(in:)` 决定，两条分支都保证「可点且有内容」：
/// 后端下发了合法 http(s) 地址就开外链，否则（未配置 / 请求失败 / 地址非法）走内置文案页。
/// **绝不出现空白页、报错弹窗或禁用的灰按钮** —— 那三种都会让审核直接被拒。
struct LegalDocumentsSection: View {
    let links: LegalLinksResponse?

    var body: some View {
        Section {
            ForEach(LegalDocumentKind.allCases) { kind in
                LegalDocumentRow(kind: kind, destination: kind.destination(in: links))
            }
        } header: {
            Text("法律条款")
        }
    }
}

private struct LegalDocumentRow: View {
    let kind: LegalDocumentKind
    let destination: LegalDocumentDestination

    var body: some View {
        switch destination {
        case .remote(let url):
            // 外链交给系统浏览器：应用内 WebView 要额外处理加载失败、返回、离线，
            // 而这三种情况下审核员看到的都是空白页。系统浏览器至少会自己给出可理解的错误页。
            Link(destination: url) {
                Text(kind.title)
            }
            .accessibilityLabel(kind.title)
            .accessibilityHint("在浏览器中打开\(kind.title)")

        case .builtInFallback:
            NavigationLink(kind.title) {
                LegalFallbackDocumentView(kind: kind)
            }
            .accessibilityLabel(kind.title)
            .accessibilityHint("查看\(kind.title)")
        }
    }
}

// MARK: - Built-in Fallback Document

/// 正式法律文本上线前的内置文案页。内容来自 `LegalFallbackCopy`，只陈述应用当前真实行为。
struct LegalFallbackDocumentView: View {
    let kind: LegalDocumentKind

    private var document: LegalFallbackCopy.Document {
        LegalFallbackCopy.document(for: kind)
    }

    var body: some View {
        List {
            Section {
                Text(document.notice)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel(document.notice)
            }

            ForEach(document.sections) { section in
                Section {
                    // 每条单独成行而不是拼成一段：VoiceOver 才能逐条浏览、逐条重听。
                    // 拼成一段会被读屏当作一个整块念完，中途想回到某一条只能从头听。
                    ForEach(Array(section.bullets.enumerated()), id: \.offset) { _, bullet in
                        Text(bullet)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textPrimary)
                            .accessibilityLabel(bullet)
                    }
                } header: {
                    Text(section.heading)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .navigationTitle(document.title)
    }
}
