import Foundation

// MARK: - 「一束光地图」原型（方向 C 灯火）

/// 「一束光地图」的纯数据层：投影、聚合、文案。**没有视图、没有网络、没有真实坐标。**
///
/// 视觉方向取 `docs/research/light-map-visual-directions-20260911.md` §4.1 推荐的
/// **C「灯火」** —— 夜光卫星影像当底，中国轮廓由真实城市灯火构成，用户的冷青光叠在暖橙灯火之上。
/// 选它的决定性理由只有一条：**只有 C 在 40 人规模下成立**。另外两个方向里，A「星图」靠
/// 「基底星」撑满画面（报告原话：这等于假装有人），B「静夜」的光点在真实底图上零零落落。
///
/// ## ⚠️ 这是原型，不是可上线的实现
///
/// 两条硬约束在这里被**绕开而不是解决**，接真实数据前必须先回答：
///
/// 1. **合规** —— App 内可缩放中国地图须送审并在左下角标注审图号。
///    `docs/research/map-review-exemption-ruling-20260921.md`（09-21）逐条对照了
///    《地图审核管理规定》第六条的三项免审情形，结论是「只到城市级」这个口子**不成立**：
///    第（三）项「不涉及国界、边界、历史疆界、行政区域界线**或者范围**」里「或者范围」四个字
///    是决定性的 —— 按城市聚合并定位这些城市，就是在表示行政区域范围。
///    本原型用的是 NASA 夜光**卫星影像**而非编制地图，09-11 报告 §1 把「影像是否构成地图」
///    列为**待确认**（没有找到任何官方对「卫星影像底图 + 自有标注」的定性）。
///    🚩 **不要把它当成已经绕开了审图号。**
///
/// 2. **隐私** —— 真实数据下最小聚合粒度是 **k≥20**
///    （`map-tech-and-location-privacy-20260913.md` 推翻了前一轮的 `k=5`：那个值只在
///    低风险/单一属性/大基数数据集里被引为下限，我们三个前提全不满足），
///    且**「新用户点亮」动画本身就是时序攻击通道** —— 增量为 1 时，前后两帧的差就是那个人。
///
/// 本文件全部用假数据，所以不触发上面两条。`sampleSites` 一旦换成真实聚合结果，
/// 这两条立刻生效。
///
/// ## 红线（三个视觉方向共用，报告 §3 维度 12）
///
/// 点击光点**不得**显示任何个人信息、头像、昵称或精确位置。只能显示区县级聚合文案，
/// 且必须同时可被 VoiceOver 读出。`caption(for:)` 是唯一的文案出口，检查钉在它上面。
enum LanternMap {

    // MARK: - 地理范围与投影

    /// 底图覆盖的经纬度范围。
    ///
    /// 🔴 **改这四个数必须同步重裁底图素材**，否则光点会和底层灯火整体错位 ——
    /// 而错位在视觉上不像 bug，像「数据不准」，没人会去怀疑这四个数。
    /// 裁图参数写在 `scripts/crop-lantern-basemap.sh`，两处取值必须一致。
    struct GeoBounds: Equatable, Sendable {
        let west: Double
        let east: Double
        let south: Double
        let north: Double

        /// 中国大陆 + 近海。西起帕米尔（~73°E），东至黑龙江与乌苏里江汇合处（~135°E），
        /// 南起南沙（本框不含，取海南以北 17°N），北至漠河（~53.5°N）。
        /// 取整到度是刻意的：裁图脚本按整度算像素偏移，不留小数。
        static let china = GeoBounds(west: 73, east: 136, south: 17, north: 54)
    }

    /// 底图的宽高比（等距圆柱投影下就是经度跨度 ÷ 纬度跨度）。
    ///
    /// ⚠️ 中国在这张图上会显得**偏扁**，这不是 bug —— 等距圆柱投影下每一度经度的屏幕宽度
    /// 处处相等，而实际地面距离随纬度收缩。NASA 那张原图本身就是这个投影，所以
    /// **影像和光点是一致的**，两者一起扁。换成墨卡托才需要重新算，那是接高德那天的事。
    static var basemapAspectRatio: Double {
        let b = GeoBounds.china
        return (b.east - b.west) / (b.north - b.south)
    }

    /// 经纬度 → 归一化画布坐标（`0...1`，原点在左上）。
    ///
    /// 夜光影像是**等距圆柱投影**（Plate Carrée），所以这是一个纯线性映射 —— 一行的事。
    ///
    /// 🔑 这正是原型不接高德的收益：09-11 报告 §6 把「投影对齐未验证」列为已知缺口，
    /// 但那条缺口的完整形态是「等距圆柱的影像 叠 Web 墨卡托的高德底图（GCJ-02）」。
    /// 纯自绘时它不存在。**接高德那天要重新做这件事**，不要因为原型跑通了就以为它解决了。
    ///
    /// 返回值可能落在 `0...1` 之外（点在框外），调用方自己裁。
    static func normalizedPoint(
        longitude: Double,
        latitude: Double,
        in bounds: GeoBounds = .china
    ) -> (x: Double, y: Double) {
        let x = (longitude - bounds.west) / (bounds.east - bounds.west)
        let y = (bounds.north - latitude) / (bounds.north - bounds.south)
        return (x, y)
    }

