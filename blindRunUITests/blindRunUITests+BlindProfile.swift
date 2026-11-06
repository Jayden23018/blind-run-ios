import XCTest

extension blindRunUITests {
    // MARK: - 资料页导盲犬三选一（#472）

    /// 同意后导盲犬那一项可点高度 ≥ 64pt，读屏值念出当前选项（种子档案 `guideDog = NO` ⇒「没有」）。
    ///
    /// 守的是两件单测看不见的事：64pt 写在 `Menu` 标签**内部**（挪到外面真机只剩文字高度，
    /// 记忆 `button-frame-outside-label-does-not-grow-hit-area`），以及 `accessibilityValue` 还在。
    @MainActor
    func testBlindProfileGuideDogChoiceIsTallAndSpeaksTheCurrentValue() throws {
        let app = launchBlindContactsApp()
        openBlindAccount(app)
        tapNavigationRow(app, labelBeginsWith: "个人资料")

        let disclosure = app.buttons["blindProfileVisionConsentDisclosure"].firstMatch
        XCTAssertTrue(scrollUntilExists(disclosure, app: app), "资料页没有「填写视力状况」")
        XCTAssertTrue(scrollElementIntoView(disclosure, app: app), "「填写视力状况」滚不出底栏")
        tapWhenHittableOrByCoordinate(disclosure, app: app)

        let agree = app.buttons["blindVisionProfileConsentAgreeButton"].firstMatch
        XCTAssertTrue(agree.waitForExistence(timeout: 8), "同意页没弹出来")
        tapWhenHittableOrByCoordinate(agree, app: app)

        let menu = app.descendants(matching: .any)["blindProfileGuideDogMenu"].firstMatch
        XCTAssertTrue(scrollUntilExists(menu, app: app), "同意后没有导盲犬三选一")
        XCTAssertTrue(scrollElementIntoView(menu, app: app))
        // 63.5 而不是 64：真机量出 63.99999999999994（浮点噪声），口径同 `AccessibilityAuditTests` 求助按钮那几条。
        // 打回成外挂 frame 时只剩文字高度（约 34pt），这个余量不会放过它。
        XCTAssertGreaterThanOrEqual(menu.frame.height, 63.5, "可点高度不足 64pt：\(menu.frame)")
        XCTAssertEqual(menu.value as? String, "没有", "读屏没念当前选项")
    }

    // MARK: - 紧急联系人无障碍

