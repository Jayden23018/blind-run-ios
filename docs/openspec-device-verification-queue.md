# OpenSpec 积压变更的设备验证队列

**建立日期**：2026-09-21
**用途**：14 个未归档 OpenSpec 变更共剩 36 条未打勾任务，其中 **29 条卡在同一件事上** ——
设备 `111` 离线、要插 USB、要人戴 VoiceOver 走一遍。分散在 14 个 `tasks.md` 里看不出这一点。
这份文档把它们按「一次能连着做完的事」归拢，**只做索引，不复制任务正文**（双写必漂移）。

> **这份文档是一次性的**：14 个变更归档完它就该删掉，不是长期清单。
> 与 [`pre-launch-checklist.md`](./pre-launch-checklist.md) 的分工：那份记上架三段路的待办，
> 这份只记「怎么把积压的 OpenSpec 变更推到能归档」。
>
> 工具已经有了，别另起炉灶：`scripts/device-test.sh`（先探活、锁屏立即失败、统计只认 result bundle）、
> skill `aidrun-ship-check`（输出验证结论的格式）。

---

## A. 插上 USB 敲一条命令就行，人不用盯（11 条）

`scripts/device-test.sh` 全量或按 `-only-testing:` 分目标。跑完回下面每行的位置打勾。

| 回哪打勾 | 验什么 |
|---|---|
| `enable-independent-sos-safely/tasks.md:58` | 6.6 真机批跑 —— **整个队列的头**，SOS 另外两条都指向它 |
| `enable-independent-sos-safely/tasks.md:54` | 6.2a 后台/锁屏下触发的用例（见 6.6） |
| `enable-independent-sos-safely/tasks.md:87` | 8.7 同 6.6，同一个阻塞项 |
| `enable-cross-turn-voice-correction/tasks.md:42` | 5.4 `blindRunTests/VoiceOrderWizardTests` |
| `enable-cross-turn-voice-correction/tasks.md:56` | 7.5 指向 5.4，一起打 |
| `gate-first-launch-with-privacy-consent/tasks.md:45` | 5.4 `testFirstLaunchBlocksTheLoginScreenUntilTheDisclosureIsAccepted` |
| `gate-first-launch-with-privacy-consent/tasks.md:48` | 5.5 全量 UI 用例 —— 确认同意门的默认跳过没把别的用例挡在门外 |
| `capture-order-end-location/tasks.md:47` | 6.5 `blindRunUITests`（原因记的是网络配对 → `Lost connection to testmanagerd`，插 USB 即解） |
| `capture-and-gate-runner-extra-needs/tasks.md:152` | 5.5 派单弹窗不出现自由文本（Mock） |
| `capture-and-gate-runner-extra-needs/tasks.md:165` | 6.2 上面 5.x 全部真跑过且非零执行 |
| `complete-blind-profile-and-contacts/tasks.md:57` | 6.2 引导式 onboarding / 审核三态 / 联系人操作的 Mock + UI 无障碍用例 |

🚩 `passed=0 failed=0` 一律当失败查 —— 这句在 `capture-and-gate-runner-extra-needs` 6.2 里已经写死了。

## B. 必须有人戴 VoiceOver 走一遍（13 条）

| 回哪打勾 | 验什么 |
|---|---|
| `enable-cross-turn-voice-correction/tasks.md:57` | 7.6 改时间只改时间 / 改终点定向追问 / 「算了不下了」取消。⚠️ 走真实大模型，Mock 证明不了 |
| `enable-one-utterance-booking/tasks.md:214` | 5.5 肯定词一次下单 / 说「修改」落逐项 / 拒麦克风权限只播一次原因 |
| `enable-one-utterance-booking/tasks.md:82` | 1B.7 读回念完整不被切（案例 J/K/L） |
| `disambiguate-same-name-start-place/tasks.md:64` | 6.3 「明天早上八点从万象城出发跑一个小时」→ 听到序号播报 → 说「第二个」能选中 |
| `capture-order-end-location/tasks.md:48` | 6.6 「从人民广场跑到五角场」→ 起终点没抽反 → 志愿者端看到「结束地点」行 |
| `capture-and-gate-runner-extra-needs/tasks.md:154` | 5.6 说一句带身体状况的整话，读回念得出原话 |
| `offer-keep-waiting-before-auto-cancel/tasks.md:85` | 5.7 `PENDING_MATCH` 订单点一次，有进行时反馈且订单没被取消 |
| `surface-planned-end-and-overdue-alert/tasks.md:73` | 5.1 `IN_PROGRESS` 按「重复当前状态」听得到结束时间 |
| `replace-placeholder-points-with-service-recognition/tasks.md:152` | 6.1 成就页遍历顺序、每档 label 语义完整 |
| `share-run-plan-with-emergency-contacts/tasks.md:122` | 5.1 分享按钮可达、hint 说清「先说明再生成」 |
| `gate-first-launch-with-privacy-consent/tasks.md:49` | 5.6 同意门每条告知独立焦点、拒绝按钮找得到 |
| `complete-blind-profile-and-contacts/tasks.md:63` | 6.5 真机 + 云端验证（`111` 与 `iPad Pro (2)`），含隐私复核 |
| `enable-live-escort-location-and-track-summary/tasks.md:67` | 6.6 云端探针 + 持续锁屏/后台双机验证（`111` 与 `iPad Pro (2)`）。**它是归档顺序的头，见 §E** |

