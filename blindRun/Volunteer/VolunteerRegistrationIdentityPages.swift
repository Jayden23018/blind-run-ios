import SwiftUI

// 志愿者注册第 1 步拆屏后的界面零件（#699）。
//
// 定稿 `docs/ui/mockups/volunteer-identity-20261104/identity-final.png`：照钱包「添加身份证」，
// 先说明要做哪几步，再一屏只做一件事；表单行照健康「详细信息」，字段名在左、输入在右。
// 状态与提交都在 `VolunteerRegistrationViewModel`，这里只管画。

enum RegistrationScreenMetrics {
    /// 「第 N 步，共 3 步」里的 3：身份、经历、刷脸。
    static let totalSteps = 3
}

// MARK: - Page Background

extension Color {
    /// 分组页面的底色与卡片色（健康「详细信息」同款）。系统中性色，不是新的强调色。
    static let registrationPageBackground = Color(uiColor: .systemGroupedBackground)
    static let registrationCardBackground = Color(uiColor: .secondarySystemGroupedBackground)
}

// MARK: - Step Header

/// 三段进度条，外加经历那一屏的「上一步」「跳过」。
///
/// 「第 N 步，共 3 步」写在导航栏标题上，读屏一进页面就念；进度条只是它的图形版，对读屏隐藏。
/// 「上一步」「跳过」做成页内按钮而不是 `.toolbar` 文字按钮：iOS 27 会把工具栏文字按钮包成玻璃胶囊，
/// 审计报对比度与「改不了字号」（记忆 `sheet-toolbar-text-button-fails-audit`）。
struct RegistrationStepHeader: View {
    let stepNumber: Int
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    var isBusy = false

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            if onBack != nil || onSkip != nil {
                HStack(spacing: AppSpacing.small) {
                    if let onBack {
                        Button("上一步", action: onBack)
                            .buttonStyle(TextButtonStyle(alignment: .leading))
                            .accessibilityHint("回到第 \(stepNumber - 1) 步，已填的内容会保留")
                            .accessibilityIdentifier("volunteerRegistrationBackButton")
                    }
                    if let onSkip {
                        Button("跳过", action: onSkip)
                            .buttonStyle(TextButtonStyle(alignment: .trailing))
                            .accessibilityHint("不再填写经历，直接提交已经填好的内容")
                            .accessibilityIdentifier("volunteerRegistrationSkipButton")
                    }
                }
                .disabled(isBusy)
            }

            HStack(spacing: 6) {
                ForEach(1...RegistrationScreenMetrics.totalSteps, id: \.self) { index in
                    Capsule()
                        .fill(index <= stepNumber ? AppColors.primary : Color(uiColor: .systemGray4))
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.top, onBack == nil && onSkip == nil ? AppSpacing.small : 0)
        .padding(.bottom, AppSpacing.small)
    }
}

// MARK: - Page Heading

struct RegistrationPageHeading: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xSmall) {
            Text(title)
                .font(.title.bold())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 审核被拒的原因（身份、人脸各一处）。红字不是唯一信号：原因文本本身就说清了被拒。
struct RegistrationRejectionNotice: View {
    let text: String
    let identifier: String

    var body: some View {
        Text(text)
            .font(AppFonts.body())
            .foregroundColor(AppColors.destructive)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(identifier)
    }
}

// MARK: - Grouped Card

/// 白色圆角分组卡片。行与行之间的分隔线由调用方用 `RegistrationRowDivider` 插。
struct RegistrationGroupCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity)
        .background(Color.registrationCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.medium))
    }
}

struct RegistrationRowDivider: View {
    var body: some View {
        Divider().padding(.leading, 16)
    }
}

// MARK: - Form Rows

/// 字段名在左、输入在右的一行。辅助功能字号下改成上下排：并排时输入框会被挤到只剩一两个字宽。
struct RegistrationTextFieldRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let identifier: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var capitalizesCharacters = false
    /// 经历这类自由文本可以折行；姓名、证件号、手机号只占一行。
    var allowsMultipleLines = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 76
    @FocusState private var isEditing: Bool

    var body: some View {
        let stacksVertically = dynamicTypeSize.isAccessibilitySize
        let layout = stacksVertically
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: AppSpacing.xSmall))
            : AnyLayout(HStackLayout(alignment: .center, spacing: AppSpacing.medium))
        layout {
            // 读屏念的是输入框自己的标签，这一行字只给眼睛看，免得同一个字段名念两遍。
            Text(title)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .frame(width: stacksVertically ? nil : labelWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
            field
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(capitalizesCharacters ? .characters : .never)
                .autocorrectionDisabled()
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityLabel(title)
                .accessibilityHint(placeholder)
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 16)
        .padding(.top, stacksVertically ? AppSpacing.medium : 0)
    }

    @ViewBuilder
    private var field: some View {
        if allowsMultipleLines {
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...4)
        } else {
            // 可折行：单行 `TextField` 被真机审计判 `Text clipped`（#699 姓名、身份证号；同 `VoiceTextField`）。
            // 回车不插换行：去掉换行并收起键盘，等于原来单行框的回车。
            TextField(placeholder, text: $text, axis: .vertical)
                .lineLimit(1...3)
                .focused($isEditing)
                .onChange(of: text) { newText in
                    let result = VoiceTextFieldReturn.apply(to: newText, allowsLineBreaks: false, isTyping: isEditing)
                    guard result.text != newText else { return }
                    text = result.text
                    if result.submitted { isEditing = false }
                }
        }
    }
}

