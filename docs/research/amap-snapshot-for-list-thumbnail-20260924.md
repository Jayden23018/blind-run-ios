# 记录列表的路线缩略图能不能用高德截图（2026-09-24）

问题：跑后运动记录阶段 3，陪跑员记录行左侧 ≤ 64 点的路线缩略图（后端下发 `thumbnail`，GCJ-02），
用高德截图还是纯 SwiftUI `Path` 画。D2 要求高德 API 先查官方文档。

## 事实（本机 SDK 头文件 + 官方文档，均 2026-09-24 核实）

- 本机 `AMap3DMap-NO-IDFA 11.1.200`（`Podfile.lock:3`）。截图入口只有两类，**都要先有一个 `MAMapView` 实例**：
  - `MAMapView.takeSnapshotInRect:withCompletionBlock:` / `…timeoutInterval:completionBlock:`（`MAMapView.h:504`、`:516`），回调 `state` 0 = 载入不完整、1 = 完整；同步版 `takeSnapshotInRect:` 自 6.0.0 起 deprecated（`:494`）。
  - `MAMapSnapshot`（`MAMapSnapshot.h`，2022 年加入）：`- (instancetype)init:(MAMapView*)mapview`，`capture:topLeft:topRight:complete:`。同样挂在一个地图视图上。
- 官方开发指南《地图截屏功能》原话：地图截屏功能**依赖于地图显示，即：只有内容先显示在地图上，才能进行截屏**。
  <https://lbs.amap.com/api/ios-sdk/guide/interaction-with-map/map-screenshot>
- 官方示例（地图 + 自定义视图合成截图）：先 `takeSnapshotInRect:self.mapView.bounds`，再 `renderInContext` 叠加层合成。
  <https://lbs.amap.com/demo/sdk/screenshot-mapview-view>
- 高德**没有** `MKMapSnapshotter` 那种不依赖地图视图、可在后台线程直接出图的独立截图器（HANDOFF 6.1 写的 `MKMapSnapshotter` 在 D2 之后没有高德等价物）。

## 两种做法的代价

| | 纯 SwiftUI `Path` | 高德截图 |
|---|---|---|
| 画面 | 只有路线形状，无底图 | 底图 + 路线 |
| 实现 | 经纬度按包围盒归一化，一个 `Shape` | 需要一个离屏 `MAMapView`：加折线 → 调视野 → 等瓦片载入 → 截图 → 缓存；逐行串行 |
| 失败面 | 无网络依赖 | 瓦片没载完（`state == 0`）、离屏视图的瓦片加载行为未在本仓库验证、每行一次截图的内存与耗时 |
| 测试 | 单测可断言归一化 | 模拟器永久不可用（高德无 arm64-sim），只能真机目视 |
| 合规 | 不涉及地图底图 | 与 App 内现有高德地图同一套（已在用） |

结论：**两种都可行**，按任务书约定交给负责人选。倾向 `Path`（原型 `prototype.html` 的 `thumbSVG` 本身也是矢量画法，底图只是浅色块）。

## 负责人决定

**纯 SwiftUI `Path`**（负责人 2026-09-24 本会话拍板）。高德截图方案放弃，理由见上表：离屏地图 + 等瓦片 + 逐行截图的失败面，换来的只是 48 点大小的底图。
