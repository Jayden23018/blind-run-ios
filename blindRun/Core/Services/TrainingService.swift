//
//  TrainingService.swift
//  blindRun
//
//  领域 service 层的一片：志愿者线上培训。范例是 `IncentiveService.swift`。
//

import Foundation

// MARK: - Endpoints

/// 培训片用到的全部端点。
///
/// **一个 case 一条完整字面量路径**，不许拼接 —— `scripts/validate-spec-coverage.mjs`
/// 只认字符串字面量，拼出来的路径它扫不到，这条端点就再也不会跟后端契约对撞
/// （记忆 `spec-coverage-scans-string-literals-not-requests`）。
/// 带路径参数的三条只能用插值，那是必要的；关键是**前缀是完整字面量**，
/// 归一化后仍能对上契约里的 `{courseId}`。
///
/// 🚩 **为什么自成一片，不并进 `ProfileService`**：`ProfileEndpoint` 的边界注释写着
/// 「按数据归属划：谁是这份资料的主人」。课程正文与题目是**平台内容**，不是「这个用户是谁」；
/// 只有进度才属于用户。并进去会让那条边界失效。
///
/// ⚠️ 路径**不在** `/api/volunteer/registration/` 下（旧培训模块曾是）。
/// 这次培训不进注册流程 —— 走完注册（含拒绝人脸的替代路径）也可能还没培训，
/// `registrationCompleted` 不会等它。
enum TrainingEndpoint {
    case courses
    case courseDetail(courseId: Int64)
    case reportProgress(courseId: Int64)
    case submitQuiz(courseId: Int64)

    var request: EndpointRequest {
        switch self {
        case .courses:
            return EndpointRequest(.get, "/api/volunteer/training/courses")
        case .courseDetail(let courseId):
            return EndpointRequest(.get, "/api/volunteer/training/courses/\(courseId)")
        case .reportProgress(let courseId):
            return EndpointRequest(.post, "/api/volunteer/training/courses/\(courseId)/progress")
        case .submitQuiz(let courseId):
            return EndpointRequest(.post, "/api/volunteer/training/courses/\(courseId)/quiz")
        }
    }
}

// MARK: - Protocol

/// 培训片对外的全部能力。
///
/// **每个方法都必须有生产调用点**（当前 4 个方法 / 4 个调用点，全在
/// `VolunteerTrainingView.swift` 的两个 view model 里）。没有调用点的方法当场删 ——
/// service 层的价值是收敛调用点，不是先摆一层空壳（同 `ProfileServing` 的规矩）。
///
/// 错误一律 `throws` 抛出去，**这一层不吞**。谁负责渲染谁 catch：
/// 吞在 service 里的错误在 UI 上表现成「点了没反应」。
protocol TrainingServing: Sendable {
    func courses() async throws -> TrainingCourseListResponse
    func courseDetail(courseId: Int64) async throws -> TrainingCourseDetail
    /// 上报**增量**学习时长（政策要求记录的字段）。后端累加。
    func reportProgress(courseId: Int64, studiedSeconds: Int) async throws
    /// 交卷。及格线是全对，可无限重考。
    func submitQuiz(courseId: Int64, request: TrainingQuizSubmitRequest) async throws -> TrainingQuizResult
}

// MARK: - Implementation

/// 唯一的生产实现。**只做两件事**：选端点、转参数。
///
/// 不做重试、不做缓存、不做判分 —— 这一层多一个判断，
/// 就多一处「Mock 和真实后端行为不一样」的来源。
struct TrainingService: TrainingServing {
    let transport: any APIClientProtocol

    init(transport: any APIClientProtocol) {
        self.transport = transport
    }

    func courses() async throws -> TrainingCourseListResponse {
        try await transport.send(TrainingEndpoint.courses.request)
    }

    func courseDetail(courseId: Int64) async throws -> TrainingCourseDetail {
        try await transport.send(TrainingEndpoint.courseDetail(courseId: courseId).request)
    }

    func reportProgress(courseId: Int64, studiedSeconds: Int) async throws {
        let _: EmptyResponse = try await transport.send(
            TrainingEndpoint.reportProgress(courseId: courseId).request,
            body: TrainingProgressRequest(studiedSeconds: studiedSeconds)
        )
    }

    func submitQuiz(courseId: Int64, request: TrainingQuizSubmitRequest) async throws -> TrainingQuizResult {
        try await transport.send(
            TrainingEndpoint.submitQuiz(courseId: courseId).request,
            body: request
        )
    }
}
