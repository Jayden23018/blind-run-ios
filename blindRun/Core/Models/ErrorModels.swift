import Foundation

// MARK: - Error Code

enum ErrorCode: String, Codable, Sendable {
    case invalidVerificationCode = "INVALID_VERIFICATION_CODE"
    case orderNotFound = "ORDER_NOT_FOUND"
    case orderAlreadyAccepted = "ORDER_ALREADY_ACCEPTED"
    case invalidOrderStatus = "ORDER_STATUS_NOT_ALLOWED"
    // 后端 `RoleController.setRole` 是**一次性设角色**：角色非 UNSET 直接 409。
    // 后端没有任何角色切换端点，所以这个码只会出现在首次选角色的并发场景，
    // 不要再把它当成「有进行中订单挡住了切换」——那是本仓库历史误映射，已删除对应入口。
    case roleAlreadySet = "ROLE_ALREADY_SET"
    case volunteerNotAvailable = "VOLUNTEER_NOT_AVAILABLE"
    case volunteerNotApproved = "VOLUNTEER_NOT_VERIFIED"
    case appointmentTooSoon = "APPOINTMENT_TOO_SOON"
    // 下单时间类的另外两条（后端 `ErrorCode.java:174-190`，N134 随 `OrderCreationService` 一起上线）。
    // 校验顺序在 `APPOINTMENT_TOO_SOON` 之后：先时长、再夜间窗口。
    // **两条都命中时后端返回 `APPOINTMENT_TOO_LONG`**（跨多天的超长单必然也跨夜），
    // 所以那句文案不能提夜间，否则用户改完时段还是过不了。
    //
    // ⚠️ `APPOINTMENT_TOO_LONG` 当前**客户端到不了**：表单选择器最大 120 分钟
    // （`BookingDurationOption.oneTwenty`），语音那条被 `VoiceOrderWizard.acceptedDurationMinutes`
    // 夹在 10–300。映射它的理由和 `introCallRequired` 一样 —— 别把一个有确切含义的 422
    // 念成「未知错误 (422)」。契约一放宽（或哪天加了自定义时长输入）它立刻就是活分支。
    // `APPOINTMENT_IN_NIGHT_WINDOW` 相反，**现在就到得了**：客户端没有任何夜间校验，
    // 21:00 出发跑两小时是一次完全正常的操作。
    case appointmentTooLong = "APPOINTMENT_TOO_LONG"
    case appointmentInNightWindow = "APPOINTMENT_IN_NIGHT_WINDOW"
    // 跨天预约（后端迁移 `0041`，2026-09-05）。**此前下单只有下限没有上限。**
    //
    // 客户端已经在选择器上封了 7 天（`AppConstants.Timing.maximumBookingLeadDays`），
    // 所以正常路径下见不到 `APPOINTMENT_TOO_FAR`；映射它是因为那个天数是**后端配置**
    // （`app.order.max-lead-days`），后端调小的那一天，选择器上的 7 天就是错的，
    // 而这条 422 是当天唯一还能说清「为什么被拒」的东西。
    case appointmentTooFar = "APPOINTMENT_TOO_FAR"
    // 同批新增：同时最多 3 张未完成预约（`app.order.max-concurrent-scheduled`）。
    // 🚩 它与 `DUPLICATE_ORDER` 是一对，别混：那条现在只拦**时段冲突**，这条拦**总数**。
    // 客户端**算不出**它（拿不到「我还有几张未走完的单」的总数），只能等后端拒。
    case tooManyScheduledOrders = "TOO_MANY_SCHEDULED_ORDERS"
    case validationFailed = "VALIDATION_ERROR"
    case unauthorized = "UNAUTHORIZED"
    case activeOrderAccountDeletionBlocked = "ACTIVE_ORDER_ACCOUNT_DELETION_BLOCKED"
    case keepWaitingLimitReached = "KEEP_WAITING_LIMIT_REACHED"
    case orderDispatchMismatch = "ORDER_DISPATCH_MISMATCH"
    case orderConcurrentConflict = "ORDER_CONCURRENT_CONFLICT"
    case tooManyRequests = "TOO_MANY_REQUESTS"
    case notOrderParticipant = "NOT_ORDER_PARTICIPANT"
    case invalidTimestamp = "INVALID_TIMESTAMP"
    case phoneFormatInvalid = "PHONE_FORMAT_INVALID"
    case userNotFound = "USER_NOT_FOUND"
    case notFound = "NOT_FOUND"
    case badRequest = "BAD_REQUEST"
    case securityForbidden = "SECURITY_FORBIDDEN"
    case resourceNotFound = "RESOURCE_NOT_FOUND"
    case duplicateOrder = "DUPLICATE_ORDER"
    // 后端 2026-07-31（`7bce0b3`）把「已评价过此订单」从 `DUPLICATE_ORDER` 拆出来独立成码，
    // 此后 `DUPLICATE_ORDER` 只剩「已有进行中的订单」一种语义，两个码各自有确定文案。
    case reviewAlreadySubmitted = "REVIEW_ALREADY_SUBMITTED"
    case registrationStepInvalid = "REGISTRATION_STEP_INVALID"
    case internalError = "INTERNAL_ERROR"
    case idInfoInvalid = "ID_INFO_INVALID"
    case orderInProgress = "ORDER_IN_PROGRESS"
    case orderPermissionDenied = "ORDER_PERMISSION_DENIED"
    case smsSendLimitExceeded = "SMS_SEND_LIMIT_EXCEEDED"
    // 盲人下单前置门槛，后端 `ErrorCode.java`「盲人下单前置条件类（403）」小节（2026-07-30 新增）。
    // `OrderCreationService.createOrder` 的判定顺序是**先实名、后紧急联系人**，客户端门槛必须同序。
    case identityNotVerified = "IDENTITY_NOT_VERIFIED"
    // 取代此前复用的通用 `ORDER_PERMISSION_DENIED`：后者与「非订单参与者」等场景共用一个码，
    // 客户端无法程序化区分，只能猜 message。
    case emergencyContactRequired = "EMERGENCY_CONTACT_REQUIRED"
    // 紧急求助撤销权（后端 `ErrorCode.java:111-115`，2026-07-31 随「受助者 ≠ 触发者」修复一起上线）。
    // 陪同者不得关闭被陪同者的警报 —— 一对一陪跑里志愿者本身可能就是威胁来源，
    // 所以志愿者传 `action=FALSE_ALARM` 恒 403，志愿者端也就不提供「误触」按钮。
    case emergencyVolunteerCannotDismiss = "EMERGENCY_VOLUNTEER_CANNOT_DISMISS"
    case emergencyNotOwner = "EMERGENCY_NOT_OWNER"
    case emergencyAlreadyClosed = "EMERGENCY_ALREADY_CLOSED"
    // 紧急联系人专用码，后端 `ErrorCode.java` 「紧急联系人类（400）」小节的三个值。
    case contactLimitExceeded = "CONTACT_LIMIT_EXCEEDED"
    case contactMinimumRequired = "CONTACT_MINIMUM_REQUIRED"
    case contactFieldRequired = "CONTACT_FIELD_REQUIRED"
    // 行程实时分享（后端 `ErrorCode.java:119`，2026-08-13 随 `POST /api/orders/{id}/share` 上线）。
    // 终态订单不能再开新链接。客户端在终态**隐藏**分享入口而不是禁用后报错，
    // 所以这个码只会在竞态里出现：订单页每 5 秒轮询一次，用户可能正好在订单刚结束的窗口里按下。
    // 映射它不是为了那个窗口好看，是为了别把一个有确切含义的 409 念成「未知错误 (409)」。
    case shareOrderAlreadyFinished = "SHARE_ORDER_ALREADY_FINISHED"
    // 接单前通话磨合（后端 `ErrorCode.java:111` / `:119`，2026-08-21 随迁移 `0031` 上线）。
    //
    // `INTRO_CALL_NOT_ACTIVE` 最常见的成因**不是客户端乱调**，而是这一轮的 20 分钟窗口已经超时、
    // 订单已经换了下一个候选人，用户此刻才把表态发上来。所以文案说「这一轮已经结束」，
    // 不能说成「参数错误」或「操作失败」——后者会让人以为再点一次就好。
    case introCallNotActive = "INTRO_CALL_NOT_ACTIVE"
    // 陌生人试图跳过通话直接接单。客户端一律先发 `INTERESTED`，所以正常路径下见不到它；
    // 映射它是为了别把一个有确切含义的 409 念成「未知错误 (409)」。
    case introCallRequired = "INTRO_CALL_REQUIRED"
    // 反过来的那一头（后端 2026-08-26 新增）：**已经磨合成功过的一对**又发了 `INTERESTED`。
    //
    // 🚨 这个码是本 App 会真撞上的，不是理论分支：派单弹窗只有「有意向」和「拒绝」两个按钮
    // （`VolunteerHomeView.dispatchOverlay`），界面上**没有任何控件能发 `ACCEPT`**。
    // 所以只把它翻成一句文案就等于让志愿者卡在一个本该能接的单上 ——
    // `respondToDispatch` 收到它会自动改发一次 `ACCEPT`，用户无感。
    //
    // 后端刻意不替客户端转：`INTERESTED` 不构成接单、聊崩了没有统计损失，`ACCEPT` 当场把人
    // 绑在这一单上，把不承诺静默转成承诺是后端最不该做的事。所以这一步必须由客户端做。
    case introCallNotRequired = "INTRO_CALL_NOT_REQUIRED"
    // 固定搭档收藏（后端 `ErrorCode.java:169` / `:176`）。
    //
    // 🚨 `FAVORITE_VOLUNTEER_NOT_ELIGIBLE` 是**两种情况同码同文案**：「没一起跑完过」与
    // 「这个 id 根本不是志愿者」。契约点名要求客户端**不要试图区分** ——
    // 区分开就等于确认了这个 id 是个志愿者，那个端点就成了枚举接口。
    // 所以文案只说门槛，不说「这个人不存在」。
    case favoriteVolunteerNotEligible = "FAVORITE_VOLUNTEER_NOT_ELIGIBLE"
    case favoriteVolunteerLimitExceeded = "FAVORITE_VOLUNTEER_LIMIT_EXCEEDED"
    // 志愿者接单守卫（后端 `ErrorCode.java:109`，2026-09-04 随架构复核 N126 上线）。
    // 在它之前没有任何守卫拦「一个人接两单」—— 接单锁按订单加，拦得住两个人抢一单。
    //
    // 🚨 **文案不能和 `ORDER_ALREADY_ACCEPTED` 共用，两者意思相反**：那个是「这一单被别人抢走了」
    // （该去看别的单），这个是「你自己那个时段有事」（该换个时段的单）。
    //
    // ⚠️ 判据在 2026-09-05 变过一次，文案跟的是**改后**的语义：从「有没有占用中的单」
    // 改成「有没有**时间重叠**的占用中的单」（`DispatchService.hasTimeConflict`，两侧各外扩
    // `app.order.booking-buffer-minutes`）。所以不能说「您还有一单没有完成」——
    // 跨天预约上线后接了后天的单照样能接今天的，照旧文案会让他去找一张根本不冲突的单。
    case volunteerAlreadyEngaged = "VOLUNTEER_ALREADY_ENGAGED"
    // 二要素核验（阿里云 CloudAuth Id2Meta）**服务本身**没跑通：网络/超时/鉴权/配额/返回体残缺。
    // 后端 `AliyunIdVerifyService.verifyIdCard`，两个端点共用
    // （`POST /api/blind/verify-identity` 与 `POST /api/volunteer/registration/step1`）。
    //
    // 🚨 **必须与 `ID_INFO_INVALID`(400) 分开，且绝不引导去核对证件** —— 用户的证件没有任何问题，
    // 让他去核对是在浪费他的时间，重试才有意义。此前这两种情况返的是同一个结果，
    // 而服务故障那次还会把他永久写成 `verifyStatus=FAILED`（只有管理员能改回来）。
    case idVerifyUnavailable = "ID_VERIFY_UNAVAILABLE"

