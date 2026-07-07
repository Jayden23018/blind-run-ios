import Foundation

// MARK: - Registration Status

struct VolunteerRegistrationStatus: Decodable, Sendable {
    let currentStep: Int?
    let currentStepCode: String?
    let registrationStep: String?
    let step1Completed: Bool?
    let step2Completed: Bool?
    let step3Completed: Bool?
    let trainingCompleted: Bool?
    let overallStatus: String? // "PENDING", "IN_PROGRESS", "COMPLETED", "REJECTED"
    let idVerifyStatus: String?
    let faceVerifyStatus: String?

    init(
        currentStep: Int? = nil,
        currentStepCode: String? = nil,
        registrationStep: String? = nil,
        step1Completed: Bool? = nil,
        step2Completed: Bool? = nil,
        step3Completed: Bool? = nil,
        trainingCompleted: Bool? = nil,
        overallStatus: String? = nil,
        idVerifyStatus: String? = nil,
        faceVerifyStatus: String? = nil
    ) {
        self.currentStep = currentStep
        self.currentStepCode = currentStepCode
        self.registrationStep = registrationStep
        self.step1Completed = step1Completed
        self.step2Completed = step2Completed
        self.step3Completed = step3Completed
        self.trainingCompleted = trainingCompleted
        self.overallStatus = overallStatus
        self.idVerifyStatus = idVerifyStatus
        self.faceVerifyStatus = faceVerifyStatus
    }

    private enum CodingKeys: String, CodingKey {
        case currentStep
        case registrationStep
        case step1Completed
        case step2Completed
        case step3Completed
        case trainingCompleted
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
        step1Completed = try container.decodeIfPresent(Bool.self, forKey: .step1Completed)
        step2Completed = try container.decodeIfPresent(Bool.self, forKey: .step2Completed)
        step3Completed = try container.decodeIfPresent(Bool.self, forKey: .step3Completed)
        trainingCompleted = try container.decodeIfPresent(Bool.self, forKey: .trainingCompleted)
        overallStatus = try container.decodeIfPresent(String.self, forKey: .overallStatus)
        idVerifyStatus = try container.decodeIfPresent(String.self, forKey: .idVerifyStatus)
        faceVerifyStatus = try container.decodeIfPresent(String.self, forKey: .faceVerifyStatus)
    }
}

// MARK: - Step 1: Basic Info

struct BasicInfoRequest: Codable, Sendable {
    let name: String
    let phone: String
    let runningExperience: String?
    let hasGuidedBefore: Bool?
    let emergencyExperience: String?
}

// MARK: - Step 4: Training

struct TrainingCourseResponse: Codable, Sendable, Identifiable {
    let id: Int64?
    let title: String?
    let description: String?
    let durationMinutes: Int?
    let videoUrl: String?
    let contentUrl: String?
    let orderIndex: Int?
}

struct TrainingProgressRequest: Codable, Sendable {
    let courseId: Int64
    let progressPercent: Int
    let lastPositionSeconds: Int
    let timeSpentSeconds: Int
}

struct QuizQuestionResponse: Codable, Sendable, Identifiable {
    let id: Int64?
    let courseId: Int64?
    let questionText: String?
    let questionType: String? // "SINGLE_CHOICE", "MULTIPLE_CHOICE"
    let options: [String]?
    let orderIndex: Int?
}

struct QuizAnswerRequest: Codable, Sendable {
    let courseId: Int64
    let questionId: Int64
    let answers: [String]
    let timeSpentSeconds: Int
}

struct QuizAnswerResponse: Codable, Sendable {
    let correct: Bool?
    let correctAnswers: [String]?
    let explanation: String?
    let passed: Bool?
}
