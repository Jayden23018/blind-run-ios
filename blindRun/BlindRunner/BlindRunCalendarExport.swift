import EventKit
import EventKitUI
import SwiftUI

// MARK: - 「加入日历」（#660 B-18）
//
// 用系统的日程编辑页（`EKEventEditViewController`），用户在里面看一遍、按「添加」才写进日历。
//
// 🔴 **只在 iOS 17 及以上出现。** Apple 文档《Accessing the event store》与 TN3152（2026-11-04 核实）：
// iOS 17 起 EventKitUI 的编辑页跑在 App 进程外，**不需要任何日历权限**，也不需要 Info.plist 用途说明；
// iOS 16 上同一个编辑页要先拿到完整日历权限，还要加 `NSCalendarsUsageDescription` 与 `NSContactsUsageDescription`。
// 为一个辅助功能在 iOS 16 上多弹一次权限、多声明一项通讯录用途不值得，那里只靠本机开跑提醒
// （`BlindRunStartReminder`）。

enum BlindRunCalendarExport {
    static let buttonTitle = "加入日历"

    /// 写进日程备注。日程不会跟着订单变，得让用户知道要自己删。
    static let notes = "这条日程是从助盲跑加入的。订单取消或改了时间，日程不会跟着变，请自己删掉或修改。"

    /// 日程自带的提醒：提前 1 小时，与本机开跑提醒同一个时刻。
    static let alarmOffset: TimeInterval = -BlindRunStartReminder.leadTime

    /// 这张单能不能加：人已经定下来、开始时间还没到。
    static func canExport(_ order: OrderDetailResponse, now: Date = Date()) -> Bool {
        guard order.status.remindsBlindRunnerBeforeStart,
              let start = order.plannedStart?.backendTimestamp else { return false }
        return start > now
    }

    /// 结束时刻：有 `plannedEnd` 用它，没有就按预计时长，都没有按 1 小时。
    static func endDate(for order: OrderDetailResponse, start: Date) -> Date {
        if let end = order.plannedEnd?.backendTimestamp, end > start { return end }
        let minutes = order.expectedDurationMinutes ?? 60
        return start.addingTimeInterval(TimeInterval(minutes) * 60)
    }

    static func makeEvent(for order: OrderDetailResponse, in store: EKEventStore) -> EKEvent? {
        guard let start = order.plannedStart?.backendTimestamp else { return nil }
        let event = EKEvent(eventStore: store)
        event.title = "助盲跑陪跑"
        event.startDate = start
        event.endDate = endDate(for: order, start: start)
        // 自己的日历，写出发地点是方便他自己：这和锁屏通知不同，通知正文里不写（见 `BlindRunStartReminder`）。
        event.location = order.startAddress?.nilIfBlank
        event.notes = notes
        event.addAlarm(EKAlarm(relativeOffset: alarmOffset))
        return event
    }
}

/// 首页订单卡下面那枚按钮。iOS 16、或这张单不能加时整个不渲染。
struct BlindRunCalendarButton: View {
    let order: OrderDetailResponse
    @State private var isPresentingEditor = false

    var body: some View {
        if #available(iOS 17, *), BlindRunCalendarExport.canExport(order) {
            Button(BlindRunCalendarExport.buttonTitle) { isPresentingEditor = true }
                .buttonStyle(OutlineSecondaryButtonStyle())
                .accessibilityHint("打开系统日历，确认后把这次陪跑加进日历。订单取消后要自己删掉这条日程")
                .accessibilityIdentifier("blindHomeAddToCalendar")
                .sheet(isPresented: $isPresentingEditor) {
                    BlindRunEventEditor(order: order) { isPresentingEditor = false }
                        .ignoresSafeArea()
                }
        }
    }
}

@available(iOS 17, *)
private struct BlindRunEventEditor: UIViewControllerRepresentable {
    let order: OrderDetailResponse
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = context.coordinator.store
        controller.event = BlindRunCalendarExport.makeEvent(for: order, in: context.coordinator.store)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        /// 编辑页持有的 store 要活得比它久（文档：先释放 store 再用其他 EventKit 对象可能出错）。
        let store = EKEventStore()
        let onFinish: () -> Void

        init(onFinish: @escaping () -> Void) {
            self.onFinish = onFinish
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            onFinish()
        }
    }
}
