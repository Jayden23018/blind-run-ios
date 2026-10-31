import Foundation

/// 陪跑员跑后详情的读屏文字（OpenSpec `audit-run-record-accessibility`，阶段 7）。
/// 与 `VolunteerRunRecordContent` 分文件只是因为那边已超过文件长度上限（SwiftLint 棘轮只许变小）。
extension VolunteerRunRecordContent {
    /// 页面标题的显示 / 朗读两份：屏幕上「和陈*一起跑」，读屏念「和陈一起跑」。
    var navigationTitle: (shown: String, spoken: String) { (title, spokenTitle) }

    /// 地图的整段读屏描述（HANDOFF §7 第 5 条：地图内部标记不逐个暴露，给一段整体描述）。
    ///
    /// 原型的 data-vo 还说颜色的意思和最快的一公里（§7 第 1 条：信息不能少）。
    /// 没有配速采样时整条路线是单色，不提颜色。
    static func spokenMapDescription(record: RunRecordResponse, spokenDistance: String?, geometry: RunRouteGeometry?) -> String {
        var description = "路线地图"
        if let spokenDistance { description += "，全程 \(spokenDistance) 公里" }
        if let geometry {
            description += geometry.startEndCoincide ? "，起点和终点在同一处" : "，起点和终点不在同一处"
        }
        description += record.stops.isEmpty ? "，途中没有休息" : "，途中休息\(record.stops.count)次"
        description += "。"
        if RunPaceScale(samples: record.paceSamples) != nil { description += "颜色表示配速，蓝色快，黄色慢。" }
        if let fastest = record.fastestSplitIndex { description += "第\(fastest)公里最快。" }
        return description + "数字见下方。"
    }
}
