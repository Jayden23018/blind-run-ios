import Foundation

extension VoiceOrderWizard {
    static func isCancel(_ transcript: String) -> Bool {
        let normalized = normalizedCommand(transcript)
        guard !normalized.isEmpty else { return false }
        return normalizedCancelWords.contains(normalized)
    }

    /// 句尾语气词不改变语义，剥掉可以显著提高召回而不牺牲安全性（「确认吧」「好的呀」）。
    /// 句首不剥：那会让「不确认」这类否定的判定变得脆弱，而多问一轮是可接受的失败方向。
    private static let trailingParticles: Set<Character> = ["吧", "啊", "呀", "了", "哦", "喔", "嘛", "呗", "咯", "啦"]

    /// ponytail: 本地整串匹配只做**第 1 档直通**，判不出来不是终点 —— 交给
    /// `handleConfirmViaBackend` 的 `userIntent` / `correctionTarget`。原来那条「方言与长句会被判成
    /// 没听懂，用户多说一轮」的天花板已经由后端接住，本地表只保留零延迟与离线可用这两件事。
    static func normalizedCommand(_ transcript: String) -> String {
        var normalized = transcript.filter { !$0.isWhitespace && !$0.isPunctuation && !$0.isSymbol }
        while let last = normalized.last, trailingParticles.contains(last) {
            normalized.removeLast()
        }
        return normalized
    }

    static func isAffirmative(_ transcript: String) -> Bool {
        let normalized = normalizedCommand(transcript)
        guard !normalized.isEmpty else { return false }
        return affirmatives.contains(normalized)
    }

    /// 判定顺序有意义：**肯定词先判、且只认整串**，免得「重新确认一下」这种话里的「确认」被包含匹配吃掉。
    static func command(for transcript: String) -> Command {
        let normalized = normalizedCommand(transcript)
        guard !normalized.isEmpty else { return .unrecognized }
        if affirmatives.contains(normalized) { return .confirm }
        if repeatWords.contains(normalized) { return .repeatBack }
        if restartWords.contains(where: { normalized.contains($0) }) { return .restart }
        return .unrecognized
    }
}
