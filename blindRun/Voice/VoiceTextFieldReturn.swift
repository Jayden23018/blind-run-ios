import Foundation

/// 语音输入框里「回车」的处理（下单输入框大字号截断，见 `VoiceTextField`）。
///
/// 单行框改成 `TextField(…, axis: .vertical)` 才能在大字号下折行而不是截掉文字，
/// 可那样回车默认**插入换行**、不再触发 `onSubmit`。这里把单行框收到的换行拦下来：去掉换行，
/// 是键盘打的就当一次「回车提交」（原来的行为），是语音填进来的就只去掉换行、不提交 ——
/// 识别结果里带了换行不该替用户按下「搜索」。
/// 本来就该多行的框（`allowsLineBreaks`，例如路线备注）原样保留换行。
enum VoiceTextFieldReturn {
    struct Result: Equatable {
        let text: String
        let submitted: Bool
    }

    static func apply(to text: String, allowsLineBreaks: Bool, isTyping: Bool) -> Result {
        guard !allowsLineBreaks, text.contains(where: \.isNewline) else {
            return Result(text: text, submitted: false)
        }
        return Result(text: text.filter { !$0.isNewline }, submitted: isTyping)
    }
}
