import Foundation

/// 带绳提醒与「开始跑步」上方那行小字，按跑者的引导方式（`tetherPreference`）换说法（#660 V-8 / F-29）。
///
/// 负责人 2026-11-04 定：**两端都提醒带绳，现场谁有就用谁的**。跑者选「搀扶」或「仅语言引导」时不提醒。
/// 没给、`NOT_SPECIFIED`、认不出的新值一律**照常提醒** —— 多带一根绳没有代价，到了现场没绳就开不了跑。
///
/// 提醒只放在两端「约好」那一步的订单页（`SCHEDULED_CONFIRMED` / `PENDING_ACCEPT`）。
enum GuideRopeReminder {
    static let blindLine = "出门记得带上引导绳。陪跑员也会收到同样的提醒，现场谁带了就用谁的。"
    static let volunteerLine = "出门记得带上引导绳。跑者也会收到同样的提醒，现场谁带了就用谁的。"

    static func remindsToBringRope(tetherPreference: String?) -> Bool {
        switch TetherPreference(rawValue: tetherPreference?.nilIfBlank ?? "") {
        case .armHold, .verbalOnly: return false
        case .tetherRope, .none: return true
        }
    }

    /// 只在「约好」那一步给，其余状态 `nil`。
    static func line(for order: OrderDetailResponse, isVolunteer: Bool) -> String? {
        guard order.status == .scheduledConfirmed || order.status == .pendingAccept,
              remindsToBringRope(tetherPreference: order.tetherPreference) else { return nil }
        return isVolunteer ? volunteerLine : blindLine
    }

    /// 陪跑员「开始跑步」上方那行小字。原来写死「见面并握好引导绳后再按」，跑者选搀扶或仅语言引导时也这么写。
    static func startRunCaption(tetherPreference: String?) -> String {
        switch TetherPreference(rawValue: tetherPreference?.nilIfBlank ?? "") {
        case .tetherRope: return VolunteerOrderFlowCopy.startRunCaption
        case .armHold: return "见面并让跑者扶好你的手臂后再按"
        case .verbalOnly: return "见面并和跑者说好怎么用语言引导后再按"
        case .none: return "见面并和跑者确认好引导方式后再按"
        }
    }
}

extension VolunteerOrderFlowPresentation.PrimaryAction {
    /// `caption(awaitingBlindConfirmation:)`，但「开始跑步」那句按引导方式换说法。
    func caption(awaitingBlindConfirmation: Bool, tetherPreference: String?) -> String? {
        guard self == .startRun, !awaitingBlindConfirmation else {
            return caption(awaitingBlindConfirmation: awaitingBlindConfirmation)
        }
        return GuideRopeReminder.startRunCaption(tetherPreference: tetherPreference)
    }
}

extension OrderDetailResponse {
    /// 盲人订单页副标题的状态说明：通用那句，约好时再接一句带绳提醒。
    var blindRunnerFlowDescription: String {
        guard let rope = GuideRopeReminder.line(for: self, isVolunteer: false) else {
            return blindRunnerDescriptionUnlessLeftAlone
        }
        return blindRunnerDescriptionUnlessLeftAlone + rope
    }
}
