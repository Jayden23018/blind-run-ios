import Foundation

extension BlindBookingViewModel {
    func moveToNextStep() {
        guard canAdvanceFromCurrentStep else {
            let message = blockingReasonForCurrentStep ?? "请先完成当前步骤。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }

        guard let currentIndex = BlindBookingGuidedStep.allCases.firstIndex(of: currentStep),
              currentIndex < BlindBookingGuidedStep.allCases.count - 1 else {
            return
        }
        errorMessage = nil
        let nextStep = BlindBookingGuidedStep.allCases[currentIndex + 1]
        if nextStep == .appointmentTime { reseedAppointmentTimeIfExpired() }
        currentStep = nextStep
        speechService?.speak(currentStepSpeechSummary)
    }

    func moveToPreviousStep() {
        guard let currentIndex = BlindBookingGuidedStep.allCases.firstIndex(of: currentStep),
              currentIndex > 0 else {
            return
        }
        errorMessage = nil
        currentStep = BlindBookingGuidedStep.allCases[currentIndex - 1]
        speechService?.speak(currentStepSpeechSummary)
    }

    func repeatCurrentStepStatus() {
        speechService?.speak(currentStepSpeechSummary)
    }

    /// 进页面就把第一个「本页填不了」的门槛播出来。
    ///
    /// 起点和时间是这一页自己的槽位，缺了不算进不来，向导和分步提示各自会管。
    /// 剩下三道都得去别的页面补（资料 / 实名 / 紧急联系人），
    /// 越早说越好：审阅步的按钮禁用状态走的是全部五道门槛，用户填完四步撞上一个灰按钮时，
    /// 看不见屏幕的人只会当成「点了没反应」。
    ///
    /// 语音路径不走这里 —— `VoiceOrderWizard.start()` 在启动前用同一套门槛自己播过一次了。
    func announceEntryGateIfNeeded() {
        guard let gate = firstMissingGate, gate != .startPoint, gate != .appointmentTime else { return }
        errorMessage = gate.message
        speechService?.speak(gate.message)
    }
}
