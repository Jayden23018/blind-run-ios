## ADDED Requirements

### Requirement: 两端订单页用同一种方式跟住一张单

跑者订单页与陪跑员订单页 SHALL 以相同的规则跟住手上这一单：协调器校验过的状态更新 SHALL 立即改本地状态，不等 REST 详情；协调器不发状态更新的事件（任一状态值未知、`fromStatus` 与本地不符、重复 `messageId`）SHALL NOT 改本地状态，只 MAY 触发一次刷新。协调器请求刷新这一单时，订单页 SHALL 重拉 `GET /api/orders/{id}`；进页时已挂着的刷新请求 SHALL 补拉一次。轮询兜底的间隔 SHALL 为 5 秒，停止条件按角色：跑者订单页在最近一次权威状态不再需要轮询时停，陪跑员订单页在拉到终态时停；登录暂缓中两端 SHALL NOT 轮询。刷新失败 SHALL 按 1、2、4 秒重试三次后放弃。订单页离开屏幕时 SHALL 停止轮询并停止接收对方位置，但 SHALL 继续接收这一单的状态更新，直到页面被释放。

#### Scenario: 状态推送先于详情生效
- **WHEN** 陪跑员订单页正在等一次很慢的详情请求，收到本单合法的 `ORDER_STATUS_CHANGED`（`DRIVER_ARRIVED` → `IN_PROGRESS`）
- **THEN** 页面立即显示 `IN_PROGRESS`
- **AND** 那次慢请求之后带回的旧状态 SHALL NOT 让页面退回 `DRIVER_ARRIVED`

#### Scenario: 推送里的状态值是未知值
- **WHEN** 跑者订单页收到本单的 `ORDER_STATUS_CHANGED`，`toStatus` 是客户端不认识的值
- **THEN** 页面上的状态不变，页面 SHALL NOT 变成空白
- **AND** 订单页重拉一次详情

#### Scenario: 通话磨合没成
- **WHEN** 跑者订单页收到本单 `PENDING_INTRO_CALL` → `PENDING_MATCH`
- **THEN** 页面显示等待匹配，SHALL NOT 显示 `REMATCHING` 的内容

#### Scenario: 跑者订单页的轮询停止
- **WHEN** 跑者订单页拉到的权威状态是不再需要轮询的状态
- **THEN** 下一轮之前停止轮询，不再发详情请求

#### Scenario: 陪跑员订单页的轮询停止
- **WHEN** 陪跑员订单页某一轮拉到 `COMPLETED`
- **THEN** 这一轮之后停止轮询

#### Scenario: 登录暂缓中不轮询
- **WHEN** 跑步中登录已过期、App 处于暂缓状态时打开任一端订单页
- **THEN** 订单页连第一次详情请求也不发

#### Scenario: 进页前已经挂着的刷新
- **WHEN** 订单页打开之前，协调器已因重连请求刷新这一单
- **THEN** 订单页打开后拉一次详情，并在拉到权威结果后清掉这条刷新请求

#### Scenario: 页面被盖住时的状态推送
- **WHEN** 陪跑员订单页上面推入了另一个页面（订单页 ViewModel 仍在），收到本单 `REMATCHING`
- **THEN** 订单页 ViewModel 仍收到这条状态更新
- **AND** 对方位置标记已清，不再更新

### Requirement: 状态变化句只念一次，订单页开着时由订单页念

同一次状态变化 SHALL 只念一句。本单的订单页 ViewModel 存在时，状态变化句 SHALL 由订单页念，首页 SHALL NOT 念这一单的状态句（首页的「当前订单」照常更新）；订单页不存在时 SHALL 由首页念。这个判断 SHALL 基于「本单的订单页是否在跟这一单」，SHALL NOT 依赖两处收到推送的先后顺序。

#### Scenario: 陪跑员订单页开着时跑者取消
- **WHEN** 陪跑员订单页开着，收到本单 `CANCELLED`（跑者取消）
- **THEN** 只念订单页那句「不算你的取消」的整句
- **AND** 首页 SHALL NOT 再念通用的「这一单已取消」

#### Scenario: 陪跑员订单页没开时跑者取消
- **WHEN** 陪跑员在首页，订单页没有打开，收到本单 `CANCELLED`
- **THEN** 首页念一次通用的取消句

#### Scenario: 跑者订单页开着时通话磨合没成
- **WHEN** 跑者订单页开着，收到本单 `PENDING_INTRO_CALL` → `PENDING_MATCH`
- **THEN** 念订单页那句（含「本次见面安排未生效」或本轮结束的说明）
- **AND** 首页 SHALL NOT 念它自己的状态句

#### Scenario: 失联转走后紧跟重派
- **WHEN** 陪跑员订单页开着，先收到 `ORDER_VOLUNTEER_LOST`，紧接着收到本单 `REMATCHING`
- **THEN** 订单页按失联静默离开，SHALL NOT 念「订单已取消」
