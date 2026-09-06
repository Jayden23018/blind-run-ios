import XCTest
@testable import blindRun

/// `OrderEndpoint` 的方法与路径。
///
/// 这一条接管的是迁移前散在各个传输桩里的路径断言（`path.hasSuffix("/keep-waiting")`、
/// `path == "/api/orders/504"` 之类）。桩换成 `FakeOrderService` 之后路径不再经过用例，
/// 而**路径本身仍然必须被钉住** —— 它是与后端契约对撞的那一面。
///
/// 只查两件事：路径写对没有、方法选对没有。没有业务判定，所以不需要 `AppState`。
final class OrderEndpointTests: XCTestCase {

    /// 契约门禁 `validate-spec-coverage.mjs` 扫的是**字面量**。
    /// 这里逐条对一遍，等于把「路径在源码里长什么样」也纳入用例。
    func testEveryEndpointResolvesToItsContractPath() {
        let cases: [(OrderEndpoint, HTTPMethod, String)] = [
            (.create, .post, "/api/orders"),
            (.mine, .get, "/api/orders/mine"),
            (.active, .get, "/api/orders/active"),
            (.detail(orderId: 42), .get, "/api/orders/42"),
            (.cancel(orderId: 42), .post, "/api/orders/42/cancel"),
            (.respond(orderId: 42), .post, "/api/orders/42/respond"),
            (.enRoute(orderId: 42), .post, "/api/orders/42/en-route"),
            (.arrived(orderId: 42), .post, "/api/orders/42/arrived"),
            (.startService(orderId: 42), .post, "/api/orders/42/start-service"),
            (.finish(orderId: 42), .post, "/api/orders/42/finish"),
            (.review(orderId: 42), .post, "/api/orders/42/review"),
            (.reviews(orderId: 42), .get, "/api/orders/42/reviews"),
            (.statusLogs(orderId: 42), .get, "/api/orders/42/status-logs"),
            (.startLiveShare(orderId: 42), .post, "/api/orders/42/share"),
            (.stopLiveShare(orderId: 42), .delete, "/api/orders/42/share"),
            (.volunteerLocation, .get, "/api/blind/volunteer-location"),
            (.dispatchSummary, .get, "/api/volunteer/dispatch-summary"),
            (.dispatchStatus, .put, "/api/volunteer/dispatch-status"),
        ]

        for (endpoint, method, path) in cases {
            let request = endpoint.request
            XCTAssertEqual(request.path, path, "路径不符：\(path)")
            XCTAssertEqual(request.method, method, "方法不符：\(path)")
        }
    }

    /// 🚨 **延长那两条是 `PUT`，不是 `POST`。**
    ///
    /// 其余订单流转端点全走 `POST`，只有这两条不同族（`api_spec.yaml:236` / `:256`）。
    /// 顺手写成 `POST` 会得到 405，而盲人这一侧看到的只是「继续等待」按下去报了个错。
    func testKeepWaitingEndpointsAreThePutOutliers() {
        XCTAssertEqual(
            OrderEndpoint.keepWaiting(.keepWaiting, orderId: 501).request.method,
            .put
        )
        XCTAssertEqual(
            OrderEndpoint.keepWaiting(.keepWaiting, orderId: 501).request.path,
            "/api/orders/501/keep-waiting"
        )
        XCTAssertEqual(
            OrderEndpoint.keepWaiting(.keepRematching, orderId: 502).request.method,
            .put
        )
        XCTAssertEqual(
            OrderEndpoint.keepWaiting(.keepRematching, orderId: 502).request.path,
            "/api/orders/502/keep-rematching"
        )
    }

    /// 通话磨合四条里**只有 `view` 是 GET**，其余三条是 POST。
    func testIntroCallViewIsTheOnlyReadEndpoint() {
        XCTAssertEqual(OrderEndpoint.introCall(.view, orderId: 7).request.method, .get)
        XCTAssertEqual(
            OrderEndpoint.introCall(.view, orderId: 7).request.path,
            "/api/orders/7/intro-call"
        )
        XCTAssertEqual(OrderEndpoint.introCall(.decision, orderId: 7).request.method, .post)
        XCTAssertEqual(OrderEndpoint.introCall(.unreachable, orderId: 7).request.method, .post)
        XCTAssertEqual(OrderEndpoint.introCall(.notifyIncoming, orderId: 7).request.method, .post)
    }

    /// 订单片没有一条端点是免鉴权的（认证片那边的 `send-code` / `legal-links` 才是）。
    /// 写反了的后果是请求不带 JWT，后端 401，而客户端会当成「登录过期」把用户踢出去。
    func testEveryOrderEndpointRequiresAuth() {
        let endpoints: [OrderEndpoint] = [
            .create, .mine, .detail(orderId: 1), .cancel(orderId: 1), .respond(orderId: 1),
            .enRoute(orderId: 1), .arrived(orderId: 1), .startService(orderId: 1),
            .finish(orderId: 1), .review(orderId: 1), .reviews(orderId: 1),
            .statusLogs(orderId: 1), .startLiveShare(orderId: 1), .stopLiveShare(orderId: 1),
            .volunteerLocation, .dispatchSummary, .dispatchStatus,
            .keepWaiting(.keepWaiting, orderId: 1), .introCall(.view, orderId: 1),
        ]
        for endpoint in endpoints {
            XCTAssertTrue(endpoint.request.requiresAuth, "\(endpoint.request.path) 少带了 JWT")
        }
    }
}
