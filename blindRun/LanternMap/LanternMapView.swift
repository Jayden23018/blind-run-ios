import SwiftUI

// MARK: - 「一束光地图」原型视图

/// 方向 C「灯火」的可交互原型：夜光影像当底，志愿者的冷青光叠在暖橙灯火之上，
/// 可捏合缩放、拖动，点一束光念出「北京朝阳区，37 位志愿者」。
///
/// 数据层、合规与隐私约束见 `LanternMap`（本文件只负责画和点）。
///
/// ## 为什么不用高德 / 不用任何地图 SDK
///
/// 原型要验证的是「灯火的视觉与交互成不成立」，而那不需要地图引擎：
/// 夜光影像是等距圆柱投影，经纬度 → 像素是**线性映射**（`LanternMap.normalizedPoint`）。
/// 接了高德反而要先解掉 09-11 报告 §6 列的投影对齐缺口（等距圆柱 叠 Web 墨卡托/GCJ-02），
/// 而那件事和「好不好看」无关。**正式版要不要接高德是另一个决定**，见 `LanternMap` 的
/// 合规注释 —— 报告 §4.1 给的兜底方案正是「C 的视觉 + B（高德幻影黑）的合规路径」。
///
/// ## 已知缺口（原型没解决，不要当成做完了）
///
/// 🚩 **框里最亮的一块不是中国。** 2026-09-21 裁出底图后目视确认（校验方法见下），
/// `GeoBounds.china` 这个矩形里同时装进了印度、孟加拉、东南亚、日韩的灯火，
/// 而**印度—孟加拉那一片比中国西部亮得多**，画面左下角最亮的区域根本不在国境内。
/// 这稀释的是整个隐喻：「万家灯火」里有一大半不是我们的人。
///
/// 三份报告都没提这件事 —— 它们看的是「中国的轮廓由真实灯火构成」这一面，
/// 没看框外。**它没有便宜的解法**：收窄裁剪框会切掉喀什（75.9°E）和云南南部，
/// 而给中国区域做亮度蒙版等于自绘国界 —— 09-11 报告第一部分 §1.5 明确说那是三条路里
/// 合规风险最高的一条（2018 年 8 起「问题地图」通报全是自制地图）。
/// ⇒ **记录，不改**，交给产品方连同西部那个问题一起判断。
///
/// 🚩 **低视力通道没有验收。** 09-11 报告 §5 第 2 条：深色底 + 低 alpha 辉光在 WCAG 对比度上
/// 大概率不合格，而 `VisionLevel.LOW_VISION` 在本 App 的数据模型里是一等公民
/// （记忆 `low-vision-visual-channel-unaudited`）。本原型只保证**文字层**达标
/// （白字压 `#0A0E17` 约 18:1），光点本身的对比度**未测量**。
/// 若这张图的受众包含低视力用户，需要一个高对比模式，而那个模式会牺牲掉全部「精致感」。
struct LanternMapView: View {

    // MARK: 调色板
    //
    // 🔴 **这一屏偏离了 `docs/ui/design-direction.md` §2 的 09-08 裁决**（两端跟随系统明暗，
    // 盲人端不强制深色），偏离写在这里而不是悄悄做掉：
    //
    // 方向 C 的前提是夜光卫星影像当底，而**夜光影像没有浅色版本** —— 它拍的就是夜晚。
    // 跟随系统明暗在这一屏无法成立，不是没去做。
    //
    // 但那条裁决的理由在这里**一条都没失效**：低视力不是单一症状，羞明的人需要深色，
    // 视野缺损或对比敏感度下降的人需要浅色高亮度。所以这个偏离有代价，且代价落在后一半人身上。
    // 🚩 **正式版必须二选一**，不能就这么放着：
    //   ① 做一个浅色/高对比模式（09-11 报告 §5 第 2 条已经预告：那个模式会牺牲掉全部精致感），
    //      或 ② 这张图在亮色模式下退回报告 §5 第 3 条那句纯文字摘要 —— 那句对全盲用户
    //      本来就比整张图更有价值，对需要浅色的低视力用户同样成立。
    //
    // 色值本身不进 `AppColors`，理由和 `AppColors.activeRunSurface` 那一族完全相同：
    // 它们是某一屏专属的固定表面色，从不当前景压在系统的亮/暗背景上，塞进 `tones` 表
    // 只会得到一条方向反了的断言。而且这是原型 —— 原型的色留在原型文件里，删起来干净。
    //
    // 过 §2「新增强调色的门槛」：5 个语义色（primary 蓝 / destructive 红 / warning 橙 /
    // success 绿 / textSecondary 灰）都表达不了「一束光」—— 它不是状态也不是操作，
    // 是**数据编码色**，且 09-11 报告 §3 维度 5/6 要求它与底层暖橙灯火拉开色温（冷青）。
    // 这不是装饰性色彩：换成 `primary` 蓝会和灯火混成一片。

