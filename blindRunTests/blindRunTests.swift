//
//  blindRunTests.swift
//  blindRunTests
//
//  Created by Jerry on 5/18/26.
//

import XCTest
@testable import blindRun

@MainActor
final class blindRunTests: XCTestCase {

    func testPhoneLoginRequestUsesOpenAPICamelCaseKeys() throws {
        let request = PhoneLoginRequest(
            phoneNumber: "13800138000",
            verificationCode: "123456"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(json["phoneNumber"], "13800138000")
        XCTAssertEqual(json["verificationCode"], "123456")
        XCTAssertNil(json["phone_number"])
        XCTAssertNil(json["code"])
    }

    func testAuthResponseDecodesOpenAPICamelCaseKeys() throws {
        let json = """
        {
          "accessToken": "token",
          "tokenType": "Bearer",
          "user": {
            "id": "00000000-0000-0000-0000-000000000001",
            "phoneNumber": "13800138000",
            "nickname": "测试用户",
            "roles": ["blind_runner", "volunteer"],
            "activeRole": null,
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-01T00:00:00Z"
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(AuthResponse.self, from: json)

        XCTAssertEqual(response.accessToken, "token")
        XCTAssertEqual(response.user.id, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(response.user.phoneNumber, "13800138000")
        XCTAssertEqual(response.user.roles, [.blindRunner, .volunteer])
    }

    func testOrderRequestUsesOpenAPIWireValues() throws {
        let request = CreateOrderRequest(
            startLocation: LocationPoint(
                latitude: 31.2304,
                longitude: 121.4737,
                addressText: "人民广场",
                source: .deviceLocation
            ),
            destinationText: "公园慢跑一圈",
            appointmentTime: "2026-05-22T09:00:00Z",
            estimatedDurationMinutes: 60,
            estimatedDistanceKm: 5.0,
            pacePreference: "慢跑",
            preferSameGender: true,
            remark: "请在地铁口见面"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let location = try XCTUnwrap(json["startLocation"] as? [String: Any])

        XCTAssertEqual(json["destinationText"] as? String, "公园慢跑一圈")
        XCTAssertEqual(location["addressText"] as? String, "人民广场")
        XCTAssertEqual(location["source"] as? String, "device_location")
        XCTAssertNil(json["routeNotes"])
        XCTAssertNil(location["address"])
    }

    func testManualCancellationReasonKeepsOpenAPIWireValueAndChineseLabel() throws {
        let request = CancelOrderRequest(
            cancelledBy: .blindRunner,
            cancelledReason: .wrongLocation,
            otherReasonText: nil
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])

        XCTAssertEqual(json["cancelledBy"], "blind_runner")
        XCTAssertEqual(json["cancelledReason"], "wrong_location")
        XCTAssertEqual(ManualCancellationReason.wrongLocation.displayName, "地点填写错误")
    }
}
