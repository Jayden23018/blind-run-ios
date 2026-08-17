//
//  ContractFixtureTests.swift
//  blindRunTests
//
//  用**真实后端响应的原始字节**跑一遍生产解码路径。
//
//  为什么需要这个：`scripts/validate-spec-coverage.mjs` 比对的是**路径**，
//  而本仓库记录在案的契约事故几乎全在**字段/语义**层：
//
//    - `LocalDateTime` 带小数秒（`2026-08-04T11:40:42.644571`）解析不出，ISO 原串被念给盲人
//    - 枚举遇未知值让整条 payload 崩掉，订单地址/坐标/电话/计划时间一起丢
//    - `EmergencyContactResponse.phone` v1.5.0 起返回明文，前端仍当掩码处理
//
//  这些之所以能溜过去，是因为测试里的 JSON 全是**手写字面量** —— 手写的是「我以为后端发的」，
//  真实的是「后端真的发的」。小数秒那次，手写的是 `...:42`，服务器发的是 `...:42.644571`。
//
//  fixture 采集：`node scripts/capture-fixtures.mjs`（打真实后端，会脱敏）。
//  Xcode 同步文件组会自动把 Fixtures/*.json 打进测试包，不需要改 pbxproj。
//

import XCTest
@testable import blindRun

final class ContractFixtureTests: XCTestCase {

    /// 与 `URLSessionAPIClient` 里那个一致：裸 `JSONDecoder()`，没有任何 key/date 策略。
    /// 刻意不在测试里换一个「更宽容」的 decoder —— 那样测的就不是生产路径了。
    private let decoder = JSONDecoder()

    // MARK: - 注册表

    /// 文件名前缀（`__` 之前）→ 如何解码并检查它。
    ///
    /// 新采集的 fixture 如果前缀不在这里，测试会**失败**而不是跳过：
    /// 一个没人检查的 fixture 等于没有 fixture。
    private lazy var checkers: [String: (Data) throws -> Void] = [
        "OrderDetailResponse": { [self] data in
            let order = try decode(OrderDetailResponse.self, data)
            XCTAssertGreaterThan(order.orderId, 0, "orderId 必须有值")
            XCTAssertNotEqual(order.status, .unknown, "订单状态解成了 unknown —— 后端加了新状态而前端没跟上")
            // 小数秒回归：能拿到 plannedStart 就必须解得出日期，否则会把 ISO 原串念出来
            if let planned = order.plannedStart {
                XCTAssertNotNil(
                    planned.backendLocalDate,
                    "plannedStart「\(planned)」解不出日期。后端 LocalDateTime 取自 now() 时带小数秒，"
                        + "这是 String.backendLocalDate 存在的原因。"
                )
            }
        },
        "PagedOrderResponse": { [self] data in
            let page = try decode(PagedOrderResponse.self, data)
            // 空列表时下面的循环一条都不跑 —— 那不是通过，是没数据可验。
            // fixture 的价值全在真实内容上，空的等于没采。
            XCTAssertFalse(
                page.content.isEmpty,
                "订单列表 fixture 是空的，本条什么都没验证。换一个有历史订单的测试账号重采。"
            )
            for order in page.content {
                XCTAssertNotEqual(order.status, .unknown, "列表里出现 unknown 状态：orderId=\(order.orderId)")

                // 小数秒回归的**真实**覆盖点。
                // 这个断言原本只写在 OrderDetailResponse 的 checker 里，而只读端点清单
                // 根本采不到那个模型 —— 于是整个「防小数秒」的目的一直是空转的死代码。
                // 后端 LocalDateTime 取自 now() 时带小数秒（2026-08-04T11:40:42.644571），
                // 解不出来就会把 ISO 原串念给盲人听。
                for (field, value) in [
                    ("plannedStart", order.plannedStart),
                    ("createdAt", order.createdAt),
                    ("acceptedAt", order.acceptedAt),
                ] {
                    guard let value else { continue }
                    XCTAssertNotNil(
                        value.backendLocalDate,
                        "orderId=\(order.orderId) 的 \(field)「\(value)」解不出日期。"
                            + "这正是 String.backendLocalDate 存在的原因。"
                    )
                }
            }
        },
        "EmergencyContactResponse": { [self] data in
            let contacts = try decode([EmergencyContactResponse].self, data)
            XCTAssertFalse(contacts.isEmpty, "联系人列表不该是空的 —— 下单硬前置就是至少一个联系人")
            for contact in contacts {
                // 模型里这些字段是 Optional（后端可能省略），但真实响应里它们必须有值 ——
                // 「模型允许 nil」和「后端真的会发 nil」是两件事，只有 fixture 能区分。
                XCTAssertFalse(contact.name?.isEmpty ?? true, "联系人缺 name")
                // v1.5.0 起后端返回明文手机号，掩码是展示层的事。
                // 这里断言拿到的是可拨号的号码，而不是已经被谁掩过的 ***。
                let phone = contact.phone ?? ""
                XCTAssertFalse(phone.isEmpty, "联系人缺 phone")
                XCTAssertFalse(phone.contains("*"), "phone 应为明文，掩码只应发生在展示层")
            }
            // 「至多一个」而不是「恰好一个」：后端 setPrimary 做了互斥（不会出现 2 个），
            // 但从没设过主联系人时是 0 个 —— 而且那是后端显式处理的合法状态
            // （无主要联系人时紧急事件保持 PENDING 等客服）。断言成「恰好一个」会把
            // 一个正常的数据状态判成契约违约。
            XCTAssertLessThanOrEqual(
                contacts.filter { $0.isPrimary == true }.count, 1,
                "主联系人不该多于一个 —— 后端 setPrimary 的互斥失效了"
            )
        },
        "EmergencyTriggerResponse": { [self] data in
            let response = try decode(EmergencyTriggerResponse.self, data)
            XCTAssertNotNil(response.eventId, "求助响应缺 eventId")
        },
        "LoginResponse": { [self] data in
            let login = try decode(LoginResponse.self, data)
            XCTAssertFalse(login.token.isEmpty, "登录响应缺 token")
        },
        "CurrentUserResponse": { [self] data in
            _ = try decode(CurrentUserResponse.self, data)
        },
        "BlindProfileResponse": { [self] data in
            _ = try decode(BlindProfileResponse.self, data)
        },
        "VolunteerProfileResponse": { [self] data in
            _ = try decode(VolunteerProfileResponse.self, data)
        },
        "LegalLinksResponse": { [self] data in
            _ = try decode(LegalLinksResponse.self, data)
        },
        "ParseVoiceOrderResponse": { [self] data in
            _ = try decode(ParseVoiceOrderResponse.self, data)
        },
    ]

