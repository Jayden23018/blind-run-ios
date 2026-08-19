# 服务提供者端的紧急求助入口放在哪：同类产品怎么做

调研日期 2026-08-19 ｜ 只谈**服务提供者端（司机 / 陪同者）进行中页面的 SOS 入口位置与误触防护**

盲人端的按钮尺寸与信息密度不在本篇，见 [`blind-ui-visual-benchmark-20260808.md`](./blind-ui-visual-benchmark-20260808.md)；
信息架构与焦点数见 [`blind-voice-booking-ia-20260805.md`](./blind-voice-booking-ia-20260805.md)。

**起因**：AidRun 志愿者端「服务进行中」页面的「一键求助」是一个全宽 64pt 的红色 `PrimaryButton`，
浮在底部操作面板**上方**（`blindRun/Volunteer/VolunteerOrderFlowViews.swift:1471`），
垂直位置约在屏幕 30–36% 处，且随面板内容高度上下漂移。用户反馈「放在中间，不是很常见的位置」。
本篇要回答的是：常见的位置到底是哪儿。

---

## 0. 一句话结论

**四款产品全部把安全入口做成「地图角落的固定悬浮图标 + 独立二级页 / 二级确认」，没有一款把紧急按钮
混排进常规操作按钮列表。** 「紧急操作应与常规操作空间分离」这句话本身**查不到逐字的正式规范条款**
（Apple HIG / Material / NN/g 都没有点名回答），但破坏性操作分离摆放是设计系统文献里反复出现的共识。

---

## 1. 服务提供者端的 SOS 入口位置

| 产品 | 形态 | 位置 | 二级结构 |
|---|---|---|---|
| Uber Driver | 蓝色**盾牌图标**，固定悬浮 | 地图页**左下角** | 点开进 Safety Toolkit（紧急联系人 / 911 助手 / 事故上报） |
| Lyft Driver | 图标 | **右上角** | 点开展开 Emergency assistance 菜单 → 再点 Call 911 |
| 滴滴出行（司乘同架构） | 「安全中心」图标 | 行程页**左下角** | 独立子页面，「一键报警」是子页里最醒目的专门按钮 |
| Lyft + ADT「Emergency Help」 | 独立入口 | — | 一键联系 ADT 客服，同样脱离常规操作流 |

- Uber 2022 重新设计后统一为盾牌图标，官方说法是为「提升关键安全功能的可见性与可达性」
  [来源: https://www.uber.com/us/en/drive/safety/]
- Uber 官方描述用词是「点击地图屏幕上的盾牌图标」——固定悬浮图标，不是嵌入的操作按钮
  [来源: https://www.uber.com/us/en/newsroom/ubers-new-safety-toolkit/]
- Lyft 2018 上线时的形态是右上角图标 + 展开菜单
  [来源: https://www.lyft.com/hub/posts/emergency-assistance]
- Lyft 与 ADT 合作的 Emergency Help 作为独立入口深度集成
  [来源: https://www.lyft.com/blog/posts/lyft-launches-emergency-help]
- 滴滴的「安全中心」在打车 / 行程页左下角，一键报警在子页内
  [来源: https://iot.ofweek.com/2018-09/ART-132215-8110-30264771.html]

**查不到**：Noonlight / bSafe 作为「服务进行中页面」场景的入口位置 —— 它们是独立的个人安全 App，
没有「服务中页面」这个概念，不适用于本问题。

## 2. 「紧急按钮混在常规操作堆里」算不算反模式

**没有查到任何规范逐字写明「紧急操作应与常规操作空间分离」。** 这条按未证实对待，不要写进对外文档。

三条间接支撑同一方向的材料：

- Apple HIG（Action Sheets）：破坏性操作单独置顶 + 红色高亮，与底部的 Cancel 分开 —— 体现的是「按操作性质分区」
  [来源: https://codershigh.github.io/guidelines/ios/human-interface-guidelines/ui-views/action-sheets/index.html]
- 设计系统文献的共识：破坏性按钮应远离功能性按钮，相邻危险操作建议留 >8–16px 间距并视觉降权
  [来源: https://www.designsystemscollective.com/designing-better-buttons-how-to-handle-destructive-actions-d7c55eef6bdf]
- NN/g「User Control and Freedom」（十大可用性原则第三条）要求清晰标记的 emergency exit，
  隐含紧急类操作需要独立可辨识的位置
  [来源: https://www.nngroup.com/articles/user-control-and-freedom/]

## 3. 误触防护

| 产品 | 手段 |
|---|---|
| Uber | 盾牌 → 子菜单 → 再选「911 Assistance」，多级菜单 + 二次选择 [来源: https://www.uber.com/us/en/blog/ubers-emergency-button-and-the-technologies-behind-it/] |
| Lyft | 图标 → 菜单 → Call 911；触发后保护司机接单评分并事后邮件回访 [来源: https://www.lyft.com/hub/posts/emergency-assistance] |
| 滴滴 | 报警页顶部「谎报警情，依法追责」警示语 + iOS 系统层二次确认弹窗；全流程最快 4 次点击 [来源: https://iot.ofweek.com/2018-09/ART-132215-8110-30264771.html] |
| Noonlight | **长按（Hold Until Safe）**，松手后 10 秒内输入 4 位 PIN 解除，不输入即视为真实紧急直接派警 [来源: https://help.noonlight.com/en/articles/2114600-how-does-the-button-work] |
| bSafe | 触摸按钮或**语音口令**激活（手机在口袋里也能隐蔽触发）[来源: https://techglimpse.com/bsafe-free-help-app-android-ios-windows-alert-sos-guardian/] |

**查不到**：Life360 的 SOS 误触防护具体机制（本轮未覆盖）。

---

## 4. 对 AidRun 的适用性（哪些能抄、哪些不能）

**能抄**：悬浮图标 + 脱离常规操作按钮列表这一条，四款一致，直接采纳。

**不能照抄的两处，理由是语义不同**：

1. **我们志愿者端的 SOS 不是志愿者自己的逃生按钮，是代盲人发起求助**
   （后端自 commit `a5ba523` 起按订单参与方归属事件，`TriggerType.VOLUNTEER_BUTTON` 区分来源）。
   Uber / 滴滴司机端那个按钮保护的是按按钮的人自己。
2. **我们的误触代价比它们高**：后端对志愿者的 `action=FALSE_ALARM` 恒回 403
   `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`（一对一陪跑里志愿者可能就是威胁来源，撤销权只在受助者本人与客服手里）。
   ⇒ 志愿者按错了**自己撤不掉**。这让「远离拇指自然区」的收益比在打车场景里更大。

**已否决**：Noonlight 的长按 + PIN 解除。我们已有逐字锁定的二次确认弹窗（`AGENTS.md` §6），
再加一层长按会让真正需要求助时更慢，而 PIN 对盲人端不可用（志愿者端单独用一套又制造了两端不一致）。

**未采纳但记一笔**：滴滴的「谎报警情，依法追责」式警示语。我们的求助不直接报警（只记录事件 + 通知客服），
写这句话会夸大后果，与 §6「不得宣称任何未发生的事」冲突。
