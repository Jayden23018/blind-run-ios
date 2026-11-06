import SwiftUI

extension BlindBookingView {
    var appointmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("预约时间")
            DatePicker(
                "预约时间",
                selection: $viewModel.appointmentTime,
                // 上界是 2026-09-05 加的：后端此前对 `plannedStartTime` 只有下限，
                // 用户能选到几个月后，然后在提交那一步吃 422 `APPOINTMENT_TOO_FAR`。
                // 对盲人一次被拒等于重走整套读回流程，所以拦在选择器上。
                // ⚠️ 夜间窗口 `[22:00, 05:00)` **拦不到这里** —— `DatePicker` 的 `in:`
                // 只接受连续区间，挖不出一个洞。那道由 `appointmentTimeProblem` 在提交前拦。
                in: viewModel.minimumAppointmentTime...viewModel.maximumAppointmentTime,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.compact)
            .font(AppFonts.body())
            .foregroundColor(AppColors.textPrimary)
            .accessibilityLabel("预约时间，\(viewModel.appointmentTime.formatted(date: .abbreviated, time: .shortened))")
            .accessibilityHint("请选择至少三十分钟后、\(AppConstants.Timing.maximumBookingLeadDays) 天以内的时间")

            BookingAppointmentAdjusters(viewModel: viewModel)

            // 这里此前**两种状态同一句话**，合法与否只由颜色区分（灰 / 红）。
            // 那不只是色觉障碍的问题：读屏用户根本没有颜色这条通道，选了一个过近的时间
            // 之后听到的还是那句中性的规则说明，只有提交被拒时才知道。
            // 所以改文案而不是加一个 `differentiateWithoutColor` 分支 —— 后者只补色觉一条通道，
            // 前者对所有人都修好，且顺带让颜色不再是唯一信号。
            Text(viewModel.appointmentTimeHint)
                .font(AppFonts.caption())
                .foregroundColor(viewModel.isAppointmentTimeValid ? AppColors.textSecondary : AppColors.destructive)
                .accessibilityLabel(viewModel.appointmentTimeHint)
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    var optionalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("更多选项（选填）")

            escortGuidanceHint

            VoiceTextField(
                title: "路线备注",
                placeholder: "例如：沿公园慢跑一圈",
                text: $viewModel.routeNotes, allowsLineBreaks: true,
                speechInputService: speechInputService,
                speechService: speechService,
                speechField: .destinationRoute,
                accessibilityLabel: "路线备注，选填",
                accessibilityHint: "可以使用语音或键盘输入路线说明"
            )

