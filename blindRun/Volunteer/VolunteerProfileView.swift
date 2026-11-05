import SwiftUI

// MARK: - 内容

/// 个人资料页显示的几行。纯数据，便于单测。
///
/// 🚩 **只画后端真有、且这页真拿得到的数据。** 稿子（2026-11-04）画了「昵称可改」和「陪跑经历」三项，实现前核了契约：
/// - `PUT /api/volunteer/profile` 的 `name` 必须等于实名核验的身份证姓名（后端 #826 M8），改成别的一律 400 ——
///   昵称和实名是同一个值，这页没有可改的东西，所以不给「编辑」。
/// - 陪跑经历（`hasGuidedBefore` / `runningExperience` / `emergencyExperience`）只在注册 step1 里写，
///   `GET /api/volunteer/profile` 不返回 ⇒ 不画。
struct VolunteerAccountProfileContent: Equatable {
    struct Row: Equatable {
        let id: String
        let title: String
        let value: String
        /// 读屏念的值。手机号只念尾号：掩码星号念出来是「星号星号」，全号不进无障碍文案（AGENTS.md §8）。
        let spokenValue: String?
    }

    /// 头像下面的大字。没有姓名时为 nil，不编占位。
    let displayName: String?
    let rows: [Row]

    static func make(
        profile: VolunteerProfileResponse?,
        phone: String?,
        registrationStatus: VolunteerRegistrationStatus?
    ) -> VolunteerAccountProfileContent {
        let name = profile?.name?.nilIfBlank
        var rows: [Row] = []
        if let name {
            rows.append(Row(id: "name", title: VolunteerAccountProfileCopy.nameTitle, value: name, spokenValue: nil))
        }
        if let phoneRow = phoneRow(phone) {
            rows.append(phoneRow)
        }
        if let identity = identityStatusText(registrationStatus?.resolvedIdVerifyStatus) {
            rows.append(Row(id: "identity", title: VolunteerAccountProfileCopy.identityTitle, value: identity, spokenValue: nil))
        }
        return VolunteerAccountProfileContent(displayName: name, rows: rows)
    }

    /// 手机号来自 `GET /api/auth/me`，后端已经脱敏成「138****0002」（`PhoneMaskUtils.mask`）。
    /// 也认 11 位明文（自己再脱敏一次）。别的形状一律不画：`maskPhone` 遇到别的长度会原样返回，全号就上屏了。
    private static func phoneRow(_ phone: String?) -> Row? {
        guard let phone = phone?.trimmed, !phone.isEmpty else { return nil }
        let masked: String
        if phone.count == 11, phone.allSatisfy(\.isNumber) {
            masked = "\(phone.prefix(3))****\(phone.suffix(4))"
        } else if phone.range(of: #"^[0-9]{3}\*{4}[0-9]{4}$"#, options: .regularExpression) != nil {
            masked = phone
        } else {
            return nil
        }
        return Row(
            id: "phone",
            title: VolunteerAccountProfileCopy.phoneTitle,
            value: masked,
            spokenValue: "尾号 \(masked.suffix(4))"
        )
    }

    /// 身份证二要素核验的状态。没有或认不出就不画这一行（不猜）。
    /// 账户页（`VolunteerAccountView`）的「实名认证」行也用这一份，两页说法一致。
    static func identityStatusText(_ status: String?) -> String? {
        switch status {
        case "APPROVED": return "已认证"
        case "PENDING": return "审核中"
        case "REJECTED": return "未通过"
        default: return nil
        }
    }
}

enum VolunteerAccountProfileCopy {
    static let navigationTitle = "个人资料"
    static let nameTitle = "姓名"
    static let phoneTitle = "手机号"
    static let identityTitle = "实名认证"
    /// 只有一处逗号；行中间的全角标点被挤到行尾会被审计判裁切（记忆 `text-clipped-audit-trailing-fullwidth-paren` 第 7 条）。
    static let readOnlyNote = "姓名与实名认证一致，手机号是登录账号。这里只显示、不能修改。"
}

// MARK: - View

/// 陪跑员「我的」→ 个人资料。照健康 App「健康详细信息」：头像 + 名字居中，下面字段名在左、值在右。
///
/// 未通过审核时根路由落地的认证页是另一个视图（`VolunteerCertificationGateView`），这一页只给已经进到标签栏的陪跑员。
/// 不发请求：资料、当前用户、注册状态都在 `AppState` 里，首页和根路由已经拉过。
struct VolunteerProfileView: View {
    @EnvironmentObject private var appState: AppState

    private var content: VolunteerAccountProfileContent {
        .make(
            profile: appState.volunteerProfile,
            phone: appState.currentUser?.phone,
            registrationStatus: appState.volunteerRegistrationStatus
        )
    }

    var body: some View {
        let content = content
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(content.displayName)

                if !content.rows.isEmpty {
                    GroupedCard {
                        ForEach(Array(content.rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                GroupedCardDivider()
                            }
                            VolunteerAccountValueRow(title: row.title, value: row.value, spokenValue: row.spokenValue)
                                .accessibilityIdentifier("volunteerAccountProfileRow.\(row.id)")
                        }
                    }
                    GroupedCardFootnote(text: VolunteerAccountProfileCopy.readOnlyNote)
                        .accessibilityIdentifier("volunteerAccountProfileReadOnlyNote")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle(VolunteerAccountProfileCopy.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏：悬浮的栏会盖住最后一行（记忆 `tab-bar-clips-the-last-line-of-secondary-pages`）。
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerAccountProfileView")
    }

    private func header(_ name: String?) -> some View {
        VStack(spacing: 12) {
            // 头像只是装饰：后端没有头像字段，画一个通用剪影。
            Image(systemName: "person.fill")
                .font(.system(size: 46, weight: .regular))
                .foregroundColor(.white)
                .frame(width: 96, height: 96)
                .background(Circle().fill(AppColors.Flow.decorMutedInk))
                .accessibilityHidden(true)
            if let name {
                Text(name)
                    .font(.title.weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        VolunteerProfileView()
            .environmentObject(AppState())
    }
}
#endif