    var localizedMessage: String {
        switch self {
        case .invalidVerificationCode:
            return "验证码错误，请重新输入。"
        case .orderNotFound:
            return "订单不存在。"
        case .orderAlreadyAccepted:
            return "该订单已被其他志愿者接单。"
        case .invalidOrderStatus:
            return "当前订单状态不允许此操作。"
        case .roleAlreadySet:
            return "身份已设定，不可修改。"
        case .volunteerNotAvailable:
            return "您当前未开启接单状态。"
        case .volunteerNotApproved:
            // 后端 `DispatchService` 的接单守卫（403 VOLUNTEER_NOT_VERIFIED）唯一解法是上传资质证书等审核。
            // case 名与 rawValue 不一致是历史命名，不要改 rawValue。
            return "尚未通过资质认证，请先上传资质证书。"
        case .appointmentTooSoon:
            return "预约时间需要至少30分钟之后。"
        case .appointmentTooLong:
            // 只说时长，不提夜间：两条同时命中时后端返回的就是这一条，
            // 而这种单（跨多天）先要改短，改时段没用。
            return "单次陪跑最长5小时，这一单排得太长了。请把时长改短一些再提交。"
        case .appointmentInNightWindow:
            // 🚨 必须说清判据是**整段**。只说「这个时间不能约」的话，21点出发的用户
            // 会认为自己没碰到22点，把开始时间往前挪一点再试一次 —— 而真正越界的是结束时间。
            //
            // 语音那条路**指望不上后端的解析追问兜底**：`/api/orders/voice/parse` 也查夜间窗口
            // （`VoiceOrderService.nightWindowReask`），但那个端点拿不到时长，只能按最短一单
            // （`MIN_DURATION_MINUTES` = 10 分钟）探一次 —— 后端自己在 `:832` 写明了这一点。
            // 于是「21点出发跑两小时」在解析轮照样放行，到提交才被拒，而用户此时已经确认过一遍。
            // 这句话是那种情况下他唯一能听到的解释。
            //
            // 时刻用「晚上10点 / 早上5点」而不是后端那句的 `22:00` / `05:00`：这段要过 TTS，
            // 念数字冒号不如念钟点稳。语义两边一致，措辞刻意不抄。
            return "晚上10点到次日早上5点之间不安排陪跑。这一单从开始到结束整段都要避开这个时段，"
                + "请改到白天，或者把时长改短、让它在晚上10点前结束。"
        case .appointmentTooFar:
            // 不写死「7 天」：那是后端配置，而这条码恰恰是在**客户端那个 7 天已经不对**时才会到达。
            // 念一个错的天数比不念更糟 —— 用户会照着它改，然后再被拒一次。
            return "这个日期太远了，暂时约不了。请改到近一些的日子。"
        case .tooManyScheduledOrders:
            // 同理不写死「3 个」。说清**出路**（完成或取消一个），否则用户不知道自己该做什么。
            return "你手上没跑完的预约已经到上限了。完成或取消其中一个，再来约新的。"
        case .validationFailed:
            return "提交内容不符合要求，请检查后重试。"
        case .unauthorized:
            return "登录已过期，请重新登录。"
        case .activeOrderAccountDeletionBlocked:
            return "当前存在进行中的服务，请处理完成后再删除账户。"
        case .keepWaitingLimitReached:
            return "延长次数已达上限，无法继续等待。"
        case .orderDispatchMismatch:
            return "该订单未派送给您。"
        case .orderConcurrentConflict:
            return "操作冲突，请重试一次。"
        case .tooManyRequests:
            return "请求过于频繁，请稍后再试。"
        case .phoneFormatInvalid:
            return "手机号格式不正确。"
        case .userNotFound:
            return "用户不存在。"
        case .notFound:
            return "请求的资源不存在。"
        case .badRequest:
            return "请求参数有误。"
        case .securityForbidden:
            return "没有权限执行此操作。"
        case .resourceNotFound:
            return "请求的资源不存在。"
        case .duplicateOrder:
            // 🚩 2026-09-05 改口径（跨天预约上线）：后端判据从「有任何未走完的单」改成
            // **时段冲突**（与任一未走完订单的时间区间相交，两侧各外扩 60 分钟）。
            // 原文案「您有进行中的订单，请完成后再下单」自那天起就是错的 ——
            // 约了后天早上的单之后，今天临时想跑**照样能下单**，说成「有进行中的订单」
            // 会让用户去取消一张完全不冲突的预约。
            return "这个时间段你已经有一单了。换个时间再试试。"
        case .reviewAlreadySubmitted:
            return "您已评价过此订单。"
        case .registrationStepInvalid:
            return "注册步骤不正确，请重新开始。"
        case .internalError:
            return "服务器内部错误，请稍后重试。"
        case .idInfoInvalid:
            return "身份信息核验未通过，请检查后重试。"
        case .orderInProgress:
            // 后端只在「取消受阻」这一处抛该码（`OrderLifecycleService`），文案跟着这个唯一场景走。
            return "志愿者已出发或服务进行中，如需取消请联系志愿者。"
        case .orderPermissionDenied:
            // 后端确认该码只剩 `OrderQueryService` 一个抛出点，场景是只读查询越权（handoff Q8）。
            return "您无权查看此订单。"
        case .smsSendLimitExceeded:
            return "短信发送已达上限，请稍后重试。"
        case .identityNotVerified:
            return "还没有完成实名认证，暂时不能下单。请打开设置里的实名认证，填写姓名和身份证号后再预约。"
        case .emergencyContactRequired:
            return "还没有设置紧急联系人，暂时不能下单。请先添加至少 1 位紧急联系人，并把其中 1 位设为主联系人。"
        case .notOrderParticipant:
            return "您不是该订单的参与方。"
        case .invalidTimestamp:
            return "时间参数格式错误。"
        case .emergencyVolunteerCannotDismiss:
            // 文案面向志愿者：他不该有撤销权，能做的只有确认对方是否需要帮助。
            return "志愿者无权撤销求助，请确认对方是否需要帮助。"
        case .emergencyNotOwner:
            return "只能撤销自己发出的紧急求助。"
        case .emergencyAlreadyClosed:
            return "该求助已经结束，无需再操作。"
        case .contactLimitExceeded:
            return "最多添加 5 个紧急联系人，请先删除一个再添加。"
        case .contactMinimumRequired:
            return "至少保留 1 个紧急联系人，请先添加新的再删除。"
        case .contactFieldRequired:
            return "请填写联系人姓名和手机号。"
        case .shareOrderAlreadyFinished:
            return RunPlanLiveShareCopy.alreadyFinished
        case .introCallNotActive:
            return IntroCallCopy.roundAlreadyEnded
        case .introCallRequired:
            return "还没有和这位跑者通过电话，请先选「有意向，想先聊聊」。"
        // 只有**自动改发 `ACCEPT` 也失败**时才会被念到（正常路径下用户看不到这一句）。
        // 所以文案说的是「再点一次」这个还能做的动作，不是解释那个码。
        case .introCallNotRequired:
            return "你们之前已经聊过了，可以直接接单。请再点一次试试。"
        case .favoriteVolunteerNotEligible:
            return PartnerStreakCopy.favoriteNotEligible
        case .favoriteVolunteerLimitExceeded:
            return PartnerStreakCopy.favoriteLimitExceeded
        case .volunteerAlreadyEngaged:
            return "这个时间段您已经答应了另一位跑者，换一个时间段的订单再试试。"
        case .idVerifyUnavailable:
            return "身份认证服务暂时不可用，请稍后重试。"
        }
    }