    /// 画布底色。夜光影像加载不出来时也是它。
    /// 不用纯黑：报告 §2.1 的 Stellarium 教训是「天空是极微妙的深蓝紫渐变，不是纯黑」。
    private static let canvasColor = Color(red: 0.039, green: 0.055, blue: 0.090) // #0A0E17
    /// 光点的芯。冷青。
    private static let coreColor = Color(red: 0.75, green: 1.0, blue: 0.98)
    /// 光晕。同色相、极低 alpha，靠叠加变亮而不是靠调亮单点（报告 §4.3）。
    private static let glowColor = Color(red: 0.25, green: 0.83, blue: 0.78) // #3FD3C6

    private let sites: [LanternMap.Site]
    private let basemap: UIImage?

    @State private var scale: Double = 1
    @State private var gestureScale: Double = 1
    @State private var offset: CGSize = .zero
    @State private var gestureOffset: CGSize = .zero
    @State private var selection: LanternMap.Cluster?

    init(sites: [LanternMap.Site] = LanternMap.sampleSites, basemap: UIImage? = LanternBasemap.load()) {
        self.sites = sites
        self.basemap = basemap
    }

    private var liveScale: Double { min(max(scale * gestureScale, 1), 8) }

    private var clusters: [LanternMap.Cluster] {
        LanternMap.cluster(sites, tier: LanternMap.tier(forScale: liveScale))
            .sorted { $0.volunteerCount > $1.volunteerCount }
    }

    var body: some View {
        VStack(spacing: 0) {
            summaryHeader
            mapSurface
            footer
        }
        .background(Self.canvasColor.ignoresSafeArea())
    }

    // MARK: - 摘要行

    /// 🔑 **整张图里对全盲用户唯一有价值的东西**（报告 §5 第 3 条），所以它排在最前面。
    ///
    /// 位置不是审美问题：VoiceOver 的遍历顺序跟着**绘制顺序**走
    /// （记忆 `swiftui-traversal-order-follows-paint-order`：`accessibilitySortPriority`
    /// 在跨叠放层时是空操作）。把它叠成 overlay 就会排到地图后面，
    /// 所以它必须是 `VStack` 的第一个孩子，而不是压在地图上的一层。
    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("一束光")
                .font(AppFonts.title())
            Text(LanternMap.summary(sites))
                .font(AppFonts.body())
                .foregroundColor(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .foregroundColor(.white)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 地图

    private var mapSurface: some View {
        GeometryReader { geo in
            let frame = Self.basemapRect(in: geo.size)
            ZStack {
                // 底图与光点都是**装饰层**：VoiceOver 走的是上面那层透明按钮。
                // 装饰底层只能 `accessibilityHidden` —— 四种排序写法真机全废，见上面那条记忆。
                basemapLayer(frame: frame, container: geo.size)
                lanternLayer(frame: frame, container: geo.size)
                    .accessibilityHidden(true)

                tapTargets(frame: frame, container: geo.size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(zoomGesture.simultaneously(with: panGesture))
        }
        .overlay(alignment: .bottom) { selectionCard }
    }

    @ViewBuilder
    private func basemapLayer(frame: CGSize, container: CGSize) -> some View {
        if let basemap {
            Image(uiImage: basemap)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: frame.width * liveScale, height: frame.height * liveScale)
                .offset(liveOffset)
                .accessibilityHidden(true)
        } else {
            // 这个降级分支**真的会被走到**（素材不在 git 里，见 LanternBasemap 的注释），
            // 所以它必须说清楚「你现在看到的不是方向 C」——
            // 否则下一个人会对着一块纯黑判断「灯火方向不成立」。
            Text("未找到夜光底图素材，当前是纯深色画布（方向 B 的形态，不是 C）。\n生成方式见 scripts/crop-lantern-basemap.sh")
                .font(AppFonts.caption())
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.7))
                .padding(24)
        }
    }