    // MARK: - 数据

    /// 一个亮着灯的地方。**最细粒度是区县，没有更细的东西可以进这个结构。**
    ///
    /// 注意这里没有 `blindRunnerCount`：报告 §3 维度 7 在方向 C 下明确建议
    /// **视障跑者不单独上图** —— 暖色的盲人光会和底层暖橙灯火混淆，而且第一部分 §2.3 的
    /// 隐私结论本来就指向「只上志愿者」。少一个字段，少一条泄露路径。
    struct Site: Identifiable, Equatable, Sendable {
        /// 区县名。
        ///
        /// ⚠️ **区县名全国不唯一**，这不是理论问题：本文件的假数据里「和平区」就有两个
        /// （天津、沈阳）。所以 `id` 和给用户看的 `label` 都带上 `region` ——
        /// 拿区县名当 key 会让其中一个在 `ForEach` 里被吃掉，而画面上只是「少了一个点」，
        /// 没有任何报错。真实数据请换成后端的行政区划码。
        let name: String
        /// 上一级行政区，`Tier.region` 档下按它聚合。
        let region: String
        let longitude: Double
        let latitude: Double
        let volunteerCount: Int

        var id: String { region + name }

        /// 给用户看 / 给 VoiceOver 念的地名。带上省份，否则两个「和平区」听起来一模一样。
        var label: String { region + name }
    }

