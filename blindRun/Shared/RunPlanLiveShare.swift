import Foundation

// MARK: - Contract

/// `POST /api/orders/{id}/share` 的响应（`api_spec.yaml` 的 `ShareLinkResponse`）。
struct ShareLinkResponse: Decodable, Sendable, Equatable {
    /// 完整链接，**原样交给系统分享面板**。令牌在 fragment 里，见 `RunPlanLiveShareMessage`。
    let shareUrl: String
    /// 链接失效时间，后端算的是 `max(plannedEndTime, now) + 2 小时`。
    /// 客户端只有展示的份 —— 自己按 `plannedEnd` 推会和家属那边看到的对不上。
    /// 契约里是必填，这里仍收成 optional：少一个字段不该让整条分享失败。
    let expiresAt: String?
}

// MARK: - Copy

/// 实时行程分享的全部对外文案。与 `RunPlanShareCopy`（静态短信）分开：
/// 那条是「一次性把行程要素告诉家人」，这条是「持续提供实时位置」，
/// 合规性质、可撤回性、失败后果都不同，合并成一份文案必然有一边说错。
///
/// **同一条红线**：不许出现「已通知」「家人已收到」「已送达」。
/// 系统分享面板的完成回调只代表用户选了一个目标应用，不代表对方收到了。
/// `scripts/hooks/guard.mjs` 的 `emergency-sms-delivery-claim` 规则会拦这类措辞。
enum RunPlanLiveShareCopy {
    static let buttonTitle = "分享实时位置给家人"

    /// hint 说清「先告知再生成」：盲人按下去后第一屏不是分享面板而是告知页，
    /// 不说清会以为按错了。
    static let accessibilityHint = "会先说明分享什么内容，你同意后才生成链接"

    static let stopButtonTitle = "停止分享实时位置"
    static let stopAccessibilityHint = "停止后，已经发出去的链接立刻失效"

    static let preparing = "正在生成分享链接。"

    /// 生成成功。**只说到「链接已生成」为止** —— 后面选发给谁、发不发得出去，
    /// 都在系统分享面板里，App 不掌控也无从得知。
    static let ready = "链接已生成，请在分享面板里选择发给谁。"

    /// 分享面板关掉后的状态播报。盲人看不到面板收起，不播就等于按下去什么都没发生。
    static let sharing = "实时位置正在分享中，可以随时停止。"
    static let panelDismissed = "分享面板已关闭，实时位置仍在分享中，可以随时停止。"

    static let stopping = "正在停止分享。"
    /// 停止是**服务端确认过的** 204，这句可以用完成时。
    static let stopped = "已停止分享，链接已失效。"
    static let stopFailed = "没能停止分享，链接可能仍然有效，请稍后再试一次。"

    /// 终态竞态：页面每 5 秒轮询，用户可能在订单刚结束的那个窗口里按下按钮。
    /// 后端此时返 409 `SHARE_ORDER_ALREADY_FINISHED`。
    static let alreadyFinished = "这次行程已经结束，不能再开新的分享链接。"

    static let smsFallbackButtonTitle = "改用短信告诉家人"
    static let smsFallbackHint = "发送一条写好行程信息的短信，不含实时位置"

    /// 失败提示。前半句是具体原因（网络 / 权限 / 409），后半句给出路。
    /// 不劝重试 —— 盲人此刻更需要的是一条能立刻走通的路，而不是再按一次同一个按钮。
    static func failed(_ reason: String, offersSMSFallback: Bool) -> String {
        offersSMSFallback ? "\(reason)可以改用短信告诉家人。" : reason
    }
}

// MARK: - Share payload

/// 分享面板要发出去的正文。**纯函数，不 import UIKit，可单测。**
enum RunPlanLiveShareMessage {
    static let intro = "我正在使用助盲跑陪跑服务，这是我的实时位置："

    /// ⚠️ **`shareUrl` 必须原样带出去，一个字符都不许改写。**
    ///
    /// 令牌在 URL 的 fragment 里（`.../share.html#<token>`）而不是 query，这是后端刻意的：
    /// fragment 不进 `Referer`、不上服务端访问日志，而那个分享页要加载高德 JS SDK
    /// 这个第三方脚本。把令牌挪成 `?t=<token>`「让链接更规整」，等于把一个 43 字符的
    /// 免登录凭据交给第三方脚本和一路上的日志（`api_spec.yaml` 的 `createShareLink` 说明）。
    ///
    /// `RunPlanLiveShareTests.testShareTextCarriesTheUrlVerbatim` 钉住这条。
    static func compose(shareUrl: String) -> String {
        "\(intro)\n\(shareUrl)"
    }
}

// MARK: - Local share state

/// 「哪一单正在实时分享」的本地记录。
///
/// **为什么必须持久化**：告知页逐字承诺「你可以随时停止分享」，而后端**没有查询分享状态的
/// 端点** —— `/api/orders/{id}/share` 只有 `POST` 和 `DELETE`，`OrderDetailResponse` 里
/// 也没有分享状态字段（`api_spec.yaml` 的 required 列表可查）。只存在内存里的话，
/// App 一重启这个承诺就静默失效：链接还在外面有效，用户却再也找不到停止的入口。
/// 已向后端提出补 `shareActive` / `shareExpiresAt`，补上后这个类可以删掉。
///
/// **只存一个订单号，不是每单一个 key**：盲人同一时刻只可能有一个进行中的订单
/// （后端 `DUPLICATE_ORDER` 挡着），所以「正在分享的那一单」天然是单值。
/// 按单存会在 `UserDefaults` 里堆下无上限的历史 key，而且没有任何一处会去清它们。
struct RunPlanLiveShareStore {
    static let storageKey = AppStatePersistenceKeys.runPlanLiveShareOrderId

    private let persistence: any AppStatePersistence

    init(persistence: any AppStatePersistence) {
        self.persistence = persistence
    }

    func isSharing(orderID: Int64) -> Bool {
        persistence.string(forKey: Self.storageKey) == String(orderID)
    }

    func markSharing(orderID: Int64) {
        persistence.set(String(orderID), forKey: Self.storageKey)
    }

    func clear() {
        persistence.removeObject(forKey: Self.storageKey)
    }
}