    private func lanternLayer(frame: CGSize, container: CGSize) -> some View {
        Canvas { context, _ in
            // 密集处靠叠加自然变亮，不是把单点调亮 —— 报告 §4.3，也正是 deck.gl 那 85 万点
            // 好看的原因。单点调亮会在稀疏处刺眼、在密集处糊成一片白。
            context.blendMode = .plusLighter
            for cluster in clusters {
                let point = displayPoint(cluster, frame: frame, container: container)
                guard container.contains(point, slack: 40) else { continue }
                let radius = Self.radius(forCount: cluster.volunteerCount)

                // 双层辉光（报告 §4.3，学 Mapsmith）：宽而暗的底 + 窄而亮的芯。
                // 不是单纯调高亮度 —— 少了底层那一圈，点会像素子弹孔而不像灯。
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - radius * 4.2,
                        y: point.y - radius * 4.2,
                        width: radius * 8.4,
                        height: radius * 8.4
                    )),
                    with: .radialGradient(
                        Gradient(colors: [Self.glowColor.opacity(0.28), Self.glowColor.opacity(0)]),
                        center: point,
                        startRadius: 0,
                        endRadius: radius * 4.2
                    )
                )
                context.fill(
                    Path(ellipseIn: CGRect(
                        x: point.x - radius * 0.6,
                        y: point.y - radius * 0.6,
                        width: radius * 1.2,
                        height: radius * 1.2
                    )),
                    with: .color(Self.coreColor)
                )
            }
        }
    }

    /// VoiceOver 与手指真正碰到的那一层。
    ///
    /// 用一组透明按钮而不是在 `Canvas` 里做命中测试，理由有两个，第二个更重要：
    /// ① `Canvas` 画的东西不进无障碍树，自己算命中还得再自己造一套无障碍元素；
    /// ② 记忆 `xcuitest-cannot-invoke-accessibility-actions`：`tap()` 注入的是物理触摸、
    ///    不经过 accessibility action ⇒ 「指针路径」和「辅助技术路径」必须是**同一个** `Button`，
    ///    否则 UI 测试只能验形状、验不了行为。
    ///
    /// 按人数降序声明，所以 VoiceOver 从灯最亮的地方开始念（遍历顺序 = 绘制顺序）。
    /// 触达 64pt 是盲人端的下限（不是 HIG 的 44pt）。
    private func tapTargets(frame: CGSize, container: CGSize) -> some View {
        ForEach(clusters) { cluster in
            let point = displayPoint(cluster, frame: frame, container: container)
            if container.contains(point, slack: 0) {
                Button {
                    selection = cluster
                } label: {
                    Color.clear
                        .frame(width: 64, height: 64)
                        .contentShape(Circle())
                }
                .position(point)
                .accessibilityLabel(LanternMap.caption(for: cluster))
                .accessibilityIdentifier("lantern.site.\(cluster.id)")
            }
        }
    }

    // MARK: - 选中卡片

    @ViewBuilder
    private var selectionCard: some View {
        if let selection {
            // 🔴 红线：这里只允许出现 `LanternMap.caption(for:)` 的输出。
            // 不得加头像、昵称、精确位置，也不得在这里另起一处文案绕过那个函数。
            HStack {
                Text(LanternMap.caption(for: selection))
                    .font(AppFonts.body())
                    .foregroundColor(.white)
                Spacer(minLength: 12)
                Button("关闭") { self.selection = nil }
                    .font(AppFonts.body())
                    .foregroundColor(Self.glowColor)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.10))
            .cornerRadius(14)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .accessibilityIdentifier("lantern.selection")
        }
    }

    // MARK: - 页脚（合规载体，不是装饰）

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 🔴 审图号的位置：可缩放中国地图必须在**左下角**标注审图号
            // （09-21 裁定免审口子不成立，见 `LanternMap` 的合规注释）。
            // 原型没有审图号，所以这里写的是这个事实本身 —— 留一行空位假装合规比不留更糟。
            Text("原型 · 未送审，无审图号 · 数据为假数据，非真实用户")
            // NASA 素材的两个使用条件之一：必须注明来源（另一条是不得暗示 NASA 背书）。
            Text("底图：NASA Earth at Night (Black Marble)")
        }
        .font(AppFonts.caption())
        .foregroundColor(.white.opacity(0.7))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - 手势

    private var liveOffset: CGSize {
        CGSize(width: offset.width + gestureOffset.width, height: offset.height + gestureOffset.height)
    }

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { gestureScale = $0 }
            .onEnded { _ in
                scale = liveScale
                gestureScale = 1
            }
    }

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { gestureOffset = $0.translation }
            .onEnded { _ in
                offset = liveOffset
                gestureOffset = .zero
            }
    }

    // MARK: - 几何

    /// 光点在屏幕上的位置。
    ///
    /// 必须和 `basemapLayer` 里 `Image` 的变换**逐字一致**：
    /// `.frame(fitted * scale)` + `.offset` 等价于「以容器中心为锚点缩放再平移」，
    /// 下面这个式子就是它展开后的形式。两边任何一边改了变换，光点就会离开灯火 ——
    /// 而那在画面上不像 bug，像「数据不准」，没人会去怀疑这两处不同步。
    private func displayPoint(_ cluster: LanternMap.Cluster, frame: CGSize, container: CGSize) -> CGPoint {
        let n = LanternMap.normalizedPoint(longitude: cluster.longitude, latitude: cluster.latitude)
        return CGPoint(
            x: (n.x - 0.5) * frame.width * liveScale + container.width / 2 + liveOffset.width,
            y: (n.y - 0.5) * frame.height * liveScale + container.height / 2 + liveOffset.height
        )
    }

    /// 底图按 `aspectRatio(.fit)` 落在容器里之后的实际尺寸。
    ///
    /// 不能直接拿容器尺寸当画布：`fit` 会留黑边，而光点若按容器算坐标就会整体拉伸、离开灯火。
    static func basemapRect(in container: CGSize) -> CGSize {
        let aspect = LanternMap.basemapAspectRatio
        guard container.width > 0, container.height > 0 else { return .zero }
        if container.width / container.height > aspect {
            return CGSize(width: container.height * aspect, height: container.height)
        }
        return CGSize(width: container.width, height: container.width / aspect)
    }

    /// 光晕半径的上限。
    ///
    /// 🔑 **没有这个上限时，规模一大整张图就糊成白团，底层灯火完全看不见** ——
    /// 而「底层灯火撑着画面」正是方向 C 被选中的**全部理由**。也就是说：不封顶的话，
    /// 这个功能会在用户变多之后亲手毁掉自己成立的前提。
    ///
    /// 2026-09-21 用 `scripts/render-lantern-scale-preview.sh` 渲 40/200/1000/5000 四档
    /// 目视确认：省级聚合下 5000 人分到 43 处 ≈ 116 人/处，不封顶时半径 9.5pt、
    /// 光晕直径 80pt，长三角连成一坨白；封到 6pt（光晕直径 50pt）之后底图重新看得见，
    /// 光点仍有层次。
    ///
    /// 这也正是报告 §4.3 引用 Stellarium 的教训原话：
    /// 「密集处靠叠加自然变亮，而不是把单点调亮」—— 而光晕半径 = 4.2r、r 又随人数一路涨，
    /// 等于恰好在做它反对的事。封顶之后密集处仍然更亮（多个光晕叠加），只是不再更大。
    static let maximumRadius: Double = 6.0

    /// 光点半径。开方而不是线性 —— 人数差 10 倍时面积差 10 倍，半径只差 3 倍，
    /// 否则上海那一簇会把半个长三角盖住。开方之上还要封顶，理由见 `maximumRadius`。
    static func radius(forCount count: Int) -> Double {
        min(2.0 + Double(count).squareRoot() * 0.7, maximumRadius)
    }
}

