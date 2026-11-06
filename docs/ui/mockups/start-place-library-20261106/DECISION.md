# 定稿记录

- 批准日期：2026-11-06
- 负责人原话：「定稿，开新会话」
- 批准的稿：`start-place-v2.png` / `start-place-v2.html`，全部屏：①A ② ③ ④ ⑤ ⑥。①B 是对照稿，不采用。
- 四项选择（AskUserQuestion，都选了推荐项）：保留顶部「现在默认从这里出发」卡；图标按地名自动配；本轮一起做「全部常用地点」列表页（左滑删除 + 读屏「删除」操作）；「添加常用地点」页的方块图标改成圆形。
- 稿里写明、随定稿一并批准的：收藏多时换行不横滑；AX 字号把圆排改成列表（用 `dynamicTypeSize.isAccessibilitySize`）；副标题写「离你 X 公里」，拿不到定位不写；删除不弹二次确认；删掉的是默认地点时改回当前定位并朗读。
- 尺寸依据：原稿存档的 `research/apple-maps-library-spec.md`（见文末）。

## 入库副本说明（#817 实现 PR）

- 这里的 `start-place-v2.html` / `start-place-v2.png` 是去敏副本：删掉了「参考 · 苹果地图」那一列（第三方截图不入库），示例地名换成通用名（如「城南书院」「滨海公园南门」「河畔绿道入口」），`current.png` 里的校名同样换掉。版式、尺寸、颜色、文案规则与原稿一致。
- 原稿在负责人本机设计存档 `~/Documents/aidrun-design-archive/2026-11-06-start-place-library/final/`。
- 尺寸依据（原稿同目录 `research/apple-maps-library-spec.md`）摘要：圆 60pt、圆下名称 15pt、副标题 13pt、卡片左右边距 16pt、列表行高 72pt、列表图标 30pt、卡底行 64pt 可点。
