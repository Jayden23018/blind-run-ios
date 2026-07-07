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
    let trainingCompleted: Bool?
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
        trainingCompleted: Bool? = nil,
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
        self.trainingCompleted = trainingCompleted
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
        canAcceptOrders = try container.decodeIfPresent(Bool.self, forKey: .canAcceptOrders)
        stepDetails = try container.decodeIfPresent(VolunteerRegistrationStepDetails.self, forKey: .stepDetails)
        step1Completed = try container.decodeIfPresent(Bool.self, forKey: .step1Completed)
        step2Completed = try container.decodeIfPresent(Bool.self, forKey: .step2Completed)
        step3Completed = try container.decodeIfPresent(Bool.self, forKey: .step3Completed)
        trainingCompleted = try container.decodeIfPresent(Bool.self, forKey: .trainingCompleted)
        overallStatus = try container.decodeIfPresent(String.self, forKey: .overallStatus)
        idVerifyStatus = try container.decodeIfPresent(String.self, forKey: .idVerifyStatus) ?? stepDetails?.idVerifyStatus
        faceVerifyStatus = try container.decodeIfPresent(String.self, forKey: .faceVerifyStatus) ?? stepDetails?.faceVerifyStatus
    }

    var isRegistrationComplete: Bool {
        canAcceptOrders == true || (registrationStep ?? currentStepCode)?.uppercased() == "STEP_4_COMPLETED"
    }
}

struct VolunteerRegistrationStepDetails: Codable, Sendable {
    let idVerifyStatus: String?
    let faceVerifyStatus: String?
    let totalTrainingMinutes: Int?
    let completedCoursesCount: Int?
    let currentCourseId: Int64?
    let idVerifyRejectionReason: String?
    let faceVerifyRejectionReason: String?

    init(
        idVerifyStatus: String? = nil,
        faceVerifyStatus: String? = nil,
        totalTrainingMinutes: Int? = nil,
        completedCoursesCount: Int? = nil,
        currentCourseId: Int64? = nil,
        idVerifyRejectionReason: String? = nil,
        faceVerifyRejectionReason: String? = nil
    ) {
        self.idVerifyStatus = idVerifyStatus
        self.faceVerifyStatus = faceVerifyStatus
        self.totalTrainingMinutes = totalTrainingMinutes
        self.completedCoursesCount = completedCoursesCount
        self.currentCourseId = currentCourseId
        self.idVerifyRejectionReason = idVerifyRejectionReason
        self.faceVerifyRejectionReason = faceVerifyRejectionReason
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

// MARK: - Step 3: Face Verify

struct FaceVerifyResponse: Codable, Sendable {
    let passed: Bool?
    let status: String?
    let message: String?

    var isPassed: Bool {
        if passed == true {
            return true
        }
        return status?.uppercased() == "PASSED"
    }
}

// MARK: - Step 4: Training

struct TrainingCourseResponse: Decodable, Sendable, Identifiable {
    let id: Int64?
    let title: String?
    let description: String?
    let durationMinutes: Int?
    let videoUrl: String?
    let contentUrl: String?
    let orderIndex: Int?
    let progressPercent: Int?
    let status: String?
    let quizPassed: Bool?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case durationMinutes
        case videoUrl
        case contentUrl
        case content
        case orderIndex
        case displayOrder
        case progressPercent
        case status
        case quizPassed
    }

    init(
        id: Int64? = nil,
        title: String? = nil,
        description: String? = nil,
        durationMinutes: Int? = nil,
        videoUrl: String? = nil,
        contentUrl: String? = nil,
        orderIndex: Int? = nil,
        progressPercent: Int? = nil,
        status: String? = nil,
        quizPassed: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.durationMinutes = durationMinutes
        self.videoUrl = videoUrl
        self.contentUrl = contentUrl
        self.orderIndex = orderIndex
        self.progressPercent = progressPercent
        self.status = status
        self.quizPassed = quizPassed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        videoUrl = try container.decodeIfPresent(String.self, forKey: .videoUrl)
        contentUrl = try container.decodeIfPresent(String.self, forKey: .contentUrl) ?? container.decodeIfPresent(String.self, forKey: .content)
        orderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex) ?? container.decodeIfPresent(Int.self, forKey: .displayOrder)
        progressPercent = try container.decodeIfPresent(Int.self, forKey: .progressPercent)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        quizPassed = try container.decodeIfPresent(Bool.self, forKey: .quizPassed)
    }
}

struct TrainingProgressRequest: Codable, Sendable {
    let courseId: Int64
    let progressPercent: Int
    let lastPositionSeconds: Int
    let timeSpentSeconds: Int
}

struct QuizQuestionResponse: Decodable, Sendable, Identifiable {
    let id: Int64?
    let courseId: Int64?
    let questionText: String?
    let questionType: String? // "SINGLE_CHOICE", "MULTIPLE_CHOICE"
    let options: [String]?
    let orderIndex: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case courseId
        case questionText
        case questionType
        case options
        case orderIndex
        case displayOrder
    }

    init(
        id: Int64? = nil,
        courseId: Int64? = nil,
        questionText: String? = nil,
        questionType: String? = nil,
        options: [String]? = nil,
        orderIndex: Int? = nil
    ) {
        self.id = id
        self.courseId = courseId
        self.questionText = questionText
        self.questionType = questionType
        self.options = options
        self.orderIndex = orderIndex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int64.self, forKey: .id)
        courseId = try container.decodeIfPresent(Int64.self, forKey: .courseId)
        questionText = try container.decodeIfPresent(String.self, forKey: .questionText)
        questionType = try container.decodeIfPresent(String.self, forKey: .questionType)
        options = try container.decodeIfPresent([String].self, forKey: .options)
        orderIndex = try container.decodeIfPresent(Int.self, forKey: .orderIndex) ?? container.decodeIfPresent(Int.self, forKey: .displayOrder)
    }
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
    let correctCount: Int?
    let totalQuestions: Int?
    let scorePercent: Int?
    let remainingAttempts: Int?
    let questionResults: [QuizQuestionResultResponse]?
}

struct QuizQuestionResultResponse: Codable, Sendable {
    let questionId: Int64?
    let correct: Bool?
    let correctAnswers: [String]?
    let explanation: String?
}
