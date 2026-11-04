import Contacts
import ContactsUI
import SwiftUI
import UIKit

/// 从系统通讯录选一位联系人的一个手机号（#657 B-10）。
///
/// 用 `CNContactPickerViewController`：它在**进程外**运行，用户选中之前 App 拿不到任何通讯录数据，
/// 所以不需要通讯录权限，也不用写 `NSContactsUsageDescription`。App 最终只拿到用户选中的那一个人。
///
/// 🔴 不能把选择器直接当 sheet 的内容：放进 SwiftUI sheet 会先闪一页空白、随即自己关掉。
/// 这里挂一个看不见的 `UIViewController`，由它去 `present` 选择器。
struct ContactPhonePicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onPick: (ContactPhonePick) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.isHidden = true
        host.view.isAccessibilityElement = false
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.parent = self
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0")
        // 只有一个号码的人直接选中；有多个号码的人进详情页，让用户挑是哪一个。
        picker.predicateForSelectionOfContact = NSPredicate(format: "phoneNumbers.@count == 1")
        picker.predicateForSelectionOfProperty = NSPredicate(format: "key == 'phoneNumbers'")
        DispatchQueue.main.async {
            host.present(picker, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPhonePicker

        init(parent: ContactPhonePicker) {
            self.parent = parent
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let number = contact.phoneNumbers.first?.value.stringValue ?? ""
            finish(contact: contact, rawPhone: number)
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contactProperty: CNContactProperty) {
            let number = (contactProperty.value as? CNPhoneNumber)?.stringValue ?? ""
            finish(contact: contactProperty.contact, rawPhone: number)
        }

        private func finish(contact: CNContact, rawPhone: String) {
            parent.isPresented = false
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            parent.onPick(ContactPhonePick(name: name, rawPhone: rawPhone))
        }
    }
}

/// 选择器选中的结果。号码保留原样，清洗交给 `normalizedPhone`（纯函数，单测钉着）。
struct ContactPhonePick: Equatable {
    let name: String
    let rawPhone: String

    /// 通讯录里的号码常带 `+86`、空格、连字符、括号。只留数字，再去掉国家码。
    /// 结果不一定是合法手机号（座机、境外号），合法性由表单原有的校验去判。
    var normalizedPhone: String {
        Self.normalizedPhone(rawPhone)
    }

    static func normalizedPhone(_ raw: String) -> String {
        var digits = raw.filter(\.isASCIIDigit)
        if digits.hasPrefix("0086"), digits.count == 15 {
            digits.removeFirst(4)
        } else if digits.hasPrefix("86"), digits.count == 13 {
            digits.removeFirst(2)
        }
        return digits
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}
