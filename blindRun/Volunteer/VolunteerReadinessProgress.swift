// 陪跑员「接单前还差什么」的判定与文案。
//
// 只 import Foundation，与 `VolunteerProfileFirstScreen.swift` 同一个分法：这里出错时屏幕上
// 只是一张排版正常的页面，写成纯函数才有可以验红的测试面。
//
// 派单资格的权威来源是 `GET /api/volunteer/dispatch-summary` 的 `canDispatch` 与
// `notAvailableReasons`。`AppState.isVolunteerProfileApproved` 只说注册走完没有，
// 拿它判滑块就是审计 V-6：陪跑员看到「接单中」，而后端不会派单给他。
import Foundation

// MARK: - 文案

/// 证书标准与合作方相关文案的唯一落点。
///
/// 🚩 一束光的联系方式还没有，**不要编**。拿到之后只改 `noCertificateHelp` 这一句。
enum VolunteerCertificateCopy {
    /// 负责人 2026-11-02 定：证书标准是一束光助盲跑团颁发的证书。
    static let issuerName = "一束光助盲跑团"
    static let requirement = "请上传\(issuerName)颁发的证书。"
    static let reviewerNote = "提交后由团队在后台审核，通过后才能接单。"
    static let noCertificateHelp = "还没有证书？请联系\(issuerName)。"
    static let rejectionFallback = "暂时看不到具体原因。请核对证书后重新上传，或联系\(issuerName)。"
    static let alternativeRejectionFallback = "暂时看不到具体原因。请核对材料后重新上传。"

    /// 后端给的是审核人手写的自由文本，只去首尾空白，不改写。
    static func rejectionDetail(reason: String?, isAlternativeIdentityPath: Bool) -> String {
        if let reason = reason?.nilIfBlank { return "未通过原因：\(reason)" }
        return isAlternativeIdentityPath ? alternativeRejectionFallback : rejectionFallback
    }
}

enum VolunteerReadinessCopy {
    static let navigationTitle = "接单前进度"
    static let progressButtonTitle = "查看接单前进度"
    static let confirmingTitle = "正在确认接单状态"
    static let progressButtonHint = "打开接单前进度，查看还差哪几步"
    static let tapForProgress = "点这里看进度"
    /// 注册流程走到底时念的那一句。不说「注册完成」：后面还有证书、审核、培训。
    static let completionAnnouncement = "实名和人脸认证已完成，请查看接单前还差哪几步"
    static let awaitingCompletion = "活体已通过，正在同步注册状态"
    static let everyStepDoneTitle = "接单前的步骤都完成了"
    static let unknownTitle = "暂时无法确认全部进度"
    static let unknownSubtitle = "请检查网络后重新获取。"
    static let reloadTitle = "重新获取进度"
    static let statusUnknown = "状态未知"

    static func remainingTitle(_ count: Int) -> String { "还差 \(count) 步才能接单" }
}

// MARK: - 滑块状态

/// 首页滑块此刻该说什么。全 App 判「是不是真的在接单」只走这一个类型。
enum VolunteerAvailabilityStatus: Equatable {
    /// 开关关着，滑开就能开始等派单。
    case canOpen
    /// 资质审核没过。开着关着都一样：滑动解决不了。
    case blockedByCertificate
    /// 必修培训没完成。与资质可以同时成立，资质优先（后端引导顺序）。
    case blockedByTraining
    /// 账号被平台停用。优先于资质和培训：那两步做完也接不了单。
    case blockedBySuspension
    /// 开着，派单摘要确认可派单。**只有这一态能说「接单中」。**
    case accepting
    /// 开着，但摘要还没到，或还是开启之前的那一份。
    case confirming
    /// 开着，但后端说不在线。
    case notOnline
    /// 开着，可派单不为真，原因认不出或者没给。
    case unavailable(explanation: String)

