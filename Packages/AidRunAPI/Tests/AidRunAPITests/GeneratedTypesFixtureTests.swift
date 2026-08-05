import Foundation
import XCTest

@testable import AidRunAPI

/// 拿 `blindRunTests/Fixtures/` 里的**真实后端字节**去解生成的类型。
///
/// 和 `ContractFixtureTests` 的分工：那边测手写解码路径，这边测生成类型。
/// 两者都必须留着 —— 一份测真实数据能不能被现有代码吃下，一份测契约推断出的
/// 结构对不对得上真实数据。任何一边单独绿都不能证明另一边。
///
/// 不复制 fixture 到包里：复制品会和 `blindRunTests/Fixtures/` 反向漂移，
/// 而漂移正是这次引入生成器要消灭的东西。用 `#filePath` 回仓库根目录取原件。
final class GeneratedTypesFixtureTests: XCTestCase {
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // AidRunAPITests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // AidRunAPI
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // 仓库根

    private func fixture(_ name: String) throws -> Data {
        let url = Self.repoRoot
            .appendingPathComponent("blindRunTests/Fixtures")
            .appendingPathComponent("\(name).json")
        return try Data(contentsOf: url)
    }

    private func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(type, from: fixture(name))
    }

    // MARK: - 裸响应

    func testBlindProfileFixtureDecodes() throws {
        let profile = try decode(Components.Schemas.BlindProfileResponse.self, from: "BlindProfileResponse__self")
        XCTAssertEqual(profile.name, "测试盲人")
        XCTAssertEqual(profile.verifyStatus, .VERIFIED)
        XCTAssertEqual(profile.visionLevel, .TOTAL_BLIND)
        XCTAssertEqual(profile.tetherPreference, .TETHER_ROPE)
        XCTAssertEqual(profile.hasGuideDog, false)
        // 后端真的会回 null，而不是省略字段。可空性必须解得动。
        XCTAssertNil(profile.specialNeeds)
    }

    func testVolunteerProfileFixtureDecodes() throws {
        let profile = try decode(Components.Schemas.VolunteerProfileResponse.self, from: "VolunteerProfileResponse__self")
        XCTAssertEqual(profile.name, "测试志愿者")
        XCTAssertEqual(profile.acceptsGuideDog, true)
        XCTAssertEqual(profile.availableTimeSlots?.isEmpty, true)
    }

    func testEmergencyContactListFixtureDecodes() throws {
        let contacts = try decode([Components.Schemas.EmergencyContactResponse].self, from: "EmergencyContactResponse__list")
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts.first?.name, "测试联系人")
        XCTAssertEqual(contacts.first?.isPrimary, true)
    }

    func testOrderHistoryFixturesDecode() throws {
        // fixture 叫 PagedOrderResponse，契约里的 schema 叫 PageOrderDetailResponse。
        // 名字对不上不等于结构对不上 —— 这条用例锁的就是「结构确实对得上」。
        for label in ["blind-history", "volunteer-history"] {
            let page = try decode(Components.Schemas.PageOrderDetailResponse.self, from: "PagedOrderResponse__\(label)")
            XCTAssertNotNil(page.content, "\(label) 的 content 解不出来")
        }
    }

    // MARK: - 信封响应

    /// 契约里只有 5 条端点是信封形态，legal-links 是其中之一，也是唯一有真实 fixture 的一条。
    func testLegalLinksEnvelopeFixtureDecodes() throws {
        let payload = try decode(
            Operations.getLegalLinks.Output.Ok.Body.jsonPayload.self,
            from: "LegalLinksResponse__public"
        )
        XCTAssertEqual(payload.value1.success, true)
        XCTAssertEqual(payload.value1.code, 200)
        XCTAssertNil(payload.value1.errorCode)
        // 载荷本身两个字段后端都回 null，信封解开后不能变成整个 data 缺失。
        XCTAssertNotNil(payload.value2.data)
        XCTAssertNil(payload.value2.data?.privacyPolicyUrl)
    }

    // MARK: - 未知枚举值（AGENTS.md / CLAUDE.md 红线）

    /// CLAUDE.md 的硬约束：「枚举解码遇未知值不许整条崩」，见 commit 4793805。
    /// 生成器产出的是 `@frozen` 封闭枚举，遇到契约里没有的值会抛错，
    /// 而抛错会让整条响应解不出来 —— 对盲人端就是「点了没反应」。
    ///
    /// 这条用例**锁定现状**：它断言的是「生成类型确实会崩」，不是「它没问题」。
    /// 若哪天生成器支持了开放枚举、或我们加了兜底，这条用例会失败，
    /// 那时候该做的是把它改成断言「降级到未知」，而不是删掉它。
    func testGeneratedEnumRejectsUnknownValue() throws {
        let payloadWithFutureEnumValue = Data("""
        {"name":"测试盲人","visionLevel":"MONOCULAR_BLIND"}
        """.utf8)

        XCTAssertThrowsError(
            try JSONDecoder().decode(Components.Schemas.BlindProfileResponse.self, from: payloadWithFutureEnumValue),
            "生成的封闭枚举遇未知值时若不再抛错，说明上游行为变了，这条用例的结论要重写"
        )
    }
}
