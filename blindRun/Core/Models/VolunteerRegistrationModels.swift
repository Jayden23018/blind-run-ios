import Foundation

// MARK: - Registration Status

struct VolunteerRegistrationStatus: Decodable, Sendable {
    let currentStep: Int?
    let currentStepCode: String?
    let registrationStep: String?
    let canAcceptOrders: Bool?
    let stepDetails: VolunteerRegistrationStepDetails?
    let step1Completed: Bool?
    let step2Completed: Bool?
    let step3Completed: Bool?
    let overallStatus: String? // "PENDING", "IN_PROGRESS", "COMPLETED", "REJECTED"
    let idVerifyStatus: String?
    let faceVerifyStatus: String?

    init(
        currentStep: Int? = nil,
        currentStepCode: String? = nil,
        registrationStep: String? = nil,
        canAcceptOrders: Bool? = nil,
        stepDetails: VolunteerRegistrationStepDetails? = nil,
        step1Completed: Bool? = nil,
        step2Completed: Bool? = nil,
        step3Completed: Bool? = nil,
        overallStatus: String? = nil,
        idVerifyStatus: String? = nil,
        faceVerifyStatus: String? = nil
    ) {
        self.currentStep = currentStep
        self.currentStepCode = currentStepCode
        self.registrationStep = registrationStep
        self.canAcceptOrders = canAcceptOrders
        self.stepDetails = stepDetails
        self.step1Completed = step1Completed
        self.step2Completed = step2Completed
        self.step3Completed = step3Completed
        self.overallStatus = overallStatus
        self.idVerifyStatus = idVerifyStatus
        self.faceVerifyStatus = faceVerifyStatus
    }

    private enum CodingKeys: String, CodingKey {
        case currentStep
        case registrationStep
        case canAcceptOrders
        case stepDetails
        case step1Completed
        case step2Completed
        case step3Completed
        case overallStatus
        case idVerifyStatus
        case faceVerifyStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let numericStep = try? container.decodeIfPresent(Int.self, forKey: .currentStep) {
            currentStep = numericStep
            currentStepCode = nil
        } else {
            currentStep = nil
            currentStepCode = try container.decodeIfPresent(String.self, forKey: .currentStep)
        }
        registrationStep = try container.decodeIfPresent(String.self, forKey: .registrationStep)
        canAcceptOrders = try container.decodeIfPresent(Bool.self, forKey: .canAcceptOrders)
        stepDetails = try container.decodeIfPresent(VolunteerRegistrationStepDetails.self, forKey: .stepDetails)
        step1Completed = try container.decodeIfPresent(Bool.self, forKey: .step1Completed)
        step2Completed = try container.decodeIfPresent(Bool.self, forKey: .step2Completed)
        step3Completed = try container.decodeIfPresent(Bool.self, forKey: .step3Completed)
        overallStatus = try container.decodeIfPresent(String.self, forKey: .overallStatus)
        idVerifyStatus = try container.decodeIfPresent(String.self, forKey: .idVerifyStatus) ?? stepDetails?.idVerifyStatus
        faceVerifyStatus = try container.decodeIfPresent(String.self, forKey: .faceVerifyStatus) ?? stepDetails?.faceVerifyStatus
    }

    var isRegistrationComplete: Bool {
        guard canAcceptOrders != true else { return true }
        let stepCode = (registrationStep ?? currentStepCode)?.uppercased()
        return stepCode == "STEP_4_COMPLETED" || stepCode == "STEP_4_TRAINING"
    }
}

struct VolunteerRegistrationStepDetails: Codable, Sendable {
    let idVerifyStatus: String?
    let faceVerifyStatus: String?
    let idVerifyRejectionReason: String?
    let faceVerifyRejectionReason: String?

    init(
        idVerifyStatus: String? = nil,
        faceVerifyStatus: String? = nil,
        idVerifyRejectionReason: String? = nil,
        faceVerifyRejectionReason: String? = nil
    ) {
        self.idVerifyStatus = idVerifyStatus
        self.faceVerifyStatus = faceVerifyStatus
        self.idVerifyRejectionReason = idVerifyRejectionReason
        self.faceVerifyRejectionReason = faceVerifyRejectionReason
    }
}

// MARK: - Step 1: Basic Info

struct BasicInfoRequest: Codable, Sendable {
    let name: String
    let phone: String
    let idCardName: String
    let idCardNumber: String
    let runningExperience: String?
    let hasGuidedBefore: Bool?
    let emergencyExperience: String?
}

// MARK: - Step 3: Face Verify

struct FaceVerifyInitRequest: Codable, Sendable {
    let metaInfo: String
}

struct FaceVerifyInitResponse: Codable, Sendable {
    let certifyId: String?
    let status: String?
    let message: String?

    var isPending: Bool {
        status?.uppercased() == "PENDING"
    }

    var isError: Bool {
        status?.uppercased() == "ERROR"
    }
}

struct FaceVerifyResultRequest: Codable, Sendable {
    let certifyId: String
}

struct FaceVerifyResponse: Codable, Sendable {
    let passed: Bool?
    let status: String?
    let message: String?

    var isPassed: Bool {
        if passed == true {
            return true
        }
        let normalizedStatus = status?.uppercased()
        return normalizedStatus == "APPROVED" || normalizedStatus == "PASSED"
    }

    var isPending: Bool {
        status?.uppercased() == "PENDING"
    }

    var isRejected: Bool {
        status?.uppercased() == "REJECTED"
    }

    var isError: Bool {
        status?.uppercased() == "ERROR"
    }
}
