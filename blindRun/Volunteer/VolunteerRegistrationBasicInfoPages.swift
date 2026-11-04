import SwiftUI

// 志愿者注册第 1 步在界面上拆成的三屏：说明页、身份、经历（#699）。
// 刷脸那一屏仍在 `VolunteerRegistrationFlowView`；零件在 `VolunteerRegistrationIdentityPages.swift`。

/// 后端的第 1 步在界面上拆成的几屏（定稿 `docs/ui/mockups/volunteer-identity-20261104/`）。
///
/// 只在 `currentStep == .basicInfo` 时有意义。**接口不变**：身份和经历两屏填的内容
/// 仍在经历那一屏点「下一步」时由 `submitBasicInfo()` 一次提交。
enum BasicInfoPage: Equatable {
    /// 说明页：三步一览，外加改走人工审核的入口。
    case intro
    /// 界面第 1 步：姓名、身份证号、手机号（必填）。
    case identity
    /// 界面第 2 步：陪跑经历（选填，可跳过）。
    case experience
}

extension VolunteerRegistrationViewModel {
    /// 身份那一屏还差哪几项，按屏上的顺序。空数组才放「下一步」。
    /// 判据与 `basicInfoValidationMessage` 同一套，只是一次列全，按钮下面写「还差：xx」。
    var identityPageMissingFields: [String] {
        var missing: [String] = []
        if name.trimmed.isEmpty { missing.append("姓名") }
        if identityInfoValidationMessage != nil { missing.append("身份证号") }
        if !AppState.isValidMainlandPhone(phone.trimmed) { missing.append("手机号") }
        return missing
    }

    /// 顶部「第 N 步，共 3 步」的 N。说明页、结束页没有。
    var visibleStepNumber: Int? {
        guard !isRegistrationCompleted else { return nil }
        switch currentStep {
        case .faceVerify:
            return 3
        case .basicInfo:
            switch basicInfoPage {
            case .intro: return nil
            case .identity: return 1
            case .experience: return 2
            }
        }
    }

    var isOnExperiencePage: Bool {
        !isRegistrationCompleted && currentStep == .basicInfo && basicInfoPage == .experience
    }
}

// MARK: - Scroll Content

struct VolunteerRegistrationBasicInfoContent: View {
    @ObservedObject var viewModel: VolunteerRegistrationViewModel
    let consentDeclinedNotice: String?

    var body: some View {
        switch viewModel.basicInfoPage {
        case .intro:
            VolunteerRegistrationIntroContent()
        case .identity:
            identityPage
        case .experience:
            experiencePage
        }
    }

    private var identityPage: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            RegistrationPageHeading(title: "姓名和身份证号", subtitle: "要和身份证上的一致。")

            VStack(alignment: .leading, spacing: AppSpacing.small) {
                RegistrationGroupCard {
                    RegistrationTextFieldRow(
                        title: "姓名",
                        placeholder: "身份证上的姓名",
                        text: $viewModel.name,
                        identifier: "volunteerRegistrationField.姓名",
                        textContentType: .name
                    )
                    RegistrationRowDivider()
                    RegistrationTextFieldRow(
                        title: "身份证号",
                        placeholder: "18 位，含末尾 X",
                        text: $viewModel.idCardNumber,
                        identifier: "volunteerRegistrationField.身份证号",
                        keyboardType: .asciiCapable,
                        capitalizesCharacters: true
                    )
                    RegistrationRowDivider()
                    RegistrationTextFieldRow(
                        title: "手机号",
                        placeholder: "11 位手机号",
                        text: $viewModel.phone,
                        identifier: "volunteerRegistrationField.手机号",
                        keyboardType: .phonePad,
                        textContentType: .telephoneNumber
                    )
                }

                // 与同意层第三条告知同一口径（`PrivacyConsentPurpose.volunteerIdentity`）。
                Text("身份证号只用于核验身份，不会保存在这台手机上。")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }

            if let rejection = viewModel.registrationStatus?.identityRejectionNotice {
                RegistrationRejectionNotice(text: rejection, identifier: "volunteerIdentityRejectionNotice")
            }
        }
    }

    private var experiencePage: some View {
        VStack(alignment: .leading, spacing: AppSpacing.large) {
            RegistrationPageHeading(title: "你的陪跑经历", subtitle: "都是选填，可以跳过。")

            RegistrationGroupCard {
                RegistrationToggleRow(
                    title: "陪跑过",
                    isOn: $viewModel.hasGuidedBefore,
                    identifier: "volunteerRegistrationField.陪跑过"
                )
                RegistrationRowDivider()
                RegistrationTextFieldRow(
                    title: "跑步经验",
                    placeholder: "如：每周跑 3 次，跑过半马",
                    text: $viewModel.runningExperience,
                    identifier: "volunteerRegistrationField.跑步经验",
                    allowsMultipleLines: true
                )
                RegistrationRowDivider()
                RegistrationTextFieldRow(
                    title: "急救经验",
                    placeholder: "如：有红十字会急救证",
                    text: $viewModel.emergencyExperience,
                    identifier: "volunteerRegistrationField.急救经验",
                    allowsMultipleLines: true
                )
            }

            // 正常走不到：身份那一屏没填完「下一步」不放行。留着是兜底，提交前总要看得见为什么按不动。
            if let validationMessage = viewModel.basicInfoValidationMessage {
                Text(validationMessage)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel("无法提交身份信息：\(validationMessage)")
            }

            if let consentDeclinedNotice {
                Text(consentDeclinedNotice)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(consentDeclinedNotice)
                    .accessibilityIdentifier("volunteerIdentityConsentDeclinedNotice")
            }
        }
    }
}

// MARK: - Bottom Bar

struct VolunteerRegistrationBasicInfoBottomBar: View {
    @ObservedObject var viewModel: VolunteerRegistrationViewModel
    let hasConsentedToIdentity: Bool
    /// 经历那一屏的「下一步」：必须走 `handleBasicInfoSubmitTapped`，没有单独同意就不发请求。
    let onSubmit: () -> Void

    var body: some View {
        RegistrationBottomBar {
            switch viewModel.basicInfoPage {
            case .intro:
                introButtons
            case .identity:
                identityButton
            case .experience:
                experienceButton
            }
        }
    }

    @ViewBuilder
    private var introButtons: some View {
        PrimaryButton("开始") {
            viewModel.startIdentityEntry(prefersAlternativePath: false)
        }
        .accessibilityHint("先填姓名和身份证号")
        .accessibilityIdentifier("volunteerRegistrationIntroStartButton")

        // 现有的「拒绝人脸 → 二要素核验 + 人工审核」路径。拒绝接口要求二要素先通过，
        // 所以这里只记下选择，姓名和身份证号照样要填，提交通过后再代他调拒绝接口。
        Button("不想刷脸？改为上传身份材料") {
            viewModel.startIdentityEntry(prefersAlternativePath: true)
        }
        .buttonStyle(TextButtonStyle(alignment: .center))
        .accessibilityHint("仍要先填姓名和身份证号；之后上传能证明本人身份的材料，由管理员人工审核。审核时间较长，但结果等效")
        .accessibilityIdentifier("volunteerRegistrationIntroAlternativeButton")
    }

    @ViewBuilder
    private var identityButton: some View {
        let missing = viewModel.identityPageMissingFields
        let missingText = "还差：\(missing.joined(separator: "、"))"
        PrimaryButton("下一步") {
            viewModel.advanceToExperiencePage()
        }
        .disabled(!missing.isEmpty)
        .accessibilityHint(missing.isEmpty ? "去填陪跑经历，可以跳过" : missingText)
        .accessibilityIdentifier("volunteerRegistrationIdentityNextButton")
        if !missing.isEmpty {
            RegistrationBottomHint(text: missingText, identifier: "volunteerRegistrationMissingFields")
        }
    }

    @ViewBuilder
    private var experienceButton: some View {
        let hint = hasConsentedToIdentity
            ? "点下一步会一起提交第 1、2 步填的内容"
            : "点下一步会先请你同意使用身份证号和人脸信息，再一起提交第 1、2 步填的内容"
        PrimaryButton("下一步", isLoading: viewModel.isLoading, action: onSubmit)
            .disabled(!viewModel.canSubmitBasicInfo)
            .accessibilityHint(hint)
            .accessibilityIdentifier("volunteerRegistrationSubmitButton")
        RegistrationBottomHint(text: hint, identifier: "volunteerRegistrationSubmitHint")
    }
}
