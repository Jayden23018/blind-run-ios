import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class CloudWireContractTests: XCTestCase {
    func testSendCodeRequestUsesOpenAPICamelCaseKeys() throws {
        let request = SendCodeRequest(phone: "13800138000")
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["phone"], "13800138000")
    }

    /// 后端信封的 `code` 是数字，历史上也出现过字符串形态，两种都要能解出来。
    func testSendCodeResponseDecodesBothNumericAndStringBusinessCode() throws {
        let numeric = #"{"success":true,"message":"验证码已发送","code":0}"#.data(using: .utf8)!
        let numericResponse = try JSONDecoder().decode(SendCodeResponse.self, from: numeric)
        XCTAssertTrue(numericResponse.success == true)
        XCTAssertEqual(numericResponse.message, "验证码已发送")
        XCTAssertEqual(numericResponse.code, "0")

        let string = #"{"success":true,"message":"验证码已发送","code":"654321"}"#.data(using: .utf8)!
        let stringResponse = try JSONDecoder().decode(SendCodeResponse.self, from: string)
        XCTAssertEqual(stringResponse.code, "654321")
    }

    func testVerifyCodeRequestUsesOpenAPICamelCaseKeys() throws {
        let request = VerifyCodeRequest(phone: "13800138000", code: AppConstants.Auth.demoVerificationCode)
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["phone"], "13800138000")
        XCTAssertEqual(json["code"], "000000")
    }

    func testDemoVerificationCodeMatchesCloudContract() {
        XCTAssertEqual(AppConstants.Auth.demoVerificationCode, "000000")
    }

    func testOrderRespondRequestEncodesAcceptAction() throws {
        let request = OrderRespondRequest(action: .accept)
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["action"], "ACCEPT")
    }
}
