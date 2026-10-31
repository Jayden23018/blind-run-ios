## ADDED Requirements

### Requirement: 「关于」页显示 App 名称和版本号

「关于」页 SHALL 显示 App 名称「助盲跑」和版本号，版本号 SHALL 取自安装包信息。所有构建 MUST NOT 显示「MVP」「Demo」字样。

#### Scenario: 打开「关于」页
- **WHEN** 用户打开「关于」页
- **THEN** 页面显示 App 名称和「版本 x.y」，不显示「助盲跑 MVP」和「iOS SwiftUI Demo」

#### Scenario: 安装包没有版本号
- **WHEN** 安装包信息里版本号缺失或为空
- **THEN** 页面显示「版本未知」，不显示空白

### Requirement: 「关于」页标明备案编号和查询网址

「关于」页 SHALL 显示完整 App 备案编号，编号 MUST 保留后缀。备案系统网址 `https://beian.miit.gov.cn/` SHALL 显示在编号下方，并 SHALL 用系统浏览器打开。这部分内容 MUST NOT 依赖登录态、网络请求或构建配置。

#### Scenario: 查看备案编号
- **WHEN** 用户打开「关于」页
- **THEN** 页面显示「粤ICP备20047259号-4A」，下方显示备案系统网址

#### Scenario: 点击查询网址
- **WHEN** 用户点击备案系统网址
- **THEN** 系统浏览器打开工信部备案查询页

#### Scenario: 读屏
- **WHEN** VoiceOver 用户浏览备案信息
- **THEN** 读屏念出完整编号，网址是可以双击激活的链接

### Requirement: 「关于」页公示语音下单使用的大模型

「关于」页 SHALL 公示语音下单使用的大模型名称和大模型备案号。

#### Scenario: 查看大模型公示
- **WHEN** 用户打开「关于」页
- **THEN** 页面显示「通义千问大模型」和备案号「ZheJiang-TongYiQianWen-20230901」
