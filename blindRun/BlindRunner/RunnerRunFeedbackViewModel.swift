import Combine
import SwiftUI

// 跑者跑步详情底部的「陪跑员」一节与「这次陪跑怎么样」（#831，定稿 `docs/ui/mockups/order-done-review-20261107/`）。
// 评价与「设为固定搭档」原先在已完成订单页（`BlindOrderStatusViewModel`），11-07 负责人定挪到这里，订单页只留绿色卡。

@MainActor
final class RunnerRunFeedbackViewModel: ObservableObject {
    /// 「陪跑员」一节第二行。`unknown` = 查不到是不是搭档：只显示名字，不给按钮和状态句（定稿「其他状态」）。
    enum PartnerStatus: Equatable {
        case unknown
        case notPartner
        case partner
        case optedOut

        var text: String? {
            switch self {
            case .unknown: return nil
            case .notPartner: return PartnerStreakCopy.blindNotFavoriteYet
            case .partner: return PartnerStreakCopy.blindYourPartner
            case .optedOut: return PartnerStreakCopy.partnerOptedOutSuffix
            }
        }
    }

    // MARK: 评价

    @Published var reviewRating: Int?
    @Published var reviewComment = ""
    @Published private(set) var isSubmittingReview = false
    @Published private(set) var reviewErrorMessage: String?
    /// 评过了（本页刚提交，或后端读回有评价）。评过的只读，不能改。
    @Published private(set) var didSubmitReview = false
    @Published private(set) var existingReview: OrderReview?
    /// 「有没有评过」查完之前整块不出现：先摆表单再换成只读卡，读屏会念到一张马上消失的表。
    @Published private(set) var hasLoadedReview = false

    // MARK: 陪跑员

    @Published private(set) var volunteerId: Int64?
    @Published private(set) var volunteerName: String?
    @Published private(set) var partnerStatus: PartnerStatus = .unknown
    /// 进搭档详情页用的那一行。是固定搭档时取自固定搭档列表；不是时只有 id 和名字，其余留空，不编。
    @Published private(set) var partnerRow: PartnerRow?
    @Published private(set) var isUpdatingFavorite = false
    @Published private(set) var favoriteNotice: String?
    @Published private(set) var favoriteErrorMessage: String?
    /// 在个人页选了「不再匹配此人」。之后卡里不再给「设为固定搭档」。
    @Published private(set) var didBlockVolunteer = false

    private(set) var orderId: Int64?
    private weak var appState: AppState?
    private weak var speech: SpeechService?

    /// ⚠️ `appState` / `speech` 是 weak：用例要自己持有。
    func configure(appState: AppState, speech: SpeechService?) {
        self.appState = appState
        self.speech = speech
    }

    /// 订单详情读到后调一次。只认 `COMPLETED`：评价与收藏的门槛都是跑完。
    func load(order: OrderDetailResponse) async {
        // 同一单只查一次；上一次被取消（没查完）时允许重来。
        guard order.status == .completed, !(orderId == order.orderId && hasLoadedReview) else { return }
        bind(order: order)
        await loadExistingReview()
        await loadPartnerState()
    }

    /// 记下是哪一单、谁陪的，不发请求。单测直接调它，免得为评价用例去打搭档接口。
    func bind(order: OrderDetailResponse) {
        orderId = order.orderId
        volunteerId = order.volunteerId
        volunteerName = order.volunteerName?.nilIfBlank
    }

    // MARK: 评价