struct RegistrationToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let identifier: String

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
        }
        .tint(AppColors.success)
        .padding(.horizontal, 16)
        .frame(minHeight: AppTouchTarget.blindPrimary - 8)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Intro Page

/// 说明页：三步一览。不放表单，也不发任何请求。
struct VolunteerRegistrationIntroContent: View {
    @ScaledMetric(relativeTo: .largeTitle) private var iconTileSize: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: iconTileSize * 0.5, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: iconTileSize, height: iconTileSize)
                .background(AppColors.primarySolidSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.large))
                .accessibilityHidden(true)

            RegistrationPageHeading(
                title: "先确认是你本人",
                subtitle: "陪跑员要实名，跑者和家属才放心。"
            )

            RegistrationGroupCard {
                RegistrationIntroStepRow(number: 1, title: "填写姓名和身份证号", detail: "身份证号不会保存在这台手机上")
                RegistrationRowDivider()
                RegistrationIntroStepRow(number: 2, title: "写几句陪跑经历", detail: "选填，可以跳过")
                RegistrationRowDivider()
                RegistrationIntroStepRow(number: 3, title: "刷脸确认是本人", detail: "摘掉帽子、口罩和墨镜")
            }
        }
    }
}

private struct RegistrationIntroStepRow: View {
    let number: Int
    let title: String
    let detail: String
    @ScaledMetric(relativeTo: .headline) private var badgeSize: CGFloat = 34

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.medium) {
            // 圈里是白色序号：底色用 `primarySolidSurface`，暗色下白字 8.08:1；`primary` 暗色只有 3.65:1。
            Text("\(number)")
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: badgeSize, height: badgeSize)
                .background(Circle().fill(AppColors.primarySolidSurface))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, AppSpacing.medium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("第 \(number) 步，\(title)。\(detail)")
    }
}

// MARK: - Face Page

/// 刷脸页上半部：大图标 + 三条拍摄提示（钱包自拍前的提示）。按钮与原有状态提示在调用方。
struct VolunteerFaceVerifyTipsContent: View {
    @ScaledMetric(relativeTo: .largeTitle) private var circleSize: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            RegistrationPageHeading(title: "刷脸确认是本人", subtitle: nil)

            // 不用 `faceid`：那个符号按 SF Symbols 的使用限制只能指 Apple 自家的面容 ID，这里是阿里云活体。
            Image(systemName: "face.smiling")
                .font(.system(size: circleSize * 0.45, weight: .regular))
                .foregroundColor(AppColors.primary)
                .frame(width: circleSize, height: circleSize)
                .background(Circle().fill(AppColors.primary.opacity(0.1)))
                .overlay(Circle().strokeBorder(AppColors.primary, lineWidth: 4))
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            RegistrationGroupCard {
                tipRow("找一个光线亮的地方")
                RegistrationRowDivider()
                tipRow("摘掉帽子、口罩和墨镜")
                RegistrationRowDivider()
                tipRow("跟着提示慢慢转头")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("刷脸前请注意：找一个光线亮的地方；摘掉帽子、口罩和墨镜；跟着提示慢慢转头。")
        }
    }

    private func tipRow(_ text: String) -> some View {
        Text(text)
            .font(AppFonts.body())
            .foregroundColor(AppColors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }
}

// MARK: - Bottom Bar

/// 固定在屏幕底部的按钮区。放在 `ScrollView` **下面**而不是叠在它上面：
/// 滚动区在栏的上沿结束，内容不会滚到栏后面，审计不会把被盖住的字判成对比度不足
/// （记忆 `opaque-bottom-bar-fakes-contrast-failure`）。
struct RegistrationBottomBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: AppSpacing.small) {
            content
        }
        .padding(.horizontal, 20)
        .padding(.top, AppSpacing.medium)
        .padding(.bottom, AppSpacing.small)
        .frame(maxWidth: .infinity)
        .background(Color.registrationPageBackground)
    }
}

/// 按钮下面那一行灰字（「还差：身份证号」之类）。
struct RegistrationBottomHint: View {
    let text: String
    let identifier: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundColor(AppColors.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier(identifier)
    }
}
