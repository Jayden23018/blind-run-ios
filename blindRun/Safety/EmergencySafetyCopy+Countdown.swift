//
//  EmergencySafetyCopy+Countdown.swift
//  blindRun
//
//  倒计时那一屏「先自己拨 120 + 即将发生什么」（#659，审计 F-3）。
//  放在扩展文件里：`SafetyModule.swift` 已超 SwiftLint 行数基线，棘轮不许它再变长。
//

import Foundation

extension EmergencySafetyCopy {
    /// 倒计时那一屏「即将发生什么」之前的第一句（#659，审计 F-3）。
    ///
    /// 🔴 **第一句就让用户自己拨 120，并且别等回电。** 原来列表里写着「转给客服并回拨你」，
    /// 可是客服靠人开网页看，没有值班保证，也没有人承诺回拨 —— 用户可能等回电而晚拨 120。
    /// 后端 #898 同样删掉了「客服已收到」「留在原地等待」，模板都改成「如需急救请立即拨打120」。
    static let countdownSelfDialFirst = "如需急救请自己立即拨打120，别等人回电。"

    /// 进倒计时那一刻念一次的「即将发生什么」。
    ///
    /// 🔴 **三条都是进行时或将来时，一条完成时都没有。** 这不是文风选择：
    /// 短信是在触发事务提交之后异步发的、失败也从不回告盲人（`AGENTS.md` §6），
    /// 所以 App 永远不能说「已经通知了谁」。这里说的是**我们会去做什么**，不是做成了什么。
    /// 「联系你的紧急联系人」与后端模板「正在联系你的紧急联系人」同一口径。
    static let countdownPendingEffects = [
        "通知你的陪跑员",
        "联系你的紧急联系人",
        "把你的实时位置一起发出",
    ]

    /// 倒计时那一块的读屏整句：先说自己拨 120，再说接下来会做什么。
    static var countdownPendingEffectsAccessibilityLabel: String {
        countdownSelfDialFirst + "接下来会：" + countdownPendingEffects.joined(separator: "，")
    }
}
