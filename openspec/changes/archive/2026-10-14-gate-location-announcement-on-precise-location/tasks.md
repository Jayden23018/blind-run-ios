## 1. 实现

- [x] 1.1 `EmergencySafetyCopy` 新增精确位置关闭时的播报文案
- [x] 1.2 `announceCurrentLocation()` 入口判 `isPreciseLocationOff`：不逆地理、不请求服务端、念 1.1 文案

## 2. 验证

- [x] 2.1 单测：精确位置关闭 → 不调逆地理、不调 `orderLocationAddress`、念 1.1 文案
- [x] 2.2 单测对照：精确位置开着 + 真实本机坐标 → 照常逆地理并念地名
- [x] 2.3 验红：在已提交基线上打回 1.2，确认 2.1 变红、2.2 仍绿
- [x] 2.4 真机跑 `LocationAddressAnnouncementTests`，`passed>0 failed=0`
- [x] 2.5 单测：没注入定位服务时不问服务端、念「暂时定位不到」（安全复核），已验红
