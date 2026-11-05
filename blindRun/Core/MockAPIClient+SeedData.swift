import CoreLocation
import Foundation

extension MockAPIClient {
    // MARK: - Seed Data

    func seedDemoData() {
        blindProfile = BlindProfileResponse(
            name: "测试盲人",
            runningPace: "MODERATE",
            specialNeeds: nil,
            visionLevel: "TOTAL_BLIND",
            hasGuideDog: false,
            guideDog: GuideDogStatus.no.rawValue,
            tetherPreference: "TETHER_ROPE",
            chatPreference: "PREFER_CHAT",
            defaultPace: .moderate
        )

        let uiTestVolunteerAvailable = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_AVAILABLE"] == "1"
        let uiTestActiveVolunteerOrder = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_ACTIVE_ORDER"] == "1"
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_UNREGISTERED_VOLUNTEER"] == "1" {
            volunteerProfile = nil
            volunteerRegistrationStepCode = nil
            volunteerFaceVerifyDeclined = false
        } else {
            volunteerProfile = VolunteerProfileResponse(
                name: "测试志愿者",
                verificationStatus: "approved",
                adminReviewStatus: "approved",
                isAvailable: uiTestVolunteerAvailable,
                availableTimeSlots: [
                    VolunteerAvailableTimeSlot(dayOfWeek: "SATURDAY", startTime: "09:00:00", endTime: "12:00:00"),
                    VolunteerAvailableTimeSlot(dayOfWeek: "SUNDAY", startTime: "09:00:00", endTime: "12:00:00")
                ],
                acceptsGuideDog: true,
                paceRange: .moderate
            )
        }

        applyUITestVerificationStatusOverride()
        if volunteerProfile != nil {
            applyVolunteerVerificationStatusToProfile()
        }

        emergencyContacts = [
            EmergencyContactResponse(id: 1, name: "张三", phone: "13900139001", relationship: "家人", isPrimary: true)
        ]

