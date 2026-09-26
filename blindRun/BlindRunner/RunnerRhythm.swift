import Combine
import SwiftUI

// MARK: - 跑步中告诉陪跑员节奏（DECISIONS-v2 V14）

enum RunnerRhythmCopy {
    static let sectionTitle = "告诉陪跑员你的节奏"
    static func sent(_ signal: String) -> String { "已告诉陪跑员：\(signal)" }
    static let rateLimited = "刚发过，稍等再按"
    static let failed = "没有发出去，请重试"
    static let accessibilityHint = "陪跑员的手机会震动提醒"
}

@MainActor
final class RunnerRhythmViewModel: ObservableObject {
    @Published private(set) var sending: RunRhythmSignal?
    /// 最近一次的结果，**留在屏幕上**：不开读屏的低视力跑者也要看得见发没发出去。
    @Published private(set) var notice: (text: String, isProblem: Bool)?

    func send(
        _ signal: RunRhythmSignal,
        orderId: Int64,
        appState: AppState,
        speak: (String) -> Void,
        speakError: (String) -> Void
    ) async {
        guard sending == nil, let title = signal.title else { return }
        sending = signal
        defer { sending = nil }
        do {
            try await appState.orders.sendRhythm(signal, orderId: orderId)
            let text = RunnerRhythmCopy.sent(title)
            notice = (text, false)
            speak(text)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return }
            let text: String
            if case .rateLimited = error { text = RunnerRhythmCopy.rateLimited } else { text = RunnerRhythmCopy.failed }
            notice = (text, true)
            speakError(text)
        } catch {
            notice = (RunnerRhythmCopy.failed, true)
            speakError(RunnerRhythmCopy.failed)
        }
    }
}

/// 三个大按钮，竖直堆叠、整行铺满、每个 ≥64pt（`aidrun-a11y-voice`：盲人端次级操作绝不并排）。
/// 不用黄色：本页唯一的主操作仍是「播报当前数据」。
struct RunnerRhythmButtons: View {
    @ObservedObject var viewModel: RunnerRhythmViewModel
    let onSend: (RunRhythmSignal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(RunnerRhythmCopy.sectionTitle)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.Flow.primaryText)
                .accessibilityAddTraits(.isHeader)
            ForEach(RunRhythmSignal.sendable, id: \.self) { signal in
                FlowActionButton(
                    signal.title ?? "",
                    systemImage: Self.symbol(signal),
                    style: .ghost,
                    isLoading: viewModel.sending == signal,
                    isEnabled: viewModel.sending == nil,
                    accessibilityHint: RunnerRhythmCopy.accessibilityHint
                ) {
                    onSend(signal)
                }
                .accessibilityIdentifier("runnerRhythm_\(signal.rawValue)")
            }
            if let notice = viewModel.notice {
                Text(notice.text)
                    .font(AppFonts.body())
                    .foregroundColor(notice.isProblem ? AppColors.destructive : AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("runnerRhythmNotice")
            }
        }
    }

    private static func symbol(_ signal: RunRhythmSignal) -> String {
        switch signal {
        case .slower: return "arrow.down"
        case .faster: return "arrow.up"
        case .ok, .unknown: return "checkmark"
        }
    }
}
