import XCTest

extension blindRunUITests {
    // MARK: - 视力卡：先单独同意，再一题一屏（#812）

    /// 视力卡第一屏是单独同意页；同意后进第 1 题「视力状况」：没选时「继续」不可用，选了才可用；
    /// 第 2 题「是否使用导盲犬」每个选项可点高度 ≥ 64pt，选中项带「已选中」；点「完成」后弹层关掉，
    /// 卡片读屏值以「已保存：」开头。
    ///
    /// 64pt 写在选项按钮的标签**内部**（挪到外面真机只剩文字高度，记忆 `button-frame-outside-label-does-not-grow-hit-area`）。
    @MainActor
    func testBlindProfileVisionCardAsksConsentThenOneQuestionPerScreen() throws {
        let app = launchBlindContactsApp()
        openBlindAccount(app)
        tapNavigationRow(app, labelBeginsWith: "个人资料")

        let card = app.descendants(matching: .any)["blindProfileCard_vision"].firstMatch
        XCTAssertTrue(scrollUntilExists(card, app: app), "资料页没有「视力状况与导盲犬」卡")
        XCTAssertTrue(scrollElementIntoView(card, app: app), "视力卡滚不出屏幕底部")
        tapWhenHittableOrByCoordinate(card, app: app)

        let agree = app.buttons["blindProfileVisionConsentAgree"].firstMatch
        XCTAssertTrue(agree.waitForExistence(timeout: 8), "视力卡第一屏不是同意页")
        XCTAssertTrue(app.buttons["blindProfileVisionConsentDecline"].firstMatch.exists, "同意页没有「不填这一项」")
        tapWhenHittableOrByCoordinate(agree, app: app)

        let title = app.descendants(matching: .any)["blindProfileFlowQuestionTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8), "同意后没进第 1 题")
        XCTAssertEqual(title.label, "第 1 题，共 2 题，视力状况")
        let advance = app.buttons["blindProfileFlowContinue"].firstMatch
        XCTAssertFalse(advance.isEnabled, "没选时「继续」应不可用")
        let lowVision = app.buttons["blindProfileOption_visionLevel_1"].firstMatch
        tapWhenHittableOrByCoordinate(lowVision, app: app)
        XCTAssertTrue(lowVision.isSelected, "选中后读屏没有「已选中」")
        XCTAssertTrue(advance.isEnabled, "选了之后「继续」仍不可用")
        tapWhenHittableOrByCoordinate(advance, app: app)

        XCTAssertTrue(waitForLabel(title, equals: "第 2 题，共 2 题，是否使用导盲犬", timeout: 5), "没进第 2 题：\(title.label)")
        for offset in 0..<3 { // 有 / 没有 / 不说
            let option = app.buttons["blindProfileOption_guideDog_\(offset)"].firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5))
            // 63.5 而不是 64：真机量出 63.99999999999994（浮点噪声），口径同 `AccessibilityAuditTests` 求助按钮那几条。
            XCTAssertGreaterThanOrEqual(option.frame.height, 63.5, "第 \(offset) 项可点高度不足 64pt：\(option.frame)")
        }
        tapWhenHittableOrByCoordinate(app.buttons["blindProfileOption_guideDog_0"].firstMatch, app: app)
        tapWhenHittableOrByCoordinate(advance, app: app)

        XCTAssertTrue(waitForElementToDisappear(title, timeout: 10), "点「完成」后弹层没关")
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue((card.value as? String ?? "").hasPrefix("已保存："), "卡片没念「已保存」：\(String(describing: card.value))")
    }

    /// 等元素的读屏标签变成指定值（换题后同一个 identifier 的标签会变）。
    @MainActor
    private func waitForLabel(_ element: XCUIElement, equals expected: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - 改昵称（#750；#812 起入口是头像下的「修改昵称」）

    /// 清空昵称按「保存」：留在编辑页、念出并上屏原因，退回资料页仍是旧昵称（没有半截保存）。
    /// 改成新昵称再保存：回到资料页，「修改昵称」的读屏值和头像下的名字都换成新昵称。
    @MainActor
    func testBlindProfileNicknameEditRejectsEmptyAndSavesNewName() throws {
        let app = launchBlindContactsApp()
        openBlindAccount(app)
        tapNavigationRow(app, labelBeginsWith: "个人资料")

        let row = app.descendants(matching: .any)["blindProfileNicknameRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "资料页没有「修改昵称」")
        XCTAssertEqual(row.value as? String, "测试盲人")
        tapWhenHittableOrByCoordinate(row, app: app)

        let field = app.textFields["昵称，必填"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8), "没进昵称编辑页")
        tapWhenHittableOrByCoordinate(field, app: app)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "测试盲人".count))
        let save = app.buttons["blindProfileTextEditSave"].firstMatch
        tapWhenHittableOrByCoordinate(save, app: app)
        let error = app.descendants(matching: .any)["blindProfileSaveError"].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5), "空昵称没有上屏原因")
        XCTAssertEqual(error.label, "请填写昵称，2 到 50 个字。")
        XCTAssertTrue(app.navigationBars["昵称"].exists, "校验没过却离开了编辑页")

        app.navigationBars["昵称"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertEqual(row.value as? String, "测试盲人", "没存上的空昵称不能留在资料里")

        tapWhenHittableOrByCoordinate(row, app: app)
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        replaceText(in: field, with: "新昵称", app: app)
        tapWhenHittableOrByCoordinate(save, app: app)
        XCTAssertTrue(app.navigationBars["个人资料"].waitForExistence(timeout: 10), "存上之后没回到资料页")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "新昵称")
        XCTAssertTrue(app.staticTexts["新昵称"].firstMatch.exists, "头像下的名字没跟着换")
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
