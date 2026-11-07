# 首页同时有几张待办预约怎么排（#825）

日期：2026-11-07。问题：盲人跑者最多同时 3 张未完成预约（`TOO_MANY_SCHEDULED_ORDERS`），首页现在只显示 `/api/orders/active` 给的一张。
负责人方案：「有几个预约就按照这个大小除个数去分配」，即首页那张卡的高度按张数平分。调研同类 App 与苹果自带 App 怎么做。

## 结论

**查到的官方来源里，没有一家按张数平分高度。** 做法只有三类：

1. **最近一张完整显示，其余进入口或列表**：MyChart（医院配置，Froedtert 帮助页：首页显示下一个预约，其余在「就诊」列表）。
2. **一个容器里叠放 / 翻页**：钱包的票据是一叠、可拖动重排；主屏小组件「智能叠放」只显示最相关的一个，上下滑看其余。
3. **高度随内容走**：HIG「实时活动」一页明说锁屏高度按内容动态变化；同时多个活动时最多 3 个，都缩成同一种 minimal 样式（系统层面的「同等待遇」，但那是空间极小的特例），并建议能合成一个活动就别拆成几个。

支持平分的只有间接证据：Siemens iX 设计系统要求一组卡片保持等大（不是预约场景）；灵动岛多活动时三个同样式。

## 对本项目的含义

- 读屏用户不靠高度认卡，靠第一句话。HIG VoiceOver 页：相关内容要分组成一个元素，可见内容变化要通知 VoiceOver ⇒ **每张一个元素、第一个词是时间**与哪种排法无关，都要做。
- 平分的真实风险在大字号：三等分后每张约 140pt，AX5 下放不下 ⇒ 实现必须是「至少分到这么高，放不下就长高、整页滚动」，不能写死高度裁字。
- 64pt 可点区是本仓库自己的门槛（HIG 只给 44×44pt），不是外部数字。
- 折中方案（推断，无来源直接支持）：最近一张保持完整大卡，其余缩成紧凑条目。与 MyChart、钱包、智能叠放「最近一张完整」一致。

## 各对象（证据级别）

| 对象 | 同时多张时怎么排 | 证据 | 来源 |
|---|---|---|---|
| 钱包 | 一叠，可拖动重排；系统不平分 | 官方（只证实拖动重排） | https://support.apple.com/guide/iphone/iphe7aa3336/12.0 |
| 日历「即将开始」小组件 | 未找到官方条数；用户说两条约会只显示一条 | 仅用户描述 | https://forums.macrumors.com/threads/help-up-next-widget.2136544 |
| 小组件智能叠放 | 自动显示最相关的一个，上下滑看其余 | 官方 | https://support.apple.com/guide/iphone/add-and-use-widgets-iphb8f1bf206/ios |
| 实时活动 / 灵动岛 | 最多 3 个，minimal 样式；锁屏高度随内容；建议合成一个 | 官方 HIG（页面日期 2026-10-13） | https://developer.apple.com/tutorials/data/design/human-interface-guidelines/live-activities.json |
| Uber Reserve | 官方只说首页点「Reserve」看详情；多张布局未找到 | 官方博客（只覆盖入口） | https://www.uber.com/au/en/blog/schedule-rides-in-advance-with-uber-reserve/ |
| 滴滴、Lyft、国内挂号与陪诊 App | 未找到 | — | — |
| MyChart | 首页下一个预约，其余在列表（各医院配置不同） | 医院帮助页（二手） | https://help.my.froedtert.com/hc/en-us/articles/42193180658203-How-do-I-find-my-appointments-in-MyChart ；https://austinregionalclinic.com/patient-guide/mychart-tips/view-upcoming-and-past-visits |
| Be My Eyes / Aira | 没有多张待办卡的做法 | 仅用户描述 | https://sites.google.com/site/iosandsightloss/be-my-eyes |
| HIG VoiceOver | 相关内容分组成一个元素；布局变化要通知 | 官方 | https://developer.apple.com/tutorials/data/design/human-interface-guidelines/voiceover.json |
| HIG 无障碍 | 默认控件 44×44pt，最小 28×28pt；字号至少支持放大 200% | 官方 | https://developer.apple.com/tutorials/data/design/human-interface-guidelines/accessibility.json |
| 卡片 vs 列表 | NN/g 把卡片定义为可变尺寸容器；Siemens iX 要求一组卡等大 | NN/g 视频摘要、设计系统文档（间接） | https://www.nngroup.com/videos/card-view-vs-list-view/ ；https://ix.siemens.io/docs/components/card/guide |

未找到、不能当结论用的：Lyft、滴滴、国内挂号与陪诊 App 的多张布局；日历小组件条数；HIG widgets 页原文（页面渲染不出）；钱包官方排序规则。
