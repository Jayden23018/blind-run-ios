import SwiftUI

// MARK: - 完成页「这次陪跑怎么样」

/// 评的是**这次陪跑**，不是陪跑员这个人（09-15 调研：BeMyGuide 原文
/// `rate run experience rather than particular person`）。契约仍是 1–5 的整数（`OrderReviewRequest.rating`），
/// 变的只是呈现：五档文字 + 跑步小人，不用星星（2026-10-07，`redesign-blind-runner-screens-a`）。
enum RunExperienceRating: Int, CaseIterable, Identifiable {
    case veryBad = 1
    case bad = 2
    case okay = 3
    case good = 4
    case great = 5

    var id: Int { rawValue }

    /// 屏幕与读屏共用这一个词。读屏**不念数字**：「4 分」要听的人自己换算，「顺利」不用。
    var title: String {
        switch self {
        case .veryBad: return "很差"
        case .bad: return "较差"
        case .okay: return "一般"
        case .good: return "顺利"
        case .great: return "很顺利"
        }
    }

    static let sectionTitle = "这次陪跑怎么样"
}

/// 五个按钮。默认字号横排；无障碍字号档竖排整行（五格横排在 AX 档必然截断）。
///
/// 不用 `ViewThatFits` 二选一 —— 真机审计会把整页文字判成改不了字号
/// （记忆 `viewthatfits-fails-dynamic-type-audit`），用 `AnyLayout` 按字号档直接切。
struct RunExperienceRatingPicker: View {
    @Binding var rating: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(RunExperienceRating.sectionTitle)
                .flowFont(FlowV2Fonts.title())
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))
            layout {
                ForEach(RunExperienceRating.allCases) { option in
                    optionButton(option)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindRunExperienceRating")
    }

    private func optionButton(_ option: RunExperienceRating) -> some View {
        let isSelected = rating == option.rawValue
        return Button {
            rating = option.rawValue
            HapticFeedback.play(.tick)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "figure.run")
                    .font(.system(size: 22, weight: isSelected ? .bold : .regular))
                    .accessibilityHidden(true)
                Text(option.title)
                    .flowFont(FlowV2Fonts.subhead(bold: isSelected))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(isSelected ? AppColors.Flow.bluePressed : AppColors.Flow.secondaryText)
            .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? AppColors.Flow.blueTint : AppColors.Flow.surface)
            )
            .overlay(
                // 选中态不只靠颜色：边框加粗 + 字重加粗 + 读屏「已选」三处冗余。
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected ? AppColors.Flow.accent : AppColors.Flow.ghostStroke,
                        lineWidth: isSelected ? 2.5 : 1.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("blindRunExperienceRating_\(option.rawValue)")
    }
}

#if DEBUG
#Preview("这次陪跑怎么样") {
    struct Host: View {
        @State var rating = 5
        var body: some View { RunExperienceRatingPicker(rating: $rating).padding() }
    }
    return Host()
}

#Preview("这次陪跑怎么样 · AX5") {
    struct Host: View {
        @State var rating = 4
        var body: some View { RunExperienceRatingPicker(rating: $rating).padding() }
    }
    return Host().environment(\.dynamicTypeSize, .accessibility5)
}
#endif