private extension CGSize {
    /// 点是否还在容器里（`slack` 给绘制层留一点边距，免得半个光晕在边缘被硬切掉）。
    func contains(_ point: CGPoint, slack: Double) -> Bool {
        point.x >= -slack && point.y >= -slack && point.x <= width + slack && point.y <= height + slack
    }
}

// MARK: - 底图素材

enum LanternBasemap {
    static let resourceName = "LanternBasemapChina"
    static let resourceExtension = "jpg"

    /// 从 bundle 读裁好的中国区域夜光影像。
    ///
    /// ⚠️ **这个文件不在 git 里**（和 `docs/ui/reference-screenshots/` 同样的理由：体积）。
    /// 没有它时 `LanternMapView` 会走一个**说明自己不是方向 C** 的降级分支，
    /// 而不是安静地显示一块黑 —— 安静的黑会让人对着它判断「灯火方向不成立」。
    /// 生成：`scripts/crop-lantern-basemap.sh`（从 NASA 全球图裁 `GeoBounds.china` 那一块）。
    ///
    /// 走资源目录而不是 `Assets.xcassets`，和 `WeChatShareCard.thumbnailData` 同一个理由：
    /// asset catalog 会在构建期重新压缩，而这里要的是裁图脚本产出的那张图本身。
    static func load(bundle: Bundle = .main) -> UIImage? {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

#if DEBUG
struct LanternMapView_Previews: PreviewProvider {
    static var previews: some View {
        LanternMapView()
            .preferredColorScheme(.dark)
    }
}
#endif