    /// - Parameters:
    ///   - hasSummary: 派单摘要到了没有。没到时不知道能不能派单，不能往好处猜。
    ///   - explanation: 摘要自己给的说明（`reasonText`），未识别的原因走它。
    static func resolve(
        isAvailable: Bool,
        hasSummary: Bool,
        canDispatch: Bool?,
        reasons: [VolunteerDispatchNotAvailableReason],
        explanation: String
    ) -> VolunteerAvailabilityStatus {
        if reasons.contains(.accountSuspended) { return .blockedBySuspension }
        if reasons.contains(.notVerified) { return .blockedByCertificate }
        if reasons.contains(.trainingIncomplete) { return .blockedByTraining }
        guard isAvailable else { return .canOpen }
        guard hasSummary else { return .confirming }
        if canDispatch == true { return .accepting }
        // 开关是开着的而摘要说「已关闭接单」：这份摘要早于开启那一下。
        if reasons.contains(.dispatchDisabled) { return .confirming }
        if reasons.contains(.offline) { return .notOnline }
        return .unavailable(explanation: explanation)
    }

    /// 滑动解决不了的三态，滑块不许滑开。
    var blocksOpening: Bool {
        self == .blockedByCertificate || self == .blockedByTraining || self == .blockedBySuspension
    }

    var isAccepting: Bool { self == .accepting }

    /// 滑块能不能滑开。注册没走完的人不该到这一屏，这一项是防御。
    func allowsOpening(isRegistrationComplete: Bool) -> Bool {
        isRegistrationComplete && !blocksOpening
    }

    /// `canOpen` 与 `accepting` 没有要解释的事，返回 nil。
    func notice(
        certificate: VolunteerCertificateDisplayState,
        isAlternativeIdentityPath: Bool
    ) -> VolunteerAvailabilityNotice? {
        switch self {
        case .canOpen, .accepting:
            return nil
        case .blockedByCertificate:
            let noun = isAlternativeIdentityPath ? "身份材料" : "证书"
            let state: String
            switch certificate {
            case .notSubmitted: state = "还没上传\(noun)"
            case .pending: state = "\(noun)审核中"
            case .rejected: state = "\(noun)未通过审核"
            case .approved, .statusUnavailable: state = "还没通过资质审核"
            }
            return VolunteerAvailabilityNotice(
                title: Self.blockedTitle,
                detail: "\(state)，\(VolunteerReadinessCopy.tapForProgress)"
            )
        case .blockedByTraining, .blockedBySuspension:
            let detail = self == .blockedBySuspension
                ? AccountSuspensionCopy.dispatchNotice
                : "还没完成必修培训，\(VolunteerReadinessCopy.tapForProgress)"
            return VolunteerAvailabilityNotice(title: Self.blockedTitle, detail: detail)
        case .confirming:
            return VolunteerAvailabilityNotice(title: VolunteerReadinessCopy.confirmingTitle, detail: nil)
        case .notOnline:
            return VolunteerAvailabilityNotice(
                title: Self.pausedTitle,
                detail: "未在线，请保持 App 打开并允许定位"
            )
        case .unavailable(let explanation):
            return VolunteerAvailabilityNotice(title: Self.pausedTitle, detail: explanation)
        }
    }

    private static let blockedTitle = "暂不能接单"
    private static let pausedTitle = "暂时收不到派单"
}

struct VolunteerAvailabilityNotice: Equatable {
    let title: String
    let detail: String?

    /// 读屏念的那一句：标题加说明。
    var spoken: String {
        [title, detail].compactMap { $0 }.joined(separator: "，")
    }
}

// MARK: - 总进度

/// 实名、人脸、证书、审核、培训五步的总进度。注册结束页与首页共用。
struct VolunteerReadinessProgress: Equatable {
    enum StepKind: String, CaseIterable, Equatable {
        case identity, face, certificate, review, training
    }

    enum StepState: Equatable {
        case done, actionNeeded, inReview, waiting, rejected, unknown
    }

    /// 这一步该去哪里解决。实名、人脸没有去处：没走完的人根本进不了首页，
    /// 根路由会把他留在注册流程里。
    enum Destination: Equatable {
        case certificateUpload, training
    }

