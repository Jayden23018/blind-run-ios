import XCTest
@testable import blindRun

/// #746：列表页「从通讯录添加」选完直接进预填表单，关系改成预设选择。
/// 被测的静态方法挂在视图与 ViewModel 上，都隔离在 MainActor。
@MainActor
final class EmergencyContactPickAndRelationshipTests: XCTestCase {
    // MARK: 关系预设

    func testStoredPresetValueIsCheckedAsThatPreset() {
        XCTAssertEqual(EmergencyContactRelationship.selection(for: "家人"), .preset("家人"))
        XCTAssertEqual(EmergencyContactRelationship.selection(for: " 朋友 "), .preset("朋友"), "首尾空白不该让预设变成自定义")
    }

    func testStoredNonPresetValueIsKeptAsCustom() {
        XCTAssertEqual(EmergencyContactRelationship.selection(for: "干妈"), .custom("干妈"))
    }

    func testBlankStoredValueMeansNoRelationship() {
        XCTAssertEqual(EmergencyContactRelationship.selection(for: "   "), .none)
        XCTAssertEqual(EmergencyContactRelationship.displayValue(for: ""), "未填写")
    }

    /// Mock 种子联系人的关系是「家人」：它不在预设里的话，老数据全显示成自定义。
    func testMockSeedRelationshipIsAPreset() {
        XCTAssertTrue(EmergencyContactRelationship.presets.contains("家人"))
    }

    func testEveryPresetFitsTheBackendLengthLimit() {
        for preset in EmergencyContactRelationship.presets {
            XCTAssertLessThanOrEqual(preset.count, EmergencyContactRules.maxRelationshipLength, preset)
            XCTAssertNil(
                EmergencyContactsViewModel.validationMessage(name: "张三", phone: "13800138000", relationship: preset),
                "预设「\(preset)」保存时不该被校验拦下"
            )
        }
    }

    // MARK: 选中联系人 → 表单的值

    func testPickedMobileFillsNormalizedPhoneAndSpeaksOnlyTheLastFourDigits() {
        let picked = EmergencyContactFormView.pickedFields(
            ContactPhonePick(name: " 王五 ", rawPhone: "+86 138-0013-8000")
        )
        XCTAssertEqual(picked.name, "王五")
        XCTAssertEqual(picked.phone, "13800138000")
        XCTAssertTrue(picked.isValidPhone)
        XCTAssertTrue(picked.notice.contains("尾号 8000"), picked.notice)
        XCTAssertFalse(picked.notice.contains("13800138000"), "外放会被周围的人听到，不能念全号")
    }

    func testPickWithoutNameKeepsWhateverNameTheFormHad() {
        let picked = EmergencyContactFormView.pickedFields(ContactPhonePick(name: "  ", rawPhone: "13800138000"))
        XCTAssertNil(picked.name)
        XCTAssertTrue(picked.notice.hasPrefix("已选择这位联系人"), picked.notice)
    }

    func testPickedLandlineIsFilledButFlaggedInvalid() {
        let picked = EmergencyContactFormView.pickedFields(ContactPhonePick(name: "公司", rawPhone: "0571-8888-6666"))
        XCTAssertFalse(picked.isValidPhone)
        XCTAssertEqual(picked.phone, "05718888666", "照填并截到 11 位，让用户看得到再改")
        XCTAssertTrue(picked.notice.contains("不是 11 位手机号"), picked.notice)
    }

    // MARK: 编辑目标

    func testPickedTargetOpensAnAddFormCarryingThePick() {
        let pick = ContactPhonePick(name: "王五", rawPhone: "13800138000")
        let target = EmergencyContactEditTarget.picked(pick)
        XCTAssertNil(target.contact, "选中的人还没保存，表单应是新增态")
        XCTAssertEqual(target.pick, pick)
        XCTAssertNotEqual(target.id, EmergencyContactEditTarget.new.id, "两种新增共用一个 id 时，sheet 不会换内容")
        XCTAssertNil(EmergencyContactEditTarget.new.pick)
    }
}
