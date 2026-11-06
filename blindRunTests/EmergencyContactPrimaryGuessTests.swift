import XCTest
@testable import blindRun

/// #807 审查：列表没从服务端拿到时，空的 `contacts` 不能当成「一位都没有」——
/// 否则新增会带 `isPrimary: true`，把服务端原来的主联系人顶掉。
/// 单放一个文件：`EmergencyContactsViewModelTests.swift` 已到 SwiftLint 行数上限。
@MainActor
final class EmergencyContactPrimaryGuessTests: XCTestCase {
    func testEmptyLocalListIsNotTreatedAsNoContactsUntilLoaded() async {
        let appState = AppState(apiClient: ContactsAPIClientStub(contacts: []), tokenStore: ContactsInMemoryTokenStore())
        appState.userId = 7
        let viewModel = EmergencyContactsViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        XCTAssertFalse(viewModel.isKnownToHaveNoContacts, "还没加载过，不能断定一位都没有")

        await viewModel.load()

        XCTAssertTrue(viewModel.isKnownToHaveNoContacts, "服务端确认为空后，新增的这位才是主联系人")
    }
}