    struct Step: Equatable, Identifiable {
        let kind: StepKind
        let title: String
        let state: StepState
        let statusText: String
        var detail: String?
        var destination: Destination?

        var id: StepKind { kind }

        var spoken: String {
            [title, statusText, detail].compactMap { $0 }.joined(separator: "，")
        }
    }

    let steps: [Step]
    /// 派单摘要说开关还关着。开关开着却接不到单时，不能再叫他去开。
    var isSwitchedOff = false

    var remainingCount: Int {
        steps.filter { $0.state != .done }.count
    }

    private var hasUnknownStep: Bool {
        steps.contains { $0.state == .unknown }
    }

    /// 全部走完才算可以接单。有一步未知时不下结论。
    var isComplete: Bool { remainingCount == 0 }

    var title: String {
        if hasUnknownStep { return VolunteerReadinessCopy.unknownTitle }
        if isComplete { return VolunteerReadinessCopy.everyStepDoneTitle }
        return VolunteerReadinessCopy.remainingTitle(remainingCount)
    }

    /// 还差几步时没有副标题：标题已经说完了，再写一行只是多划一次读屏。
    var subtitle: String? {
        if hasUnknownStep { return VolunteerReadinessCopy.unknownSubtitle }
        return isComplete && isSwitchedOff ? VolunteerAvailabilityCopy.goOpenItHint : nil
    }

    var spoken: String {
        ([title, subtitle].compactMap { $0 } + steps.map(\.spoken)).joined(separator: " ")
    }

    /// - Parameters:
    ///   - registration: nil = 读取失败，实名与人脸两步显示未知。
    ///   - certificate: 证书审核状态。`statusUnavailable` 时证书与审核两步显示未知。
    ///   - dispatchReasons: nil = 派单摘要没拿到。培训只能从这里知道，拿不到就是未知，
    ///     不能当成未完成（对学完的人是假话），也不能当成已完成。
    static func resolve(
        registration: VolunteerRegistrationStatus?,
        certificate: VolunteerCertificateDisplayState,
        certificateRejectionReason: String?,
        dispatchReasons: [VolunteerDispatchNotAvailableReason]?
    ) -> VolunteerReadinessProgress {
        let isAlternative = registration?.hasDeclinedFaceVerification == true
        // 两个接口说法相反时不下结论：说「都完成了」会让他在滑块和这一页之间来回打转。
        let certificate = certificate == .approved && dispatchReasons?.contains(.notVerified) == true
            ? .statusUnavailable
            : certificate
        return VolunteerReadinessProgress(
            steps: [
                identityStep(registration),
                faceStep(registration),
                certificateStep(certificate, isAlternative: isAlternative),
                reviewStep(certificate, reason: certificateRejectionReason, isAlternative: isAlternative),
                trainingStep(dispatchReasons)
            ],
            isSwitchedOff: dispatchReasons?.contains(.dispatchDisabled) == true
        )
    }

    private static func identityStep(_ registration: VolunteerRegistrationStatus?) -> Step {
        let title = "实名"
        guard let registration else { return unknownStep(.identity, title: title) }
        switch registration.resolvedIdVerifyStatus {
        case "REJECTED":
            return Step(
                kind: .identity, title: title, state: .rejected, statusText: "未通过",
                detail: registration.stepDetails?.idVerifyRejectionReason?.nilIfBlank
                    ?? "暂时看不到具体原因。请核对后重新提交身份信息。"
            )
        case "PENDING":
            return Step(kind: .identity, title: title, state: .inReview, statusText: "核验中")
        case "APPROVED":
            return Step(kind: .identity, title: title, state: .done, statusText: "已通过")
        default:
            // 存量账号这一列可能是 NOT_STARTED / NULL，后端活体路径只拦 REJECTED。
            return registration.isRegistrationComplete
                ? Step(kind: .identity, title: title, state: .done, statusText: "已通过")
                : Step(kind: .identity, title: title, state: .actionNeeded, statusText: "待完成")
        }
    }