        // Seed some demo orders
        let futureDate = Calendar.current.date(byAdding: .hour, value: 2, to: Date())!
        let futureEnd = Calendar.current.date(byAdding: .hour, value: 3, to: Date())!
        let formatter = ISO8601DateFormatter()
        let activeAcceptedAt = formatter.string(from: Date().addingTimeInterval(-600))

        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_EMPTY_MOCK_ORDERS"] == "1" {
            orders = []
            nextOrderId = 10
            return
        }

        // 让 UI 用例把种子订单直接钉在某个状态上。没有它，要验 `IN_PROGRESS` 的页面就得在订单状态页
        // 最底部的 mock 面板上连点三次（模拟接单 → 模拟到达 → 模拟服务开始），每次都要先滚到底 ——
        // 慢，而且滚动 + 盲点 tap 正是 `snapshot timeout` 那类误触的温床。
        //
        // 与 `AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS` 同口径：只认真实存在的取值，
        // 未知值（含 `UNKNOWN` 这个纯解码兜底）一律忽略、退回原来的种子状态。
        let seededStatus: RunOrderStatus? = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_SEED_ORDER_STATUS"]
            .flatMap(RunOrderStatus.init(rawValue:))
            .flatMap { RunOrderStatus.allCases.contains($0) ? $0 : nil }
        let activeOrderStatus = seededStatus ?? (uiTestActiveVolunteerOrder ? .pendingAccept : .pendingMatch)
        // 汇合之后的状态必须带上接单痕迹，否则页面会同时显示「进行中」和「还没有志愿者」。
        // `plannedStart` 同理要落到过去：一单已经跑起来的约在两小时后开始是自相矛盾的，
        // 而「预计结束时间」「已进行时长」都从这两个字段算。
        //
        // 判据借 `offersVolunteerCall` —— 它的语义就是「本单此刻有一个还在场的志愿者」
        // （`REMATCHING` 为 false，因为那个志愿者已经退出了），正是要不要填
        // `volunteerPhone` / `acceptedAt` 的同一个问题，不另起一套集合字面量。
        let isPastMatching = activeOrderStatus.offersVolunteerCall
        let startedAt = Calendar.current.date(byAdding: .minute, value: -20, to: Date())!
        let startedEnd = Calendar.current.date(byAdding: .minute, value: 40, to: Date())!

        orders = [
            OrderDetailResponse(
                orderId: 1,
                status: activeOrderStatus,
                startAddress: "朝阳公园南门",
                startLatitude: 39.9342,
                startLongitude: 116.4740,
                // 种子订单**刻意不带终点**：UI 用例按现有行数与标签断言，凭空多一行会假失败。
                // 终点的展示路径由「语音下单 → 志愿者接单」这条真实路径覆盖，
                // 不靠种子数据摆样子。
                endAddress: nil,
                endLatitude: nil,
                endLongitude: nil,
                plannedStart: formatter.string(from: isPastMatching ? startedAt : futureDate),
                plannedEnd: formatter.string(from: isPastMatching ? startedEnd : futureEnd),
                blindName: "李明",
                blindPhone: "13800001001",
                volunteerPhone: isPastMatching ? "13800000002" : nil,
                acceptedAt: isPastMatching ? activeAcceptedAt : nil,
                createdAt: formatter.string(from: Date()),
                expectedDurationMinutes: 60,
                pacePreference: .moderate,
                routePreference: .parkTrail,
                routeNotes: "沿湖边跑道",
                hasGuideDogThisRun: false,
                specialNotes: nil,
                visionLevel: "TOTAL_BLIND",
                tetherPreference: "TETHER_ROPE",
                chatPreference: "PREFER_CHAT",
                // 用 `mockHasAcceptedVolunteer` 而不是上面那个 `isPastMatching`：
                // 被 `AIDRUN_UI_TEST_SEED_ORDER_STATUS` 钉成 `COMPLETED` 时两者结论相反。
                volunteerId: Self.mockHasAcceptedVolunteer(activeOrderStatus) ? Self.mockOrderVolunteerId : nil,
                volunteerName: Self.mockHasAcceptedVolunteer(activeOrderStatus) ? Self.mockOrderVolunteerName : nil,
                volunteerTotalCompleted: Self.mockHasAcceptedVolunteer(activeOrderStatus) ? Self.mockOrderVolunteerCompletedRuns : nil,
                // 完赛三项与「第几次一起跑」**只在 `COMPLETED` 有值**，与后端一致（进终态时算一次落库）。其余状态留 nil，
                // 正好也覆盖「后端没算出来时整段消失」那条分支 —— 所有状态都有值等于让已完成屏的降级路径永远走不到。
                actualDistanceMeters: activeOrderStatus == .completed ? 5120 : nil,
                actualDurationSeconds: activeOrderStatus == .completed ? 2360 : nil,
                actualAvgPaceSecPerKm: activeOrderStatus == .completed ? 461 : nil,
                completedTogetherCount: activeOrderStatus == .completed ? 3 : nil,
                earliestBlindCancelAt: Self.seededBlindCancelAt(for: activeOrderStatus),
                counterpartUserId: Self.mockHasAcceptedVolunteer(activeOrderStatus) ? Self.mockOrderVolunteerId : nil
            ),
            OrderDetailResponse(
                orderId: 2,
                status: .completed,
                startAddress: "奥林匹克森林公园",
                startLatitude: 40.0150,
                startLongitude: 116.3847,
                endAddress: nil,
                endLatitude: nil,
                endLongitude: nil,
                plannedStart: formatter.string(from: Date().addingTimeInterval(-86400)),
                plannedEnd: formatter.string(from: Date().addingTimeInterval(-82800)),
                blindName: "王芳",
                blindPhone: "13800001002",
                volunteerPhone: "13800000002",
                acceptedAt: formatter.string(from: Date().addingTimeInterval(-86000)),
                createdAt: formatter.string(from: Date().addingTimeInterval(-90000)),
                expectedDurationMinutes: 45,
                pacePreference: .easy,
                routePreference: .parkTrail,
                routeNotes: nil,
                hasGuideDogThisRun: false,
                specialNotes: nil,
                visionLevel: "TOTAL_BLIND",
                tetherPreference: "TETHER_ROPE",
                chatPreference: "NO_PREFERENCE",
                // 这一单是开发期唯一的已完成订单，也就是「把陈*设为固定搭档」那个入口的落点。
                volunteerId: Self.mockOrderVolunteerId,
                volunteerName: Self.mockOrderVolunteerName,
                volunteerTotalCompleted: Self.mockOrderVolunteerCompletedRuns,
                counterpartUserId: Self.mockOrderVolunteerId
            )
        ]
        // 记录页截图用：给「未完成的预约」那一组一条可拍的数据。**只在显式要求时加** ——
        // 其余 UI 用例按现有行数断言，凭空多一条会假失败（同上面「刻意不带终点」那条理由）。
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_SEED_HISTORY"] == "1" {
            orders.append(OrderDetailResponse(
                orderId: 3,
                status: .cancelled,
                startAddress: "朝阳公园南门",
                startLatitude: 39.9342,
                startLongitude: 116.4740,
                endAddress: nil,
                endLatitude: nil,
                endLongitude: nil,
                plannedStart: formatter.string(from: Date().addingTimeInterval(-3 * 86400)),
                plannedEnd: formatter.string(from: Date().addingTimeInterval(-3 * 86400 + 3600)),
                blindName: "李明",
                blindPhone: "13800001001",
                volunteerPhone: nil,
                acceptedAt: nil,
                createdAt: formatter.string(from: Date().addingTimeInterval(-4 * 86400)),
                expectedDurationMinutes: 60,
                pacePreference: .moderate,
                routePreference: .parkTrail,
                routeNotes: nil,
                hasGuideDogThisRun: false,
                specialNotes: nil,
                visionLevel: "TOTAL_BLIND",
                tetherPreference: "TETHER_ROPE",
                chatPreference: "PREFER_CHAT"
            ))
        }
        // 后端放行时刻（#546）：把种子订单的 `earliestDepartureAt` 放到「现在 + N 分钟」，
        // UI 用例据此验陪跑员主按钮原位不可按。不设就是 `nil`（不锁），其余用例照旧。
        if let minutes = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_SEED_EARLIEST_DEPARTURE_MINUTES"].flatMap(Int.init) {
            orders[0].earliestDepartureAt = formatter.string(from: Date().addingTimeInterval(TimeInterval(minutes * 60)))
        }
        nextOrderId = 10
    }
}
