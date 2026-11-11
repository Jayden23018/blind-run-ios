# 不可用按钮的字要读得清（2026-11-11，#759）

**问题**：不可用的主按钮外层再压透明度，低视力用户读不出字。业界怎么处理？

**结论**：
- WCAG 对不可用控件不要求最低对比度，但这不等于可以淡到读不出；多篇资料建议标签对比度仍取 4.5:1。
- 不可用不能只靠「变淡」表达，要另有线索说明为什么点不了（缺什么）。
- 没找到 Apple 官方对不可用按钮的明文规定；第三方 HIG 摘要的说法没核官方原文，不采用。

**本仓库的取法**：只用样式自己的灰底灰字（亮 5.3:1、暗 6.3:1，`PrimaryButtonContrastTests`），去掉外层 0.45；读屏提示不变。

**来源**（2026-11-11 检索，只读到搜索结果摘要，未逐篇打开原文）：
- USWDS Disabled States Research Findings 2023：https://github-redirect.dependabot.com/uswds/uswds/wiki/Disabled-States-Research-Findings-2023
- Axess Lab「Disabled buttons suck」：https://axesslab.com/disabled-buttons-suck/
- Making Disabled Buttons More Inclusive：https://www.digitalthriveai.com/en-us/resources/web-development/making-disabled-buttons-more-inclusive/
