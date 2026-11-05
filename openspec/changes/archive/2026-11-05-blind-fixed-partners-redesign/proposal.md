## Why

盲人端「固定搭档」页把每个人做成一张卡，卡下面挂「取消收藏」「举报」「不再匹配此人」三枚按钮。一屏 3 位搭档就有 9 枚按钮，人反而看不清。陪跑员端 11-04 已照健康 App「共享」改成「列表只放人、操作进详情页」（#697）。负责人 2026-11-05 批准盲人端照同一做法重做（原话「按推荐开工」，Jayden23018/blind-run-ios#752），并定「取消固定搭档每次都先确认」。

## What Changes

- 列表只放人：顶部说明卡（「N 位固定搭档」+ 派单说明）；「固定搭档」「一起跑过的人」两组；每人一行（首字头像、掩码姓名、「连续 N 周 · 一起跑完 N 次」或「对方已退出固定搭档」或「还不是固定搭档」、箭头），整行进入详情页。
- 新增盲人端搭档详情页：头像、名字、设为搭档的日期；连续周数卡（格子）；「一起跑完 N 次」；举报、不再匹配此人一组；红字「取消固定搭档」单独一组。还不是固定搭档的人：64pt 主按钮「设为固定搭档」。
- **取消固定搭档每次先确认**（原来只在对方已退出时确认）。对方已退出时沿用现有那段更长的确认文案。
- 页面标题由「我的固定搭档」改成「固定搭档」（与「我的」里的方块同名）。
- 空态三种文案、加载失败「重新加载」、收藏与取消的接口、播报原样保留；空态改成一张说明卡。

## Capabilities

### New Capabilities
- `blind-fixed-partners`: 盲人端固定搭档列表与搭档详情页显示什么、操作放在哪、取消前怎么确认。

### Modified Capabilities
- `volunteer-secondary-pages`: 删掉「盲人端『我的固定搭档』的行为与外观 SHALL 不变」这一句（盲人端改由 `blind-fixed-partners` 约束）。

## Impact

- 代码：`blindRun/Shared/PartnerListViews.swift`（列表）、`blindRun/Shared/PartnerStreaks.swift`（取消确认文案）、新增盲人端详情页与文案文件。陪跑员端 `VolunteerPartner*` 不改。
- 接口：不变（`GET/PUT/DELETE /api/blind/favorite-volunteers`、`GET /api/blind/partners/streaks`）。
- 测试：`IncentiveAdoptionPartnerTests` 取消确认用例改为「每次都确认」；UI 用例 `testBlockingAPartnerRemovesTheRowWithoutLeakingStateToTheNext` 改为进详情页操作；新增列表与详情页的 UI 用例和无障碍审计。
