import XCTest
@testable import blindRun

/// 事后工单（`POST /api/support/tickets`）。
///
/// 这一屏唯一会**静默**出错的地方是校验：空正文提交成功，在屏幕上和正常提交长得一模一样
/// —— 用户以为说完了，客服收到一张空单。所以校验闸做在 `SupportTicketRequest` 的
/// 可失败构造上（视图里那个 `if` 谁都验不了），这里逐条钉住。
final class SupportTicketTests: XCTestCase {
    func testEmptyContentNeverBecomesATicket() {
        XCTAssertNil(SupportTicketRequest(category: .orderService, content: "", orderId: 1))
        XCTAssertNil(SupportTicketRequest(category: .orderService, content: "   \n\t ", orderId: 1))
    }

    /// 契约 `maxLength: 1000`。**客户端在提交前就拦**：这一屏多半是在路边写的，
    /// 打了一千多字再被后端退回来，那些字就没了。
    func testContentLengthIsCappedAtTheContractLimit() {
        let limit = SupportTicketRequest.maxContentLength
        XCTAssertEqual(limit, 1000)

        let atLimit = String(repeating: "问", count: limit)
        XCTAssertNotNil(SupportTicketRequest(category: .orderService, content: atLimit, orderId: nil))

        let overLimit = String(repeating: "问", count: limit + 1)
        XCTAssertNil(SupportTicketRequest(category: .orderService, content: overLimit, orderId: nil))
    }

    /// 首尾空白要去掉再发：用户按完回车再提交是常事，而后端那 1000 字的上限
    /// 不该被一串换行吃掉。
    func testContentIsTrimmedBeforeItIsSent() {
        let request = SupportTicketRequest(
            category: .orderService,
            content: "  跑者一直没出现\n",
            orderId: 42
        )
        XCTAssertEqual(request?.content, "跑者一直没出现")
        XCTAssertEqual(request?.orderId, 42)
        XCTAssertEqual(request?.category, .orderService)
    }

    /// 分类是**请求向的闭合枚举**，编码出来必须是契约里那五个字面量之一。
    /// 订单页那两个入口一律发 `ORDER_SERVICE` —— 分类是给客服分流用的，不是选择题。
    func testCategoryEncodesToTheContractValues() throws {
        let request = SupportTicketRequest(category: .orderService, content: "x", orderId: nil)
        let data = try JSONEncoder().encode(XCTUnwrap(request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["category"] as? String, "ORDER_SERVICE")
        XCTAssertEqual(json["content"] as? String, "x")
        // `orderId` 可空：契约写着「给了就必须是自己的订单，否则 404」。
        XCTAssertNil(json["orderId"])

        XCTAssertEqual(SupportTicketCategory.safety.rawValue, "SAFETY")
        XCTAssertEqual(SupportTicketCategory.account.rawValue, "ACCOUNT")
        XCTAssertEqual(SupportTicketCategory.appIssue.rawValue, "APP_ISSUE")
        XCTAssertEqual(SupportTicketCategory.other.rawValue, "OTHER")
    }

    /// 🔴 **工单不是求助。** 契约在端点 description 上逐字要求
    /// 「客户端文案不得把用户从 SOS 引到这里」。这一屏在用户写字之前就要说清时效，
    /// 并把真正紧急时该做的事写出来。
    func testCopyTellsThemThisIsNotAnEmergencyChannel() {
        XCTAssertTrue(SupportTicketCopy.notice.contains("不会立刻"))
        XCTAssertTrue(SupportTicketCopy.notice.contains("120"))
        XCTAssertTrue(SupportTicketCopy.notice.contains("110"))
        // 反向：不许把这里说成「求助」，那个词在本 App 里专指云端 SOS 链路。
        XCTAssertFalse(SupportTicketCopy.title.contains("求助"))
        XCTAssertFalse(SupportTicketCopy.notice.contains("一键求助"))
    }
}