    var ttsMessage: String {
        localizedMessage
    }
}

// MARK: - Error Response

struct ErrorResponse: Codable, Sendable {
    let code: String
    let message: String
    let retryAfterSeconds: Int?

    init(
        code: String,
        message: String,
        retryAfterSeconds: Int? = nil
    ) {
        self.code = code
        self.message = message
        self.retryAfterSeconds = retryAfterSeconds
    }

    var errorCode: ErrorCode? {
        ErrorCode(rawValue: code)
    }
}

struct RateLimitInfo: Codable, Sendable, Equatable {
    let message: String
    let retryAfterSeconds: Int?
}

// MARK: - Cloud Backend Response Envelope

/// Generic response envelope for cloud backend business endpoints.
/// Format: {"success": bool, "code": int, "message": string, "data": T}
/// `URLSessionAPIClient` 的成功体解码策略，抽出来只为一件事：**能被测试直接驱动**。
///
/// 两个调用点（`request` / `upload`）此前各抄了一份同样的六行。真正需要锁住的是它的顺序语义 ——
/// 先试信封、拿不到 `data` 再裸解 —— 因为有些类型（如 `EmergencyActiveEnvelope`）正是靠
/// 「内层解不出」才落到裸解这一步的，靠读代码推断这条路走不走得通并不可靠。
enum APIPayloadDecoder {
    /// - Note: 信封优先是有意的：字段全可选的模型（如 `BlindProfileResponse`）从信封根对象裸解
    ///   会「成功」但全是 nil。
    static func decodePayload<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        decoder: JSONDecoder
    ) throws -> T {
        if let envelope = try? decoder.decode(APIEnvelopeResponse<T>.self, from: data),
           let payload = envelope.data {
            return payload
        }
        return try decoder.decode(T.self, from: data)
    }
}

