# 高德 iOS 3D SDK：配速渐变折线、白色描边、路线标注（2026-09-24）

问题：跑后详情页（阶段 4，D2）要画「白色描边 + 按配速渐变着色」的路线、公里标记、起终点、休息点。
高德有没有这些能力、API 叫什么？本机 SDK：`Pods/AMap3DMap-NO-IDFA` 11.1.200。

## 结论

| 需求 | 做法 | 来源 |
|---|---|---|
| 配速渐变 | `MAMultiPolyline.polylineWithCoordinates:count:drawStyleIndexes:` + `MAMultiColoredPolylineRenderer`（`strokeColors`，`gradient = YES`）。颜色锚在索引点上，索引点之间插值 | 本机头文件 `MAMultiPolyline.h`、`MAMultiColoredPolylineRenderer.h`；官方 3D 类参考 |
| 性能约束 | 索引点**不参与抽稀**，「请尽量少的设置索引点的数量」；连续重复点必须去重，否则绘制有问题 | 同上（头文件逐字） |
| 线帽/连接 | `MAMultiColoredPolylineRenderer` 只支持 round join / round cap，设别的无效 | 官方类参考（2D 页，搜索结果摘录） |
| 白色描边 | **没有** border/outline 属性（`MAPolylineRenderer` / `MAOverlayPathRenderer` 只有 `strokeColor`/`lineWidth`/`lineJoinType`/`lineCapType`/`lineDashType`；`sideColor` 属于 3D 箭头线）⇒ 只能在下面垫一条更宽的白色 `MAPolyline`，叠放顺序靠 `addOverlay` 的先后或 `insertOverlay:belowOverlay:` | 本机头文件 `MAPolylineRenderer.h`、`MAOverlayPathRenderer.h`、`MAMapView.h:886-978` |
| 标注 | `MAAnnotationView` + 自绘 `image`；`centerOffset` 调锚点；`zIndex` 只在 `viewForAnnotation` / `didAddAnnotationViews` 里设才生效 | `MAAnnotationView.h:34-56` |
| 视野避开底部卡片 | `setVisibleMapRect:edgePadding:animated:`（仓库已在用） | `MAMapView.h:373` |

指南页 `lbs.amap.com/api/ios-sdk/guide/draw-on-map/draw-polyline` 只讲单色/纹理折线，不讲渐变与描边 —— 渐变只在类参考里。

## 落地取舍

- 索引点按「配速颜色量化档位变化的点」放（不是每个点都放），把索引点数量压在几十个以内。
- 描边线与配速线是两个 overlay，高亮某一公里是第三个 overlay（叠在最上面）。

## 来源

- 本机头文件（11.1.200）：`MAMultiPolyline.h`、`MAMultiColoredPolylineRenderer.h`、`MAPolylineRenderer.h`、`MAOverlayPathRenderer.h`、`MAMapView.h`、`MAAnnotationView.h`、`MAConfig.h:63-64`（`MA_INCLUDE_OVERLAY_MAMultiPolyline 1`）
- https://a.amap.com/lbs/static/unzip/iOS_Map_Doc/AMap_iOS_API_Doc_3D/interface_m_a_multi_polyline.html
- https://a.amap.com/lbs/static/unzip/iOS_Map_Doc/AMap_iOS_API_Doc_2D/interface_m_a_multi_colored_polyline_renderer.html
- https://lbs.amap.com/api/ios-sdk/guide/draw-on-map/draw-polyline