**低视力目视（2 条，AX3 以上字号 + 深色模式）**：
`share-run-plan-with-emergency-contacts/tasks.md:125`（同意页不裁切）、
`surface-planned-end-and-overdue-alert/tasks.md:75`（状态卡多一行不裁切）。

## C. 要先跟后端约时间窗（1 条）

`enable-independent-sos-safely/tasks.md:56` —— 6.4 云端探针。
**不能随便打**：触发真实 SOS 会给紧急联系人发真短信并惊动客服。约好演练窗口再做。

## D. 跑完 A/B 才能写的验证结论（2 条）

按 skill `aidrun-ship-check` 的格式输出、贴真实测试输出：
`replace-placeholder-points-with-service-recognition/tasks.md:154`、
`share-run-plan-with-emergency-contacts/tasks.md:126`。

## E. 归档顺序（⚠️ 搞错会覆盖别人的 Scenario）

两条链，各自必须按箭头方向归档：

```
enable-live-escort-location-and-track-summary   （差 §B 最后一行那 1 条）
        └─→ offer-keep-waiting-before-auto-cancel
            （6.4 明写：MODIFIED 块已基于它那一版写，早归档会把它的两个 Scenario 覆盖回去）

enable-one-utterance-booking  →  enable-cross-turn-voice-correction  →  disambiguate-same-name-start-place
            （三者都 MODIFY 了 blind-runner-voice-first-experience；
              disambiguate 的 7.1 明写「本变更必须最后归档」）
```

对应的 4 条未打勾任务：`disambiguate-same-name-start-place/tasks.md:75`、
`offer-keep-waiting-before-auto-cancel/tasks.md:118` 与 `:123`、
`capture-and-gate-runner-extra-needs/tasks.md:168`。

## F. 跟设备无关的 3 条记账项

| 回哪打勾 | 现状（2026-09-21 核实） |
|---|---|
| `add-volunteer-online-training/tasks.md:77` | 8.5 提醒运维跑迁移 `0043` 并登记。**后端 `migrations/0043_volunteer_training.sql` 在、`README.md` 有登记，但 `migrations_applied.log` 这个文件根本不存在** —— 见下 |
| `capture-order-end-location/tasks.md:53` | 7.2 commit + push + PR。功能代码 `f8a3834 feat: 盲人端接入订单终点（结束地点）` 已在 `origin/main`，疑似已完成只差打勾，**但 6.5/6.6 未做，打了也归档不了**，留到设备 session 一起处理 |
| `replace-placeholder-points-with-service-recognition/tasks.md:155` | 6.3 同步 handoff + commit + push + PR。同上，等 6.1/6.2 |

🚩 **后端缺口，不属于本仓库但由这条扫出来**：`demo/migrations/README.md` 要求把执行过的迁移
登记进 `migrations_applied.log`，而那个文件**不存在**。所以「哪些迁移在生产跑过了」目前没有
任何机器可查的记录，全靠 README 的散文描述。要么建这个文件，要么把 README 里那句要求删掉。

---

## 已经解掉的（本轮）

- `enable-cross-turn-voice-correction/tasks.md:58` 7.7「先验生产是否已部署 08-09 那批」—— **已打勾**。
  2026-09-21 直连生产 ECS：JAR 构建于 2026-09-10 10:48、服务 2026-09-14 21:20:47 启动，
  后端 `origin/main` 在该构建点前最后一个提交是 `963ba37`（2026-09-10 10:41:57），
  08-09 那批远早于它。原文记的「最后一次核实是 08-06」已过期 35 天。
  ⚠️ 只解掉「不知道真机在验哪一版后端」这个未知，7.6 那一下人耳验证仍未做。