struct APIEnvelopeResponse<T: Decodable>: Decodable {
    let success: Bool?
    let code: Int?
    let message: String?
    let data: T?
}

/// Empty success payload for endpoints where the client only needs HTTP success.
struct EmptyResponse: Decodable, Sendable {
    init() {}
    init(from decoder: Decoder) throws {}
}

/// Flexible cloud error payload. The demo backend currently returns multiple
/// shapes, including `errorCode`, numeric/string `code`, and `message`.
///
/// 不再解 `error` 键：后端唯一带裸 `error` 的两处分别是 429（同时恒带 `message`，
/// 且后端已确认要删这个冗余键）和 `AuthController` 的 401 —— 而 401 在 `APIClient`
/// 里解 body 之前就 `throw .unauthorized`，这条兜底永远走不到。
struct APIErrorEnvelope: Decodable {
    let success: Bool?
    let code: String?
    let errorCode: String?
    let message: String?
    let retryAfterSeconds: Int?

    private enum CodingKeys: String, CodingKey {
        case success, code, errorCode, message, retryAfterSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        errorCode = try container.decodeIfPresent(String.self, forKey: .errorCode)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        retryAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .retryAfterSeconds)
        if let stringCode = try? container.decodeIfPresent(String.self, forKey: .code) {
            code = stringCode
        } else if let intCode = try? container.decodeIfPresent(Int.self, forKey: .code) {
            code = String(intCode)
        } else {
            code = nil
        }
    }

    func resolvedErrorResponse(statusCode: Int) -> ErrorResponse? {
        guard let resolvedMessage = message else { return nil }
        return ErrorResponse(
            code: errorCode ?? code ?? "HTTP_\(statusCode)",
            message: resolvedMessage,
            retryAfterSeconds: retryAfterSeconds
        )
    }
}