    /// 列表行只播报掩码手机号，且朗读顺序为「概览 → 联系人 → 新增」。
    @MainActor
    func testContactRowAnnouncesMaskedPhoneInReadingOrder() throws {
        let app = launchBlindContactsApp()
        openContacts(app)

        let summary = app.staticTexts[Self.seededContactSummary].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 12))

        let row = app.buttons["张三，关系家人，电话139****9001，主联系人"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "行内容应合并成一条含掩码手机号的播报")
        XCTAssertFalse(
            app.staticTexts["13900139001"].firstMatch.exists,
            "列表不得展示或朗读完整手机号"
        )

        // 添加区两行：通讯录在前、手动在后（#746）。
        let pickButton = app.buttons["从通讯录添加紧急联系人"].firstMatch
        let addButton = app.buttons["手动输入新增紧急联系人"].firstMatch
        XCTAssertTrue(pickButton.exists, "添加区没有「从通讯录添加」")
        XCTAssertTrue(addButton.exists, "添加区没有「手动输入」")
        XCTAssertLessThan(summary.frame.minY, row.frame.minY)
        XCTAssertLessThan(row.frame.minY, pickButton.frame.minY)
        XCTAssertLessThan(pickButton.frame.minY, addButton.frame.minY)
    }

    /// 新增 → 编辑 → 删除的完整往返。
    @MainActor
    func testContactAddEditAndDeleteRoundTrip() throws {
        let app = launchBlindContactsApp()
        openContacts(app)
        waitForContactSummary(app, Self.seededContactSummary)

        addContact(app, name: "李四", phone: "13700137000", relationship: "朋友")
        waitForContactSummary(app, "共 2 位紧急联系人，最多 5 位。主联系人是张三。")
        XCTAssertTrue(
            app.buttons["李四，关系朋友，电话137****7000，非主联系人"].firstMatch.waitForExistence(timeout: 8),
            "新增后应回写重新拉取的整份列表"
        )

        openContactEditor(app, named: "李四")

        let phoneField = app.textFields["联系人手机号，必填，11 位"].firstMatch
        XCTAssertTrue(phoneField.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForTextFieldValue(phoneField, equals: "13700137000", timeout: 5),
            "后端返回明文，编辑时应明文回填"
        )
        replaceText(in: phoneField, with: "13611116666", app: app)
        // 关系在选择页里改（#746）。从选择页退回会再触发表单的 onAppear，曾把刚改的号码和关系重置回旧值。
        chooseContactRelationship(app, "同事")
        XCTAssertTrue(
            waitForTextFieldValue(phoneField, equals: "13611116666", timeout: 5),
            "从关系选择页回来后，改过的号码不能被重置"
        )
        tapWhenHittableOrByCoordinate(app.buttons["保存"].firstMatch, app: app)
        XCTAssertTrue(
            waitForElementToDisappear(app.navigationBars["编辑紧急联系人"], timeout: 15),
            "保存成功后编辑表单应自动关闭"
        )

        XCTAssertTrue(
            app.buttons["李四，关系同事，电话136****6666，非主联系人"].firstMatch.waitForExistence(timeout: 10),
            "号码和关系都应按编辑后的值保存"
        )

        deleteContact(app, named: "李四")
        waitForContactSummary(app, Self.seededContactSummary)
    }

    /// 设主联系人是原子的（旧主自动降级），且最后一位联系人不可删除。
    @MainActor
    func testSetPrimaryIsAtomicAndLastContactCannotBeDeleted() throws {
        let app = launchBlindContactsApp()
        openContacts(app)
        waitForContactSummary(app, Self.seededContactSummary)

        // 只剩一位时删除被本地守卫拦下，不发请求、不弹确认框。
        // 拦截必须自己弹出来：按钮在表单最下面，内联文字在它上方，大字号时已滚出屏幕（#606）。
        openContactEditor(app, named: "张三")
        let deleteOnlyContact = app.buttons["删除张三"].firstMatch
        XCTAssertTrue(deleteOnlyContact.waitForExistence(timeout: 8))
        scrollElementIntoView(deleteOnlyContact, app: app)
        tapWhenHittableOrByCoordinate(deleteOnlyContact, app: app)
        let blocked = app.alerts["紧急联系人提示"]
        XCTAssertTrue(blocked.waitForExistence(timeout: 8))
        XCTAssertTrue(blocked.staticTexts["至少需要保留 1 位紧急联系人，不能删除最后一位。"].exists)
        XCTAssertFalse(app.alerts["确认删除联系人"].exists, "被拦下的删除不应弹出确认框")
        blocked.buttons["知道了"].tap()
        XCTAssertTrue(waitForElementToDisappear(blocked, timeout: 8))
        // 编辑页是推进的一页（#807），返回 = 不保存。
        app.navigationBars["编辑紧急联系人"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(waitForElementToDisappear(app.navigationBars["编辑紧急联系人"], timeout: 8))

        addContact(app, name: "李四", phone: "13700137000", relationship: "朋友")
        XCTAssertTrue(
            app.buttons["李四，关系朋友，电话137****7000，非主联系人"].firstMatch.waitForExistence(timeout: 15)
        )

        openContactEditor(app, named: "李四")
        let setPrimary = app.buttons["把李四设为主联系人"].firstMatch
        XCTAssertTrue(setPrimary.waitForExistence(timeout: 8))
        scrollElementIntoView(setPrimary, app: app)
        tapWhenHittableOrByCoordinate(setPrimary, app: app)
        let primaryAlert = app.alerts["确认设为主联系人"]
        XCTAssertTrue(primaryAlert.waitForExistence(timeout: 8), "切换主联系人需要二次确认")
        primaryAlert.buttons["设为主联系人"].tap()
        XCTAssertTrue(waitForElementToDisappear(primaryAlert, timeout: 8), "确认后弹窗应关闭")

        waitForContactSummary(app, "共 2 位紧急联系人，最多 5 位。主联系人是李四。")
        XCTAssertTrue(
            app.buttons["张三，关系家人，电话139****9001，非主联系人"].firstMatch.waitForExistence(timeout: 8),
            "原主联系人必须同步降级，保持恰好一位主联系人"
        )
    }

    /// 达到 5 位上限后新增被禁用并说明原因。
    @MainActor
    func testContactUpperLimitBlocksTheSixthContact() throws {
        let app = launchBlindContactsApp()
        openContacts(app)
        waitForContactSummary(app, Self.seededContactSummary)

        for index in 2...5 {
            addContact(app, name: "联系人\(index)", phone: "1370013700\(index)", relationship: "朋友")
            waitForContactSummary(app, "共 \(index) 位紧急联系人，最多 5 位。主联系人是张三。")
        }

        let pickButton = app.buttons["从通讯录添加紧急联系人"].firstMatch
        let addButton = app.buttons["手动输入新增紧急联系人"].firstMatch
        scrollUntilExists(addButton, app: app)
        XCTAssertTrue(addButton.waitForExistence(timeout: 8))
        scrollElementIntoView(addButton, app: app)

        // 上限文案排在按钮下方，同样可能还没渲染
        let limitNotice = app.staticTexts["已保存 5 位紧急联系人，达到上限。如需新增，请先删除一位。"].firstMatch
        scrollUntilExists(limitNotice, app: app)
        XCTAssertTrue(limitNotice.waitForExistence(timeout: 8))
        XCTAssertFalse(addButton.isEnabled, "到达上限后「手动输入」必须禁用")
        XCTAssertFalse(pickButton.isEnabled, "到达上限后「从通讯录添加」必须禁用")
    }
}