    private static func faceStep(_ registration: VolunteerRegistrationStatus?) -> Step {
        let title = "人脸"
        guard let registration else { return unknownStep(.face, title: title) }
        // 拒绝人脸是法定等效路径，不是失败态（后端契约原话）。
        if registration.hasDeclinedFaceVerification {
            return Step(kind: .face, title: title, state: .done, statusText: "已改用人工审核")
        }
        if registration.isFaceVerificationRejected {
            return Step(
                kind: .face, title: title, state: .rejected, statusText: "未通过",
                detail: registration.stepDetails?.faceVerifyRejectionReason?.nilIfBlank
                    ?? "暂时看不到具体原因。请重新认证。"
            )
        }
        return registration.isFaceVerificationApproved || registration.isRegistrationComplete
            ? Step(kind: .face, title: title, state: .done, statusText: "已通过")
            : Step(kind: .face, title: title, state: .actionNeeded, statusText: "待完成")
    }

    private static func certificateStep(
        _ certificate: VolunteerCertificateDisplayState,
        isAlternative: Bool
    ) -> Step {
        let title = isAlternative ? "身份材料" : "证书"
        let requirement = isAlternative
            ? "上传能证明本人身份的材料"
            : "\(VolunteerCertificateCopy.requirement)\(VolunteerCertificateCopy.noCertificateHelp)"
        switch certificate {
        case .notSubmitted:
            return Step(
                kind: .certificate, title: title, state: .actionNeeded, statusText: "待上传",
                detail: requirement, destination: .certificateUpload
            )
        case .rejected:
            return Step(
                kind: .certificate, title: title, state: .actionNeeded, statusText: "需要重新上传",
                destination: .certificateUpload
            )
        case .pending, .approved:
            return Step(kind: .certificate, title: title, state: .done, statusText: "已提交")
        case .statusUnavailable:
            return unknownStep(.certificate, title: title)
        }
    }

    private static func reviewStep(
        _ certificate: VolunteerCertificateDisplayState,
        reason: String?,
        isAlternative: Bool
    ) -> Step {
        let title = "审核"
        switch certificate {
        case .notSubmitted:
            return Step(kind: .review, title: title, state: .waiting, statusText: "等待提交")
        case .pending:
            return Step(
                kind: .review, title: title, state: .inReview, statusText: "审核中",
                // 不编审核时长；后端也没有 SLA 字段。审核通过目前不推送到手机（backend#907），所以要说回来看。
                detail: isAlternative
                    ? "该方式审核时间较长，但结果等效。结果出来后这里会更新，请记得回来查看。"
                    : "团队正在后台审核。结果出来后这里会更新，请记得回来查看。"
            )
        case .approved:
            return Step(kind: .review, title: title, state: .done, statusText: "已通过")
        case .rejected:
            return Step(
                kind: .review, title: title, state: .rejected, statusText: "未通过",
                detail: VolunteerCertificateCopy.rejectionDetail(
                    reason: reason,
                    isAlternativeIdentityPath: isAlternative
                )
            )
        case .statusUnavailable:
            return unknownStep(.review, title: title)
        }
    }

    private static func trainingStep(_ reasons: [VolunteerDispatchNotAvailableReason]?) -> Step {
        let title = "培训"
        guard let reasons else { return unknownStep(.training, title: title) }
        guard reasons.contains(.trainingIncomplete) else {
            return Step(kind: .training, title: title, state: .done, statusText: "已完成")
        }
        return Step(
            kind: .training, title: title, state: .actionNeeded, statusText: "待完成",
            detail: "完成必修课程后才会收到系统派单", destination: .training
        )
    }

    private static func unknownStep(_ kind: StepKind, title: String) -> Step {
        Step(kind: kind, title: title, state: .unknown, statusText: VolunteerReadinessCopy.statusUnknown)
    }
}
