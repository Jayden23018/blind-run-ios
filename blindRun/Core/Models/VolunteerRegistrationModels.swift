import Foundation

// MARK: - Registration Status

struct VolunteerRegistrationStatus: Codable, Sendable {
    let currentStep: Int?
    let step1Completed: Bool?
    let step2Completed: Bool?
    let step3Completed: Bool?
    let trainingCompleted: Bool?
    let overallStatus: String? // "PENDING", "IN_PROGRESS", "COMPLETED", "REJECTED"
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