    func submitReview() async {
        guard let orderId, let appState, !isSubmittingReview else { return }
        guard let rating = reviewRating, (1...5).contains(rating) else { // 默认不选（#660 B-30）
            failReview(RunExperienceRating.missingSelectionMessage)
            return
        }
        isSubmittingReview = true
        reviewErrorMessage = nil
        defer { isSubmittingReview = false }
        let comment = reviewComment.nilIfBlank
        do {
            try await appState.orders.submitReview(CreateReviewRequest(rating: rating, comment: comment), orderId: orderId)
            didSubmitReview = true
            // 本页刚提交的也显示成只读卡。时间先留空，下次进来读回后端的。
            existingReview = OrderReview(orderId: orderId, rating: rating, level: nil, comment: comment, createdAt: nil)
            speech?.speak("评价已提交，感谢反馈。")
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return }
            // 已评价过不是失败：切到只读卡，把那条评价取回来（后端 2026-07-31 起专用码）。
            if error.errorCode == .reviewAlreadySubmitted {
                didSubmitReview = true
                speech?.speak(ErrorCode.reviewAlreadySubmitted.localizedMessage)
                await loadExistingReview()
                return
            }
            failReview(error.localizedMessage)
        } catch {
            failReview("评价提交失败，请稍后重试。")
        }
    }

    /// 选档或改评语时收起上一次的失败原因。
    func clearReviewError() {
        reviewErrorMessage = nil
    }

    private func failReview(_ message: String) {
        reviewErrorMessage = message
        speech?.speakError(message)
    }

    /// `GET /api/orders/{id}/reviews`：没评过回 200 + `data: null`。
    /// 失败不提示：按没评过显示，重复提交由 `REVIEW_ALREADY_SUBMITTED` 兜住。
    private func loadExistingReview() async {
        // 先挂 defer：拿不到 appState 时也要按「没评过」显示，不能整节一直不出现。
        defer { hasLoadedReview = true }
        guard let orderId, let appState else { return }
        do {
            let envelope = try await appState.orders.reviews(orderId: orderId)
            if let review = envelope.data {
                existingReview = review
                didSubmitReview = true
            }
        } catch {
            return
        }
    }

    // MARK: 陪跑员

    /// 进个人页用的那一行。查不到搭档状态时用只有 id 和名字的一行（个人页据 `partnerStatus` 不给设为 / 取消）。
    var personRow: PartnerRow? {
        guard let volunteerId else { return nil }
        return partnerRow ?? Self.bareRow(volunteerId: volunteerId, name: volunteerName)
    }

    /// 只有 id 和名字，其余留空，不编。
    static func bareRow(volunteerId: Int64, name: String?) -> PartnerRow {
        PartnerRow(
            userId: volunteerId, name: name, completedRunsTogether: nil, favoritedAt: nil,
            hasOptedOut: false, streak: nil, isFavorite: false
        )
    }

    /// 固定搭档列表 ⋈ 火花，找这一单的陪跑员。找不到 = 还不是搭档。
    /// 失败一律静默：唯一后果是「陪跑员」一节只剩名字（`PartnerStatus.unknown`）。
    func loadPartnerState() async {
        guard let appState, let volunteerId else { return }
        do {
            let favorites = try await appState.incentive.blindFavoriteVolunteers()
            // 火花拿不到不影响搭档关系，只是详情页少一张连续周数卡。
            let streaks = (try? await appState.incentive.blindPartnerStreaks()) ?? []
            let rows = PartnerRowMerge.blindRows(favorites: favorites, streaks: streaks)
            if let row = rows.first(where: { $0.userId == volunteerId && $0.isFavorite }) {
                partnerRow = row
                partnerStatus = row.hasOptedOut ? .optedOut : .partner
            } else {
                partnerRow = rows.first { $0.userId == volunteerId } ?? Self.bareRow(volunteerId: volunteerId, name: volunteerName)
                partnerStatus = .notPartner
            }
        } catch let error as APIError {
            appState.handleAuthenticatedAPIError(error)
            partnerStatus = .unknown
        } catch {
            partnerStatus = .unknown
        }
    }

    /// 卡里「设为固定搭档」。`PUT` 幂等、恒 204。成功和失败都在卡下多一行字并播报。
    func addVolunteerToFavorites() async {
        _ = await setFavorite(true)
    }

    /// 卡里的按钮和搭档详情页共用。成功返回 nil，失败返回给人看的原因（详情页写在按钮下面）。
    /// 上屏带掩码星号；播报去掉星号（`String.unmaskedForSpeech`）。
    func setFavorite(_ isFavorite: Bool) async -> String? {
        guard let appState, let volunteerId, !isUpdatingFavorite else { return PartnerStreakCopy.favoriteFailed }
        let name = volunteerName ?? PartnerStreakCopy.unknownVolunteerName
        let spokenName = volunteerName?.unmaskedForSpeech.nilIfBlank ?? PartnerStreakCopy.unknownVolunteerName
        isUpdatingFavorite = true
        favoriteErrorMessage = nil
        favoriteNotice = nil
        defer { isUpdatingFavorite = false }
        do {
            if isFavorite {
                try await appState.incentive.addBlindFavoriteVolunteer(volunteerId: volunteerId)
            } else {
                try await appState.incentive.removeBlindFavoriteVolunteer(volunteerId: volunteerId)
            }
            favoriteNotice = isFavorite ? PartnerStreakCopy.favoriteAdded(name) : PartnerStreakCopy.favoriteRemoved(name)
            speech?.speak(isFavorite ? PartnerStreakCopy.favoriteAdded(spokenName) : PartnerStreakCopy.favoriteRemoved(spokenName))
            await loadPartnerState()
            return nil
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return error.localizedMessage }
            // 收藏专属错误码的文案挂在 `ErrorCode.localizedMessage` 上，这里不再映射一遍。
            return failFavorite(error.localizedMessage)
        } catch {
            return failFavorite(PartnerStreakCopy.favoriteFailed)
        }
    }

    private func failFavorite(_ message: String) -> String {
        favoriteErrorMessage = message
        speech?.speakError(message)
        return message
    }

    /// 在搭档详情页里选了「不再匹配此人」。那一页自己念了结果并关掉，这里在卡下留一行字，再重读搭档状态。
    func volunteerBlocked() async {
        favoriteErrorMessage = nil
        favoriteNotice = UserSafetyCopy.blockSucceeded
        didBlockVolunteer = true
        await loadPartnerState()
    }
}
