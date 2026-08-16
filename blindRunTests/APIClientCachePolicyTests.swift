//
//  APIClientCachePolicyTests.swift
//  blindRunTests
//
//  API session 不许挂 URL 缓存 —— 缓存住的永久重定向会在本地重放并剥掉 Authorization。
//

import XCTest
@testable import blindRun

/// 守 2026-08-16 线上 P0（后端 ISSUES N96）：`URLSessionConfiguration.default` 用的是
/// `URLCache.shared`，CFNetwork 会把 301/308 **永久重定向按 URL 存进去并在本地重放**，
/// 之后请求根本不到服务器，而 http→https 的本地改写会剥掉 `Authorization` ——
/// 后端收到没鉴权的请求返 401，App 渲染成「登录已过期」。
///
/// 这条门槛很低但值得存在：故障现场在**服务端已经回滚之后依然复现**，且只影响
/// 那一小时里被访问过的 URL（表现成「志愿者登不进去、盲人正常」），排查方向被带偏了整整一天。
/// 有人把这两行删掉或改回 `URLSessionConfiguration.default`，这条会红。
final class APIClientCachePolicyTests: XCTestCase {

    func testAPISessionHasNoURLCache() {
        XCTAssertNil(
            URLSessionAPIClient.defaultSession.configuration.urlCache,
            "API session 不许挂 URL 缓存：缓存住的 308 会在本地重放并剥掉 Authorization"
        )
    }

    func testAPISessionIgnoresLocalCacheData() {
        XCTAssertEqual(
            URLSessionAPIClient.defaultSession.configuration.requestCachePolicy,
            .reloadIgnoringLocalCacheData,
            "API 请求必须每次真的问服务器，不许用本地缓存条目回答"
        )
    }

    /// `urlCache = nil` 只有在它**不是** `URLCache.shared` 时才说明设置生效了。
    /// 这条防的是「有人以为设了、其实赋回了共享缓存」——两者都非 nil，上面那条就抓不到。
    func testAPISessionDoesNotFallBackToTheSharedCache() {
        XCTAssertFalse(
            URLSessionAPIClient.defaultSession.configuration.urlCache === URLCache.shared,
            "共享缓存正是那条永久重定向的存放处，API session 绝不能用它"
        )
    }
}
