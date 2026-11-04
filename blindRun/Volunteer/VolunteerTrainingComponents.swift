import SwiftUI

// MARK: - 培训页共用的小部件

/// 培训各页的底色：灰底 + 白卡（照健康 App 的分组版式）。
///
/// 用系统分组语义色而不是新加颜色：`AppColors.swift` 不在本次改动范围（#696 在改它）。
enum TrainingSurface {
    static let page = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

/// 进度圆环。纯装饰，读屏由整张卡的 label 承担。
struct TrainingProgressRing: View {
    let fraction: Double
    @ScaledMetric(relativeTo: .title) private var diameter: CGFloat = 60

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(uiColor: .systemGray5), lineWidth: 9)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(AppColors.success, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .padding(4)
    }
}

/// 行首的彩色图标方块。颜色跟状态走（完成 = 绿、必修待学 = 橙、选修 = 蓝），
/// 状态本身由右侧胶囊的**文字**给出，颜色不是唯一区分。
struct TrainingCourseIcon: View {
    let course: TrainingCourseSummary
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.callout.weight(.semibold))
            .foregroundColor(.white)
            .frame(width: side, height: side)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// `code` 是开放枚举（后端 String），认不出的落到按必修 / 选修给的通用图标。
    private var symbol: String {
        switch course.code {
        case "GUIDE_BASICS": return "figure.run"
        case "EMERGENCY_HANDLING": return "cross.case.fill"
        case "PRE_RUN_COMMUNICATION": return "bubble.left.and.bubble.right.fill"
        default: return course.isRequired ? "graduationcap.fill" : "book.fill"
        }
    }

    private var tint: Color {
        if course.isCompleted { return AppColors.success }
        return course.isRequired ? AppColors.warning : AppColors.primary
    }
}

/// 行尾的状态胶囊：已完成 / 去学习 / +N 积分。
///
/// ⚠️ **描边，不铺浅色底**：定稿上是浅色底，但同色字压在 10% 的浅色底上，亮色绿 4.42:1、
/// 暗色蓝 4.20:1，过不了正文 4.5:1（2026-11-04 按 WCAG 公式算过）。描边版的字直接压在白卡上。
struct TrainingStatusPill: View {
    enum Status: Equatable {
        case completed
        case toLearn
        case reward(Int)

        var text: String {
            switch self {
            case .completed: return VolunteerTrainingCopy.pillCompleted
            case .toLearn: return VolunteerTrainingCopy.pillToLearn
            case .reward(let points): return VolunteerTrainingCopy.pillReward(points)
            }
        }

        var tint: Color {
            switch self {
            case .completed: return AppColors.success
            case .toLearn: return AppColors.warning
            case .reward: return AppColors.primary
            }
        }
    }

    let status: Status

    var body: some View {
        Text(status.text)
            .font(.footnote.weight(.semibold))
            .foregroundColor(status.tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(status.tint, lineWidth: 1))
    }
}

// MARK: - 答题页小部件

/// 一个选项行：文字在左（多行时左对齐）、标记在右。
struct TrainingOptionRow: View {
    enum Mark { case empty, selected, wrong }

    let text: String
    let mark: Mark
    @ScaledMetric(relativeTo: .body) private var markSide: CGFloat = 24

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                // 按钮里的多行文字默认居中：旧版选项第二行错位就是这个（current/O-quiz-2.png）
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            markView
                .frame(width: markSide, height: markSide)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    /// 选中 = 实心圆 + 白对勾、答错 = 红底白叉：形状不同，不只靠颜色。
    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .empty:
            Circle().strokeBorder(AppColors.textSecondary, lineWidth: 1.5)
        case .selected:
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Circle().fill(AppColors.primary))
        case .wrong:
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Circle().fill(AppColors.destructive))
        }
    }
}

/// 贴底的按钮栏。不透明底色 + 固定 id：内容滚到它后面时，无障碍审计按几何放过被盖住的字
/// （记忆 `opaque-bottom-bar-fakes-contrast-failure`，id 已接进 `AccessibilityAuditTests.audit` 的列表）。
struct TrainingBottomBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .readableContentColumn()
        .background(TrainingSurface.page.ignoresSafeArea(edges: .bottom))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerTrainingBottomBar")
    }
}

/// 通栏胶囊按钮（开始答题 / 提交答案 / 重答 / 完成）。负责人 2026-11-04 选 A 版。
///
/// 配色与字号同 `PrimaryButtonStyle`（白字压 `primary`：亮 6.53:1、暗 3.65:1，`title3.bold` 属大字门槛 3:1；
/// 不可用 = `textSecondary` 压 `systemGray5`），只把圆角矩形换成胶囊。高度不低于 64pt（交接书易错点 2）。
struct TrainingCapsuleButtonStyle: ButtonStyle {
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let looksDisabled = !isEnabled && !isLoading
        let ink = looksDisabled ? AppColors.textSecondary : Color.white
        configuration.label
            .font(AppFonts.primaryButton())
            .foregroundColor(ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTouchTarget.blindPrimary)
            .background(Capsule().fill(looksDisabled ? Color(uiColor: .systemGray5) : AppColors.primary))
            .contentShape(Capsule())
            // 换 `ButtonStyle` 会接管掉默认的按下反馈，不补这一行按下去屏幕上什么都不动。
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