    /// 聚合后的一束光。`Tier.site` 档下它就是单个 `Site`。
    struct Cluster: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let longitude: Double
        let latitude: Double
        let volunteerCount: Int
    }

    // MARK: - 聚合

    /// 缩放档位。**只有两档。**
    ///
    /// ponytail: 两档聚合，等到一屏放不下 `sampleSites` 的量级（真实数据、上千个区县）
    /// 再换四叉树。现在 24 个点做多级索引是纯粹的自娱自乐。
    enum Tier: Equatable, Sendable {
        /// 省 / 直辖市级。画面缩小时用，避免同城多个区县糊成一团。
        case region
        /// 区县级。这是**最细的一档，没有更细的**（红线：个体不上图）。
        case site
    }

    /// 档位阈值。低于它按 `region` 聚，到了它按 `site` 散开。
    static let siteTierScale: Double = 2.5

    static func tier(forScale scale: Double) -> Tier {
        scale >= siteTierScale ? .site : .region
    }

    /// 按档位聚合。
    ///
    /// 聚合点的位置取**按人数加权**的重心，不是简单平均 —— 一个省里 200 人的省会
    /// 和 3 人的边城平均下来，光应该压在省会上，那才是「灯火」该有的位置。
    ///
    /// 🔑 **人数必须守恒**：`cluster(...).map(\.volunteerCount).reduce(0,+)` 恒等于输入总和。
    /// 聚合代码最容易出的 bug 就是把「合并」写成「取第一个」，而那在画面上看不出来
    /// —— 光点位置对、数量对，只有数字悄悄变小了。检查钉在 `LanternMapTests` 里。
    static func cluster(_ sites: [Site], tier: Tier) -> [Cluster] {
        switch tier {
        case .site:
            return sites.map {
                Cluster(
                    id: $0.id,
                    label: $0.label,
                    longitude: $0.longitude,
                    latitude: $0.latitude,
                    volunteerCount: $0.volunteerCount
                )
            }
        case .region:
            let grouped = Dictionary(grouping: sites, by: \.region)
            return grouped.map { region, members in
                let total = members.reduce(0) { $0 + $1.volunteerCount }
                // 全组 0 人时退回简单平均，避免 0/0。假数据里不会发生，真实数据里会。
                let weight = total > 0 ? Double(total) : Double(members.count)
                let weighted: (Double, Double) = members.reduce(into: (0, 0)) { acc, site in
                    let w = total > 0 ? Double(site.volunteerCount) : 1
                    acc.0 += site.longitude * w
                    acc.1 += site.latitude * w
                }
                return Cluster(
                    id: region,
                    label: region,
                    longitude: weighted.0 / weight,
                    latitude: weighted.1 / weight,
                    volunteerCount: total
                )
            }
            .sorted { $0.volunteerCount > $1.volunteerCount }
        }
    }

    // MARK: - 文案

    /// 点击一束光之后唯一允许出现的文字。
    ///
    /// 🔴 红线出口：这里只能出现**地名 + 人数**。任何个人信息、头像、昵称、精确位置
    /// 都不得经过这个函数，也不得绕过它另起一处文案。
    static func caption(for cluster: Cluster) -> String {
        "\(cluster.label)，\(cluster.volunteerCount) 位志愿者"
    }

    /// 顶部那一行摘要。
    ///
    /// 🔑 **这一行是整个功能里对全盲用户唯一有价值的东西**，不是装饰。
    /// 09-11 报告 §5 的第 3 条反对意见逐字写着：「你所在的城市，有 37 位志愿者」这一句
    /// 对全盲用户的价值高于整张图，成本低一个数量级，且零合规敞口。
    /// 所以它排在无障碍树最前面，且不依赖任何视觉元素 —— 底图加载失败时它照样在。
    static func summary(_ sites: [Site]) -> String {
        let total = sites.reduce(0) { $0 + $1.volunteerCount }
        return "全国 \(sites.count) 个区县，共 \(total) 位志愿者亮着灯"
    }

    // MARK: - 假数据

    /// 原型假数据。**一个真实用户都没有。**
    ///
    /// ⚠️ 经纬度精确到 0.1°，是城市中心的公开常识值，**不是测量值** —— 原型验证的是
    /// 「灯火的视觉与交互成不成立」，几公里的偏差不影响这个判断。正式版这份数据来自后端的
    /// k 匿名聚合结果，届时连同 `Site` 的 id 一起换成行政区划码。
    ///
    /// 🚩 **刻意保留了西部的稀疏**（拉萨 3 人、乌鲁木齐 5 人、西宁 2 人）：
    /// 报告 §5 的第 1 条反对意见说的就是这件事 —— 夜光图上青海、西藏、新疆几乎全黑，
    /// 西部用户打开看到的是自己身处一片黑暗，**与「你不孤单」的意图正好相反**。
    /// 那条意见明说「需要产品方看过实测图后自己判断」，所以原型必须把这个场景呈现出来，
    /// 而不是撒一片均匀的假点把它藏掉。
    static let sampleSites: [Site] = [
        // 京津冀
        Site(name: "朝阳区", region: "北京", longitude: 116.5, latitude: 39.9, volunteerCount: 37),
        Site(name: "海淀区", region: "北京", longitude: 116.3, latitude: 40.0, volunteerCount: 29),
        Site(name: "西城区", region: "北京", longitude: 116.4, latitude: 39.9, volunteerCount: 14),
        Site(name: "和平区", region: "天津", longitude: 117.2, latitude: 39.1, volunteerCount: 11),
        Site(name: "桥西区", region: "河北", longitude: 114.5, latitude: 38.0, volunteerCount: 6),
        // 长三角
        Site(name: "徐汇区", region: "上海", longitude: 121.4, latitude: 31.2, volunteerCount: 33),
        Site(name: "浦东新区", region: "上海", longitude: 121.5, latitude: 31.2, volunteerCount: 41),
        Site(name: "静安区", region: "上海", longitude: 121.5, latitude: 31.2, volunteerCount: 18),
        Site(name: "鼓楼区", region: "江苏", longitude: 118.8, latitude: 32.1, volunteerCount: 16),
        Site(name: "姑苏区", region: "江苏", longitude: 120.6, latitude: 31.3, volunteerCount: 12),
        Site(name: "西湖区", region: "浙江", longitude: 120.1, latitude: 30.3, volunteerCount: 22),
        Site(name: "鄞州区", region: "浙江", longitude: 121.5, latitude: 29.9, volunteerCount: 8),
        // 珠三角
        Site(name: "天河区", region: "广东", longitude: 113.4, latitude: 23.1, volunteerCount: 27),
        Site(name: "南山区", region: "广东", longitude: 113.9, latitude: 22.5, volunteerCount: 31),
        Site(name: "福田区", region: "广东", longitude: 114.1, latitude: 22.5, volunteerCount: 19),
        // 中西部主要城市
        Site(name: "武昌区", region: "湖北", longitude: 114.3, latitude: 30.5, volunteerCount: 17),
        Site(name: "岳麓区", region: "湖南", longitude: 112.9, latitude: 28.2, volunteerCount: 9),
        Site(name: "锦江区", region: "四川", longitude: 104.1, latitude: 30.7, volunteerCount: 21),
        Site(name: "渝中区", region: "重庆", longitude: 106.6, latitude: 29.6, volunteerCount: 13),
        Site(name: "雁塔区", region: "陕西", longitude: 108.9, latitude: 34.2, volunteerCount: 15),
        Site(name: "云岩区", region: "贵州", longitude: 106.7, latitude: 26.6, volunteerCount: 5),
        // 东北
        Site(name: "和平区", region: "辽宁", longitude: 123.4, latitude: 41.8, volunteerCount: 10),
        Site(name: "南岗区", region: "黑龙江", longitude: 126.6, latitude: 45.8, volunteerCount: 7),
        // 西部 —— 刻意稀疏，见上面的注释
        Site(name: "天山区", region: "新疆", longitude: 87.6, latitude: 43.8, volunteerCount: 5),
        Site(name: "城关区", region: "西藏", longitude: 91.1, latitude: 29.7, volunteerCount: 3),
        Site(name: "城东区", region: "青海", longitude: 101.8, latitude: 36.6, volunteerCount: 2),
    ]
}