    // MARK: - 用例

    func testEveryCapturedFixtureDecodesThroughTheProductionPath() throws {
        let fixtures = try loadFixtures()

        for (name, data) in fixtures.sorted(by: { $0.key < $1.key }) {
            let model = String(name.split(separator: "_", omittingEmptySubsequences: true).first ?? "")
            guard let check = checkers[model] else {
                XCTFail(
                    "fixture \(name).json 的模型前缀「\(model)」不在 ContractFixtureTests.checkers 里。"
                        + "采集了却没人检查的 fixture 等于没采集 —— 补一条 checker，或删掉这个 fixture。"
                )
                continue
            }

            XCTContext.runActivity(named: "fixture \(name)") { _ in
                do {
                    try check(data)
                } catch {
                    XCTFail("fixture \(name).json 解码失败：\(error)")
                }
            }
        }
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        // 走生产的信封优先逻辑，不是裸 decoder.decode —— 信封与裸解的顺序本身就是契约的一部分。
        try APIPayloadDecoder.decodePayload(type, from: data, decoder: decoder)
    }

    private func loadFixtures() throws -> [String: Data] {
        let bundle = Bundle(for: Self.self)
        // 两处都找。Xcode 同步文件组把 .json 路由进 Resources phase 时，
        // 「扁平化拷到 bundle 根」和「保留 Fixtures/ 子目录」两种落点都可能出现，
        // 而猜错的后果是 urls(...) 返回空 → XCTSkip → 测试看着是绿的其实一条没验。
        let urls = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "json", subdirectory: "Fixtures") ?? [])

        var result: [String: Data] = [:]
        for url in urls {
            let name = url.deletingPathExtension().lastPathComponent
            // 只认 `<Model>__<label>.json`，避免把测试包里别的 json 资源也当成 fixture
            guard name.contains("__") else { continue }
            result[name] = try Data(contentsOf: url)
        }

        if result.isEmpty {
            // 刻意用 XCTFail 而不是 XCTSkip。
            // fixture 是随仓库提交的，跑到这里为空只有两种可能：json 没被打进 .xctest 包，
            // 或者有人把 Fixtures/ 删了 —— 两种都是真问题。
            // 而 skipped 在 scripts/device-test.sh 里**不算失败**（只看 FAILED>0），
            // 所以 XCTSkip 会让这道门看着是绿的却一条都没验。这正是它要防的那类假通过。
            XCTFail(
                """
                测试包里一个 fixture 都没有，本用例什么都没验证 —— 这不是通过。

                · 如果 blindRunTests/Fixtures/ 下有 .json 却没被加载：是打包问题，
                  检查它们有没有进 blindRunTests target 的 Resources build phase。
                · 如果目录本来就是空的：采集一次真实响应
                      node scripts/capture-fixtures.mjs            # 先 dry-run 看要打哪些端点
                      node scripts/capture-fixtures.mjs --write    # 真采（会脱敏）
                """
            )
        }
        return result
    }
}
