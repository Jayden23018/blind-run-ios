## Context

判据已由 #380 提供：`LocationService.isPreciseLocationOff`（已授权且 `accuracyAuthorization == .reducedAccuracy`）。云端求助用同一判据拦截并念 `EmergencySafetyCopy.locationUnavailable(.preciseLocationOff)`。「播报我的位置」是漏网的一处。

## Goals / Non-Goals

**Goals:** 精确位置关闭时，「播报我的位置」不说出任何从坐标推出的地名或坐标。

**Non-Goals:** 不改 WebSocket 位置上报在精确位置关闭时的行为、不改陪跑员端（#407）；不改云端求助路径。

## Decisions

- **判据放在函数入口，先于本机与服务端两条来源。** 两条来源在精确位置关闭时都不准（服务端那份来自本机的模糊上报），所以不是「本机跳过、退到服务端」，而是整段短路。备选「只跳过本机、仍走服务端」被否：服务端位置同样是区域代表点。
- **「正在获取当前位置」那句进行时也不说。** 答句不走网络、立即出声，进行时只会被马上打断，徒增一次中断。
- **文案单列一条 `EmergencySafetyCopy.locationAnnouncementPreciseLocationOff`**，句式照抄 `locationUnavailable(.preciseLocationOff)`，开头从「求助未发出」换成「念不出你的准确位置」，补「说明你周围的情况」（与 `locationAnnouncement(nil)` 一致）。不复用求助那句：这里没有求助被拦。
- **不申请临时精确位置**（负责人选定方案①）：系统框在紧急时刻抢读屏焦点；且系统可能不弹。

## Risks / Trade-offs

- [用户此刻确实需要位置，而 App 什么地点都不给] → 文案第一动作是拨打 120 / 110 并口述周围情况；根治路径（打开精确位置）放在句尾。
- [服务端此时可能握着一份更早、精确位置还开着时的准确位置] → 判不出那份样本采集时的精度，宁可不念。
