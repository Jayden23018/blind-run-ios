## 1. 协调器

- [x] 1.1 `LiveEscortSessionCoordinator` 加同步谓词 `needsTrackConsentForActiveOrder` 与回调 `onVolunteerTrackConsentQuestion`（开始问 / 拒绝）

## 2. 陪跑员首页

- [x] 2.1 恢复待命那一问等首份摘要、在把订单交给协调器之后再判，同行态要问时让开
- [x] 2.2 收到「开始问」收起首页手上的同意请求；收到「拒绝」关接单开关、留下不念的说明、不再追问

## 3. 验证

- [x] 3.1 单测：只问一次 / 同行态拒绝关开关且不念 / 同行态同意不另问 / 首页那张已弹时被收起
- [x] 3.2 UI 用例：`available: true` + `DRIVER_EN_ROUTE`，同意页始终只有一张，拒绝后不再出现
- [x] 3.3 真机跑覆盖到的单测与 UI 用例，新用例在已提交基线上验红
