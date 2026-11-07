import Foundation

extension RunPlanFormat {
    /// 公里数的数字部分：一位小数，整数去掉「.0」（`5000` 米 →「5」，`5240` 米 →「5.2」）。
    ///
    /// 负责人 2026-11-08 定（#846 D8）：所有「X 公里」都用这一条规则，屏幕和朗读同一个字符串。
    /// 不足 1 公里切成「米」的那一档不在这里，见 `plannedDistanceParts` 与 `DistanceCalculator.formattedDistance`。
    /// 大于 0 却不足 50 米时写「0.1」，不写「0」：「最后 0 公里」「还剩 0 公里」像出错了（出发地点列表同样最少写 0.1）。
    nonisolated static func kilometresValue(_ kilometres: Double) -> String {
        let rounded = (kilometres * 10).rounded() / 10
        if kilometres > 0, rounded == 0 { return "0.1" }
        return rounded == rounded.rounded()
            ? "\(Int(rounded))"
            : String(format: "%.1f", rounded)
    }
}
