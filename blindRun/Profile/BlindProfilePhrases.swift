import Foundation

// 「途中提示」「其他需求」两张卡的常用说法（#812，负责人 2026-11-06 批准的书面说法）。
//
// 后端只有两个自由文本字段（`guidePreferenceText` ≤ 80、`specialNeeds` ≤ 500），不加字段：
// 勾选的说法与补充说明用「；」拼成一句存回原字段，回读时再拆开。
//
// 🔴 说法文字**就是存进去、陪跑员看到的文字**，也是回读时认人的依据。改了某一条，
// 老用户存的旧说法就认不出了 —— 不会丢（落进补充说明），但不再打勾。改之前想清楚。

/// 一张卡上的答案：单选的那一句（可无）、勾选的说法、补充说明。
struct BlindProfilePhraseAnswer: Equatable {
    var single: String?
    var multi: Set<String>
    var supplement: String

    static let empty = BlindProfilePhraseAnswer(single: nil, multi: [], supplement: "")
}

/// 一组常用说法：单选项、多选项（展示与拼接都按这个顺序）、互斥项、字数上限。
struct BlindProfilePhraseSet {
    static let separator = "；"

    let singleOptions: [String]
    /// 含互斥项（放最后）。
    let multiOptions: [String]
    /// 选它就清掉其他多选项，选其他项就清掉它。`nil` = 没有互斥项。
    let exclusiveOption: String?
    /// 按 UTF-16 数，与后端 `@Size` 同口径。
    let limit: Int

    // MARK: 拼接

    /// 单选那句在前，多选按 `multiOptions` 的顺序，补充说明放最后，用「；」连接。空的部分跳过。
    func compose(_ answer: BlindProfilePhraseAnswer) -> String {
        var parts: [String] = []
        if let single = answer.single, singleOptions.contains(single) {
            parts.append(single)
        }
        parts += multiOptions.filter { answer.multi.contains($0) }
        if let supplement = answer.supplement.trimmed.nilIfBlank {
            parts.append(supplement)
        }
        return parts.joined(separator: Self.separator)
    }

    // MARK: 回读

    /// 按「；」切开：和某个说法一字不差的段打勾，其余段按原顺序用「；」拼回补充说明。
    ///
    /// 老用户以前手写的字因此**一个都不丢**，只是可能挪到「补充说明」里。
    /// 单选项出现多次时只认第一个，后面的同样落进补充说明（不丢字）。
    func parse(_ text: String) -> BlindProfilePhraseAnswer {
        var answer = BlindProfilePhraseAnswer.empty
        var leftovers: [String] = []
        for raw in text.components(separatedBy: Self.separator) {
            let segment = raw.trimmed
            guard !segment.isEmpty else { continue }
            if answer.single == nil, singleOptions.contains(segment) {
                answer.single = segment
            } else if multiOptions.contains(segment), !answer.multi.contains(segment) {
                answer.multi.insert(segment)
            } else {
                leftovers.append(segment)
            }
        }
        // 互斥项与其他项同时存在（手写或旧数据）时，互斥项让位：留下更具体的那些。
        if let exclusive = exclusiveOption, answer.multi.contains(exclusive), answer.multi.count > 1 {
            answer.multi.remove(exclusive)
            leftovers.insert(exclusive, at: 0)
        }
        answer.supplement = leftovers.joined(separator: Self.separator)
        return answer
    }

    // MARK: 多选

    /// 点一下某个多选项后的勾选集合（处理互斥项）。
    func toggling(_ option: String, in selected: Set<String>) -> Set<String> {
        var result = selected
        if result.contains(option) {
            result.remove(option)
            return result
        }
        if option == exclusiveOption {
            return [option]
        }
        if let exclusive = exclusiveOption {
            result.remove(exclusive)
        }
        result.insert(option)
        return result
    }

    // MARK: 字数

    func length(of composed: String) -> Int {
        composed.trimmed.utf16.count
    }

    /// 还能写几个字；负数 = 超出。
    func remaining(for answer: BlindProfilePhraseAnswer) -> Int {
        limit - length(of: compose(answer))
    }

    /// 超长时的提示；`nil` = 没超。
    func lengthError(for answer: BlindProfilePhraseAnswer) -> String? {
        let over = -remaining(for: answer)
        guard over > 0 else { return nil }
        return "内容超出 \(over) 字，最多 \(limit) 字。请减少选项或缩短补充说明。"
    }

    /// 输入框下面那行灰字。
    func remainingText(for answer: BlindProfilePhraseAnswer) -> String {
        let left = remaining(for: answer)
        return left >= 0 ? "含已选内容，剩余 \(left) 字。" : "含已选内容，已超出 \(-left) 字。"
    }
}

extension BlindProfilePhraseSet {
    /// 契约 `BlindProfileUpdateRequest.specialNeeds` `maxLength: 500`。
    static let specialNeedsMaxLength = 500

    /// 「途中提示」→ `guidePreferenceText`。单选是「路况播报」，三项都存一句话，
    /// 这样答完这张卡字段一定非空，卡片不会在「已保存」之后仍显示「尚未设置」（负责人 11-06 批准）。
    static let guideNote = BlindProfilePhraseSet(
        singleOptions: ["仅播报必要路况", "详细描述周边环境", "详略均可"],
        multiOptions: ["转弯前提前提示", "台阶、路沿提前提示", "说明陪跑员所在的一侧", "递物或肢体接触前先征询"],
        exclusiveOption: nil,
        limit: BlindProfileUpdateRequest.guidePreferenceMaxLength
    )

    /// 「其他需求」→ `specialNeeds`。只放非医疗说法，避开敏感健康信息。
    /// 「无其他需求」互斥且这一题至少选一项，理由同上（负责人 11-06 批准）。
    static let specialNeeds = BlindProfilePhraseSet(
        singleOptions: [],
        multiOptions: ["途中需要休息", "跑前需慢走热身", "定时提醒补水", "尽量选择安静路线", "请提高音量、放慢语速", noOtherNeeds],
        exclusiveOption: noOtherNeeds,
        limit: specialNeedsMaxLength
    )

    static let noOtherNeeds = "无其他需求"
}
