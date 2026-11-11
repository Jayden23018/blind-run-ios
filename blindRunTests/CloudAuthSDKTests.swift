import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class CloudAuthSDKTests: XCTestCase, BlindRunTestSupport {
    func testVolunteerFaceVerifyInitPostsMetaInfoAndStartsNativeSDK() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let verifier = CloudAuthVerifierSpy(outcome: .cancelled)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(
                certifyId: "cert-1",
                status: "PENDING",
                message: "请完成活体认证"
            ),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: verifier
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(client.initCount, 1)
        XCTAssertEqual(client.capturedMetaInfo, #"{"device":"test"}"#)
        XCTAssertEqual(verifier.receivedCertifyIds, ["cert-1"])
        XCTAssertEqual(verifier.receivedEnvironments, [.mock])
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertEqual(viewModel.errorMessage, "已取消活体认证，可重新开始")
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(client.resultCount, 0)
    }

    func testCloudAuthMetaInfoSerializerEncodesAliyunDictionary() throws {
        let metaInfo: [AnyHashable: Any] = [
            "apdidToken": "token-123",
            "sdkVersion": "2.3.50",
            "device": [
                "platform": "ios",
                "features": ["camera", "liveness"]
            ]
        ]

        let json = try DefaultCloudAuthMetaInfoProvider.serializedMetaInfo(from: metaInfo)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let device = try XCTUnwrap(object["device"] as? [String: Any])
        let features = try XCTUnwrap(device["features"] as? [String])

        XCTAssertEqual(object["apdidToken"] as? String, "token-123")
        XCTAssertEqual(object["sdkVersion"] as? String, "2.3.50")
        XCTAssertEqual(device["platform"] as? String, "ios")
        XCTAssertEqual(features, ["camera", "liveness"])
    }

    func testCloudAuthRequiredResourcesAreBundled() throws {
        let requiredBundles = [
            "APBToygerFacade",
            "APBToygerFacadeSuitable",
            "BioAuthEngine",
            "ToygerService"
        ]

        for bundleName in requiredBundles {
            XCTAssertNotNil(
                Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
                "Missing required CloudAuth resource bundle: \(bundleName).bundle"
            )
        }

        let toygerBundleURL = try XCTUnwrap(
            Bundle.main.url(forResource: "ToygerService", withExtension: "bundle")
        )
        let modelURL = toygerBundleURL.appendingPathComponent("toyger.face.dat")
        let attributes = try FileManager.default.attributesOfItem(atPath: modelURL.path)
        let modelSize = try XCTUnwrap(attributes[.size] as? NSNumber)

        XCTAssertGreaterThan(modelSize.intValue, 0, "CloudAuth face model must not be empty")
    }

    func testCloudAuthUnusedOptionalModulesAreExcluded() {
#if canImport(OCRDetectSDKForTech)
        XCTFail("OCR CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
#if canImport(DTFNFCIdentityManager)
        XCTFail("NFC CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
#if canImport(MultiFactorFacade)
        XCTFail("MultiFactor CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
#if canImport(DTFBeauty)
        XCTFail("Beauty CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
    }

    func testCloudAuthMetaInfoSerializerRejectsEmptyDictionary() {
        XCTAssertThrowsError(try DefaultCloudAuthMetaInfoProvider.serializedMetaInfo(from: [:])) { error in
            guard let metaInfoError = error as? CloudAuthMetaInfoError else {
                return XCTFail("Expected CloudAuthMetaInfoError")
            }
            XCTAssertEqual(metaInfoError.localizedDescription, "刷脸没打开，请重试")
        }
    }

    func testDefaultCloudAuthVerifierMapsSDKCompletionCodes() {
        XCTAssertEqual(DefaultCloudAuthVerifier.outcome(forSDKCode: 1000), .submitted)
        XCTAssertEqual(DefaultCloudAuthVerifier.outcome(forSDKCode: 2006), .submitted)
        XCTAssertEqual(DefaultCloudAuthVerifier.outcome(forSDKCode: 1003), .cancelled)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 1001)), .internalError)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 2002)), .networkError)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 2003)), .deviceTimeError)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 9999)), .unknown(code: 9999))
    }

    func testCloudAuthDiagnosticsKeepOnlyBoundedTechnicalFields() {
        let diagnostics = CloudAuthSDKDiagnostics(
            code: 1001,
            retCode: 1001,
            retCodeSub: " z1014 ",
            retMessageSub: "raw-message-must-not-be-logged",
            sdkVersion: "2.3.50"
        )

        XCTAssertEqual(diagnostics.retCodeSub, "Z1014")
        XCTAssertTrue(diagnostics.retMessageSubPresent)
        XCTAssertEqual(diagnostics.retMessageSubLength, 30)
        XCTAssertEqual(diagnostics.sdkVersion, "2.3.50")
        XCTAssertTrue(diagnostics.debugSummary.contains("retCodeSub=Z1014"))
        XCTAssertTrue(diagnostics.debugSummary.contains("retMessageSubLength=30"))
        XCTAssertFalse(diagnostics.debugSummary.contains("raw-message"))
    }

    func testCloudAuthDiagnosticsRejectUnsafeSubcodeAndVersion() {
        let diagnostics = CloudAuthSDKDiagnostics(
            code: 1001,
            retCode: 1001,
            retCodeSub: "Z1014 certify-secret",
            retMessageSub: nil,
            sdkVersion: "2.3.50 secret"
        )

        XCTAssertNil(diagnostics.retCodeSub)
        XCTAssertNil(diagnostics.sdkVersion)
        XCTAssertFalse(diagnostics.retMessageSubPresent)
        XCTAssertEqual(diagnostics.retMessageSubLength, 0)
        XCTAssertFalse(diagnostics.debugSummary.contains("secret"))
    }

    func testDefaultCloudAuthVerifierMapsDetailedSubcodes() {
        let mappings: [(String, CloudAuthVerificationFailure.Kind)] = [
            ("Z1014", .internalError),
            ("Z1023", .internalError),
            ("I4001", .moduleIntegration),
            ("Z1010", .businessParameter),
            ("Z1037", .businessParameter),
            ("Z1001", .cameraUnavailable),
            ("Z1002", .cameraUnavailable),
            ("Z1020", .cameraUnavailable),
            ("Z1024", .duplicateFlow)
        ]

        for (subcode, expectedKind) in mappings {
            let diagnostics = CloudAuthSDKDiagnostics(
                code: 1001,
                retCode: 1001,
                retCodeSub: subcode,
                retMessageSub: "not retained",
                sdkVersion: "2.3.50"
            )
            let outcome = DefaultCloudAuthVerifier.outcome(for: diagnostics)
            XCTAssertEqual(failureKind(for: outcome), expectedKind, "Unexpected mapping for \(subcode)")
        }
    }

    func testDefaultCloudAuthVerifierTopLevelCodesTakePrecedenceOverDiagnosticSubcodes() {
        func outcome(code: Int) -> CloudAuthVerificationOutcome {
            DefaultCloudAuthVerifier.outcome(for: CloudAuthSDKDiagnostics(
                code: code,
                retCode: code,
                retCodeSub: "Z1014",
                retMessageSub: "not retained",
                sdkVersion: "2.3.50"
            ))
        }

        XCTAssertEqual(outcome(code: 1000), .submitted)
        XCTAssertEqual(outcome(code: 2006), .submitted)
        XCTAssertEqual(outcome(code: 1003), .cancelled)
        XCTAssertEqual(failureKind(for: outcome(code: 2002)), .networkError)
        XCTAssertEqual(failureKind(for: outcome(code: 2003)), .deviceTimeError)
    }

    func testCloudAuthSDKRuntimeInitializesOnlyOnce() {
        var initializeCalls = 0
        var versionCalls = 0
        let runtime = CloudAuthSDKRuntime(
            initializeSDK: { initializeCalls += 1 },
            versionProvider: {
                versionCalls += 1
                return "2.3.50"
            }
        )

        XCTAssertNil(runtime.sdkVersion)
        runtime.initializeIfNeeded()
        runtime.initializeIfNeeded()

        XCTAssertEqual(initializeCalls, 1)
        XCTAssertEqual(runtime.initializationCount, 1)
        XCTAssertEqual(runtime.sdkVersion, "2.3.50")
        XCTAssertEqual(versionCalls, 1)
    }

    func testCloudAuthOneShotGateAcceptsOnlyFirstCallback() {
        let gate = CloudAuthOneShotGate()

        XCTAssertTrue(gate.claim())
        XCTAssertFalse(gate.claim())
    }

    private func failureKind(for outcome: CloudAuthVerificationOutcome) -> CloudAuthVerificationFailure.Kind? {
        guard case .failed(let failure) = outcome else { return nil }
        return failure.kind
    }
}
