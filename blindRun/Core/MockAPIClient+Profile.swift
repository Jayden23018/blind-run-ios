//
//  MockAPIClient+Profile.swift
//  blindRun
//
//  从 MockAPIClient.swift 原样搬出的 档案与资质 分段。行为零改动，只改文件位置。
//

import Foundation

extension MockAPIClient {

    // MARK: - Profile Handlers

    /// 实名状态是 Mock 里的独立字段：资料更新不会覆盖它，提交实名后重新 GET 才拿到权威值。
    func handleGetBlindProfile() -> BlindProfileResponse {
        return BlindProfileResponse(
            name: blindProfile?.name,
            runningPace: blindProfile?.runningPace,
            specialNeeds: blindProfile?.specialNeeds,
            verifyStatus: blindVerifyStatus,
            visionLevel: blindProfile?.visionLevel,
            hasGuideDog: blindProfile?.hasGuideDog,
            tetherPreference: blindProfile?.tetherPreference,
            chatPreference: blindProfile?.chatPreference,
            defaultPace: blindProfile?.defaultPace
        )
    }

    /// `POST /api/blind/verify-identity`：后端成功分支返回
    /// `data = {"message": "身份认证通过", "verifyStatus": "VERIFIED"}`（`BlindController.verifyIdentity`），
    /// Mock 只造这两个后端真会返回的字段。核验不通过时后端走 400 分支，这里对应抛 `ID_INFO_INVALID`。
    /// Mock **不保存身份证号**，只落一个状态位。
    func handleVerifyIdentity(body: (any Encodable & Sendable)?) throws -> BlindVerifySubmitResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(BlindVerifyRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let idCardName = request.idCardName.trimmed
        guard idCardName.count >= 2, idCardName.count <= 50 else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "姓名需为 2 到 50 个字符"))
        }
        guard request.idCardNumber.trimmed.range(of: #"^\d{17}[\dXx]$"#, options: .regularExpression) != nil else {
            throw APIError.serverError(ErrorResponse(code: "ID_INFO_INVALID", message: "身份信息核验未通过"))
        }
        blindVerifyStatus = Self.environmentVerifyStatus(
            key: "AIDRUN_MOCK_BLIND_VERIFY_RESULT",
            default: BlindVerifyStatus.verified.rawValue
        )
        // 后端 200 分支的 message 是固定的「身份认证通过」；FAILED/NOT_VERIFIED 只出现在
        // UI 测试通过环境变量强制的场景里，此时不带那句成功文案。
        return BlindVerifySubmitResponse(
            message: blindVerifyStatus == BlindVerifyStatus.verified.rawValue ? "身份认证通过" : nil,
            verifyStatus: blindVerifyStatus
        )
    }

    /// 只接受三个合法状态，避免 UI 测试写错环境变量后拿到无声失败。
    static func environmentVerifyStatus(key: String, default defaultValue: String) -> String {
        guard let raw = ProcessInfo.processInfo.environment[key]?.uppercased(),
              BlindVerifyStatus(rawValue: raw) != nil,
              raw != BlindVerifyStatus.unknown.rawValue else {
            return defaultValue
        }
        return raw
    }

    func handleUpdateBlindProfile(body: (any Encodable & Sendable)?) throws -> BlindProfileResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(BlindProfileUpdateRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        blindProfile = BlindProfileResponse(
            name: request.name ?? blindProfile?.name,
            runningPace: request.runningPace ?? blindProfile?.runningPace,
            specialNeeds: request.specialNeeds ?? blindProfile?.specialNeeds,
            verifyStatus: blindVerifyStatus,
            visionLevel: request.visionLevel ?? blindProfile?.visionLevel,
            hasGuideDog: request.hasGuideDog ?? blindProfile?.hasGuideDog,
            tetherPreference: request.tetherPreference ?? blindProfile?.tetherPreference,
            chatPreference: request.chatPreference ?? blindProfile?.chatPreference,
            defaultPace: request.defaultPace ?? blindProfile?.defaultPace
        )
        return blindProfile!
    }

    func handleGetVolunteerProfile() -> VolunteerProfileResponse {
        return volunteerProfile ?? VolunteerProfileResponse(
            name: nil,
            verificationStatus: nil,
            adminReviewStatus: nil,
            registrationStep: volunteerRegistrationStepCode,
            canAcceptOrders: volunteerRegistrationStepCode == "STEP_4_COMPLETED",
            isAvailable: nil,
            availableTimeSlots: nil,
            acceptsGuideDog: nil,
            paceRange: nil
        )
    }

    func handleUpdateVolunteerProfile(body: (any Encodable & Sendable)?) throws -> VolunteerProfileResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(VolunteerProfileUpdateRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        volunteerProfile = VolunteerProfileResponse(
            name: request.name ?? volunteerProfile?.name,
            verificationStatus: "approved",
            adminReviewStatus: volunteerProfile?.adminReviewStatus ?? "approved",
            registrationStep: volunteerRegistrationStepCode ?? "STEP_4_COMPLETED",
            canAcceptOrders: volunteerRegistrationStepCode == nil || volunteerRegistrationStepCode == "STEP_4_COMPLETED",
            isAvailable: request.isAvailable ?? volunteerProfile?.isAvailable,
            wantsDispatch: request.wantsDispatch ?? volunteerProfile?.wantsDispatch,
            availableTimeSlots: request.availableTimeSlots ?? volunteerProfile?.availableTimeSlots,
            acceptsGuideDog: request.acceptsGuideDog ?? volunteerProfile?.acceptsGuideDog,
            paceRange: request.paceRange ?? volunteerProfile?.paceRange
        )
        return volunteerProfile!
    }

    /// 「Demo 模拟认证」按钮专用，真实后端没有这个端点（入口只在 `.mock` 环境显示，
    /// 见 `VolunteerModule.shouldShowRealRegistration`）。行为对齐管理员审核通过后的志愿者：
    /// 资质 APPROVED、注册流程走完、可接单。
    func handleMockVerificationApprove() -> VolunteerProfileResponse {
        volunteerVerificationStatus = .approved
        volunteerRegistrationStepCode = "STEP_4_COMPLETED"
        let existing = volunteerProfile
        volunteerProfile = VolunteerProfileResponse(
            name: existing?.name ?? "测试志愿者",
            verificationStatus: volunteerVerificationStatus.rawValue,
            adminReviewStatus: "approved",
            registrationStep: volunteerRegistrationStepCode,
            canAcceptOrders: true,
            isAvailable: existing?.isAvailable ?? false,
            wantsDispatch: existing?.wantsDispatch,
            availableTimeSlots: existing?.availableTimeSlots,
            acceptsGuideDog: existing?.acceptsGuideDog,
            paceRange: existing?.paceRange
        )
        return volunteerProfile!
    }

    func handleUpdateDispatchStatus(body: (any Encodable & Sendable)?) throws -> EmptyResponse {
        guard let data = try? JSONEncoder().encode(MockAnyEncodable(body)),
              let request = try? JSONDecoder().decode(DispatchStatusRequest.self, from: data) else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "请求格式错误"))
        }
        let existing = handleGetVolunteerProfile()
        volunteerProfile = VolunteerProfileResponse(
            name: existing.name,
            verificationStatus: existing.verificationStatus,
            adminReviewStatus: existing.adminReviewStatus,
            registrationStep: existing.registrationStep,
            canAcceptOrders: existing.canAcceptOrders,
            isAvailable: request.wantsDispatch,
            wantsDispatch: request.wantsDispatch,
            availableTimeSlots: existing.availableTimeSlots,
            acceptsGuideDog: existing.acceptsGuideDog,
            paceRange: existing.paceRange
        )
        return EmptyResponse()
    }

    func handleGetVolunteerDispatchSummary() -> VolunteerDispatchSummaryResponse {
        let profile = handleGetVolunteerProfile()
        let wantsDispatch = profile.isAvailable ?? profile.wantsDispatch ?? false
        // 🚨 **通话磨合态刻意排除在 `activeOrders` 之外**，尽管 `isActiveForVolunteer` 判它为 true。
        // 契约逐字（`introCallOrderId` 的 description）：「它不在 `activeOrders` 里，
        // 也不要合并进去」—— 人还没接单，那一态 `sharesLiveLocation()` 为 false，
        // 混进活跃订单会让位置协同空转。后端就是这么发的，Mock 照着演。
        //
        // 不去改 `isActiveForVolunteer`：那个属性的注释写明了它取「不把订单从界面上抹掉」
        // 的保守方向、且那条分支在生产里走不到（志愿者通话期读订单详情恒 403）。
        // 这里要对齐的是**后端这个响应装了什么**，不是那个判定本身。
        let activeOrders = orders
            .filter { $0.status.isActiveForVolunteer && $0.status != .pendingIntroCall }
            .sorted { ($0.acceptedAt ?? $0.createdAt ?? "") > ($1.acceptedAt ?? $1.createdAt ?? "") }
            .map {
                VolunteerDispatchSummaryActiveOrder(
                    orderId: $0.orderId,
                    status: $0.status,
                    plannedStartTime: $0.plannedStart,
                    plannedEndTime: $0.plannedEnd,
                    startAddress: $0.startAddress,
                    startLatitude: $0.startLatitude,
                    startLongitude: $0.startLongitude,
                    blindName: $0.blindName,
                    blindPhoneMasked: $0.blindPhone?.maskedPhone,
                    acceptedAt: $0.acceptedAt
                )
            }
        let recentOrders = orders
            .filter { $0.status == .completed || $0.status == .cancelled || $0.status.isActiveForVolunteer }
            .sorted { ($0.createdAt ?? $0.plannedStart ?? "") > ($1.createdAt ?? $1.plannedStart ?? "") }
            .prefix(5)
            .map {
                VolunteerDispatchSummaryRecentOrder(
                    orderId: $0.orderId,
                    status: $0.status,
                    plannedStartTime: $0.plannedStart,
                    completedAt: $0.status == .completed ? $0.plannedEnd : nil,
                    startAddress: $0.startAddress,
                    blindName: $0.blindName,
                    rating: $0.status == .completed ? 5 : nil,
                    // Mock 不得造出后端不存在的字段值：真实响应里 `pointsDelta` 恒为
                    // `nil`（后端契约与 `src/` 里 `points` 零命中）。此前这里返回 100，
                    // 于是 Mock 环境下的 UI 与真实环境长得不一样，而 UI 是照着 Mock 调的。
                    pointsDelta: nil
                )
            }
        let totalCompleted = orders.filter { $0.status == .completed }.count
        let totalAccepted = orders.filter { $0.status != .pendingMatch }.count
        // 与后端 VolunteerService.getDispatchSummary 逐条对齐：只有三个独立条件，
        // 在途订单**不**产生 notAvailableReason（后端在派单入口另行过滤）。
        // Mock 不得造后端没有的原因值，否则某些分支永远跑不到（曾因此漏掉 NOT_VERIFIED 解码 bug）。
        // Mock 只在开启接单时上报位置，因此 isOnline 与 wantsDispatch 同源。
        let isOnline = wantsDispatch
        let reasons: [VolunteerDispatchNotAvailableReason] = {
            var values: [VolunteerDispatchNotAvailableReason] = []
            if !wantsDispatch {
                values.append(.dispatchDisabled)
            }
            if !handleGetVolunteerRegistrationStatus().isRegistrationComplete {
                values.append(.notVerified)
            }
            if !isOnline {
                values.append(.offline)
            }
            return values
        }()
        return VolunteerDispatchSummaryResponse(
            canDispatch: reasons.isEmpty,
            notAvailableReasons: reasons,
            wantsDispatch: wantsDispatch,
            isOnline: isOnline,
            lastLat: isOnline ? 39.9042 : nil,
            lastLng: isOnline ? 116.4074 : nil,
            lastLocationAt: isOnline ? ISO8601DateFormatter().string(from: Date()) : nil,
            coverageRadiusKm: 10,
            isWithinServiceTime: true,
            availableTimeSlots: profile.availableTimeSlots,
            avgRating: totalCompleted > 0 ? 5.0 : nil,
            totalRatings: totalCompleted,
            totalDispatched: max(totalAccepted + 2, 2),
            totalAccepted: totalAccepted,
            totalDeclined: 1,
            totalTimeout: 1,
            totalCompleted: totalCompleted,
            totalCancelled: orders.filter { $0.status == .cancelled }.count,
            acceptanceRate: 0.7,
            activeOrders: activeOrders,
            recentOrders: Array(recentOrders),
            // 冷启动恢复用的那一个 id。Mock 从真实订单里取，不写死 ——
            // 写死就会让「没有通话在进行时它必须是 null」这条分支在开发期永远走不到，
            // 而志愿者首页正是靠 null 判断「不要自动跳进通话页」。
            introCallOrderId: orders.first { $0.status == .pendingIntroCall }?.orderId
        )
    }

    /// `GET /api/volunteer/achievements`（**不套信封**，与 `/api/volunteer/profile` 一致）。
    ///
    /// 勋章判定逐条抄后端 `VolunteerBadge.isUnlockedBy`：Mock 的职责是像后端，
    /// 不是自己发明一套。真正**不**能抄的是把这套阈值搬进 App 的展示逻辑 —— 那才会漂移。
    ///
    /// ⚠️ **`nextBadge` 的单位随 `code` 变**：`RUNS_*` 是次，`HOURS_*` 是**分钟**，
    /// `HIGH_RATED` 是条评价。Mock 也照这个口径给，否则 Mock 下看着对、真机上差 60 倍。
    func handleGetVolunteerAchievements() -> VolunteerAchievementsResponse {
        let totalCompleted = orders.filter { $0.status == .completed }.count
        // 每单按 60 分钟计。Mock 里订单没有真实的 IN_PROGRESS → COMPLETED 时间戳，
        // 编一个精确到分钟的数只会让人以为它有意义。
        let totalServiceMinutes = Int64(totalCompleted) * 60
        let avgRating: Double? = totalCompleted > 0 ? 5.0 : nil
        let totalRatings = totalCompleted

        /// 声明顺序即后端的顺序：`nextBadge` 取的是**第一枚未解锁的**，不是最接近达成的那枚。
        let table: [(code: String, name: String, unlocked: Bool, current: Int64, target: Int64)] = [
            ("FIRST_RUN", "首次陪跑", totalCompleted >= 1, Int64(totalCompleted), 1),
            ("RUNS_10", "陪跑达人 · 10 次", totalCompleted >= 10, Int64(totalCompleted), 10),
            ("RUNS_50", "陪跑达人 · 50 次", totalCompleted >= 50, Int64(totalCompleted), 50),
            ("RUNS_100", "陪跑达人 · 100 次", totalCompleted >= 100, Int64(totalCompleted), 100),
            ("HOURS_10", "累计服务 10 小时", totalServiceMinutes >= 600, totalServiceMinutes, 600),
            ("HOURS_50", "累计服务 50 小时", totalServiceMinutes >= 3000, totalServiceMinutes, 3000),
            ("HIGH_RATED", "口碑之星",
             (avgRating ?? 0) >= 4.8 && totalRatings >= 10, Int64(totalRatings), 10)
        ]

        let nextBadge = table.first { !$0.unlocked }.map {
            VolunteerNextBadgeDto(
                code: $0.code,
                name: $0.name,
                // 契约：`current` 恒 ≤ `target`，可直接当分子用。
                current: min($0.current, $0.target),
                target: $0.target
            )
        }

        return VolunteerAchievementsResponse(
            totalCompleted: totalCompleted,
            totalServiceMinutes: totalServiceMinutes,
            avgRating: avgRating,
            totalRatings: totalRatings,
            badges: table.filter(\.unlocked).map { VolunteerBadgeDto(code: $0.code, name: $0.name) },
            nextBadge: nextBadge,
            // 契约里 `starLevel` 恒非 null。Mock 给 null 会让「恒非 null」这条永远验不到。
            starLevel: VolunteerStarLevel.derive(totalServiceMinutes: totalServiceMinutes)
        )
    }
}

/// 只服务上面那处派单摘要的号码掩码。原本是 `MockAPIClient.swift` 的 file-private 扩展，
/// 拆文件后跟着唯一调用点走，仍然不进 App 命名空间。
private extension String {
    var maskedPhone: String {
        guard count >= 7 else { return self }
        return "\(prefix(3))****\(suffix(4))"
    }
}