            // 三个都走 `BlindMenuPicker`（#527）：原来的菜单 Picker 约 34pt、分段控件约 32pt，
            // 低于盲人端 64pt；分段控件在 AX5 下还会把中文选项挤成省略号。
            BlindMenuPicker(
                title: "预计时长",
                selection: $viewModel.duration,
                valueText: viewModel.duration.displayName,
                accessibilityLabel: "预计时长，选填",
                accessibilityHint: "点击选择预计跑步时长"
            ) {
                ForEach(BookingDurationOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            BlindMenuPicker(
                title: "配速偏好",
                selection: $viewModel.pacePreference,
                valueText: viewModel.paceOptionTitle(viewModel.pacePreference),
                accessibilityLabel: "配速偏好，选填",
                accessibilityHint: "选择走跑结合、轻松、中等或快速"
            ) {
                ForEach(PacePreference.allCases, id: \.self) { option in
                    Text(viewModel.paceOptionTitle(option)).tag(option)
                }
            }

            BlindMenuPicker(
                title: "路线偏好",
                selection: $viewModel.routePreference,
                valueText: viewModel.routePreference.displayName,
                accessibilityLabel: "路线偏好，选填",
                accessibilityHint: "选择公园步道、街道或跑道"
            ) {
                ForEach(RoutePreference.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }

            // 开关只能表达 `nil`/`true`：关掉等于「没提」，不是「明确不带」——
            // 屏幕上一个关着的开关本来就分不出这两者，硬把它读成"明确不带"是替用户表态。
            // `false` 只由语音产生（「今天不带导盲犬」）。
            Toggle("本次携带导盲犬", isOn: Binding(
                get: { viewModel.hasGuideDogThisRun == true },
                set: { viewModel.hasGuideDogThisRun = $0 ? true : nil }
            ))
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityLabel("是否本次携带导盲犬，选填")
                .accessibilityHint("开启后记录本次跑步携带导盲犬")

            VoiceTextField(
                title: "特殊说明",
                placeholder: "例如：我会带导盲杖",
                text: $viewModel.specialNotes,
                isMultiline: true,
                speechInputService: speechInputService,
                speechService: speechService,
                speechField: .remark,
                accessibilityLabel: "特殊说明，选填",
                accessibilityHint: "可以使用语音或键盘输入特殊说明"
            )
        }
    }

    /// 「还没告诉志愿者你希望怎么被引导」的一次性提示。
    ///
    /// 这一项在档案里（`BlindRunnerProfileView`），而档案页没有任何东西会把人带过去 ——
    /// 不提示的结果就是绝大多数人永远停在「未填」，志愿者到场前不知道该递绳还是该让人挽手臂。
    ///
    /// 🚩 **零持久化**：判据是「档案里填了没有」，填了这一行自然消失。
    /// 不需要「已提示过」标志，也就不会因为换设备 / 重装而重来一次。
    ///
    /// 🚩 **只上屏，不进下单播报。** 语音下单是这个 App 最高频、也最不该被打断的路径，
    /// 为一条可跳过的提示在每次下单时多念一句不划算。读屏用户遍历到这一段时才听到它，
    /// 那时他正在看「更多选项」，恰好是这条提示有意义的时刻。
    @ViewBuilder
    private var escortGuidanceHint: some View {
        // `NOT_SPECIFIED` 也算没填（#472）：后端 #800 起它是新建档默认值，只判 nil 会让新账号永远看不到这条。
        if TetherPreference.isUnprovided(appState.blindProfile?.tetherPreference) {
            VStack(alignment: .leading, spacing: 8) {
                Text("还没填「希望怎么被引导」。填了之后，陪跑员到场前就知道该递牵引绳、让你挽住手臂，还是只用口令。")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                NavigationLink {
                    BlindRunnerProfileView()
                } label: {
                    Text("去个人资料填写")
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.primary)
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonShapeOutlineIfNeeded(color: AppColors.primary)
                .accessibilityLabel("去个人资料填写希望怎么被引导")
                .accessibilityHint("选填")
                .accessibilityIdentifier("blindBookingEscortGuidanceHintLink")
            }
        }
    }

    var reviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("确认预约")

            reviewRow(title: "出发地点", value: viewModel.resolvedStartLocationDescription.nilIfBlank ?? "出发地点待确认")
            // 语音降级回表单时终点会跟着留下来，所以复核页也得能看到它。
            if let endPlace = viewModel.endPlace {
                reviewRow(
                    title: "结束地点",
                    value: endPlace.isUnresolved ? "\(endPlace.address)（未定位到）" : endPlace.address
                )
            }
            reviewRow(title: "预约时间", value: DateFormatter.aidRunDisplayDateTime.string(from: viewModel.appointmentTime))
            // 紧跟预约时间，**不进下面那段选填需求** —— 它是推出来的事实不是用户填的项。
            // 没说时长时这一行会自己交代「按 1 小时计」，那正是此前整条链上一个字都没说的东西。
            reviewRow(title: "预计结束", value: viewModel.plannedEndSummary)

            if viewModel.optionalReviewItems.isEmpty {
                Text("未填写选填跑步需求。")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("未填写选填跑步需求")
            } else {
                ForEach(viewModel.optionalReviewItems) { item in
                    reviewRow(title: item.title, value: item.value)
                }
            }

            if let blockingReason = viewModel.blockingReasonForCurrentStep {
                Text(blockingReason)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel(blockingReason)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    private func reviewRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(value)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}
