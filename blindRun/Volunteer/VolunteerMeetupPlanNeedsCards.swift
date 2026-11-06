import SwiftUI

// MARK: - 时段单的「跑多久 + 跑步需求」四块（#806，模拟图 v4 的 V2）
//
// 只在时段单上出现：跑者下单时没填需求，陪跑员通话后在这里补。没动的项 = 「按跑者资料」，
// 请求里不发（`IntroCallPlanRequest` 的 `nil`）。拆成独立文件是因为 `VolunteerMeetupPlanFormView.swift`
// 已超过 400 行上限。

struct VolunteerMeetupPlanNeedsCards: View {
    @Binding var draft: VolunteerMeetupPlanDraft

    var body: some View {
        VStack(alignment: .leading, spacing: FlowMetrics.v2SectionGap) {
            card(title: VolunteerMeetupPlanCopy.durationLabel) {
                chips(
                    VolunteerMeetupPlanDraft.runDurationChoices.map { minutes in
                        Choice(label: VolunteerMeetupPlanCopy.durationText(minutes), isSelected: draft.runDurationMinutes == minutes) {
                            draft.runDurationMinutes = minutes
                        }
                    }
                )
            }
            .accessibilityIdentifier("volunteerMeetupPlanDurationCard")

            card(title: VolunteerMeetupPlanCopy.paceLabel) {
                chips(
                    [Choice(label: VolunteerMeetupPlanCopy.keepProfileValue, isSelected: draft.pacePreference == nil) {
                        draft.pacePreference = nil
                    }]
                    + [PacePreference.walkRun, .easy, .moderate, .fast].map { pace in
                        Choice(label: pace.displayName, isSelected: draft.pacePreference == pace) { draft.pacePreference = pace }
                    }
                )
            }
            .accessibilityIdentifier("volunteerMeetupPlanPaceCard")

            card(title: VolunteerMeetupPlanCopy.guideDogLabel) {
                chips([
                    Choice(label: VolunteerMeetupPlanCopy.keepProfileValue, isSelected: draft.hasGuideDogThisRun == nil) {
                        draft.hasGuideDogThisRun = nil
                    },
                    Choice(label: "带", isSelected: draft.hasGuideDogThisRun == true) { draft.hasGuideDogThisRun = true },
                    Choice(label: "不带", isSelected: draft.hasGuideDogThisRun == false) { draft.hasGuideDogThisRun = false },
                ])
            }
            .accessibilityIdentifier("volunteerMeetupPlanGuideDogCard")

            card(title: VolunteerMeetupPlanCopy.notesLabel) {
                TextField(VolunteerMeetupPlanCopy.notesPlaceholder, text: $draft.specialNotes, axis: .vertical)
                    .flowFont(FlowV2Fonts.callout())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppColors.Flow.separator, lineWidth: 1)
                    )
                    .accessibilityLabel(VolunteerMeetupPlanCopy.notesLabel)
                    .accessibilityHint("最多 \(VolunteerMeetupPlanDraft.specialNotesMaxLength) 个字")
                    .accessibilityIdentifier("volunteerMeetupPlanNotesField")
                if draft.isSpecialNotesTooLong {
                    Text(VolunteerMeetupPlanCopy.notesTooLong)
                        .flowFont(FlowV2Fonts.subhead(bold: true))
                        .foregroundColor(AppColors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: 小部件

    private struct Choice: Identifiable {
        let label: String
        let isSelected: Bool
        let action: () -> Void
        var id: String { label }
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        FlowCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .flowFont(FlowV2Fonts.subhead(bold: true))
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .accessibilityElement(children: .contain)
    }

    /// 与上衣颜色那组胶囊同一套样式（选中 2pt 强调色描边、未选 1pt 分隔线色），陪跑员端一屏只有一种选择控件。
    private func chips(_ choices: [Choice]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(choices) { choice in
                Button(action: choice.action) {
                    Text(choice.label)
                        .flowFont(FlowV2Fonts.callout(bold: choice.isSelected))
                        .foregroundColor(AppColors.Flow.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(
                            Capsule().strokeBorder(
                                choice.isSelected ? AppColors.Flow.accent : AppColors.Flow.separator,
                                lineWidth: choice.isSelected ? 2 : 1
                            )
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(choice.isSelected ? .isSelected : [])
            }
        }
    }
}
