import SwiftUI

extension View {
    /// 导航栏标题显示一份、读屏念另一份。
    ///
    /// `navigationTitle` 给不了单独的朗读串：屏幕上的掩码名「陈*」会被 VoiceOver 念成「陈星号」。
    /// 这里用 principal 位置的 `Text` 盖住系统标题，屏幕上显示 `shown`。
    ///
    /// 🔴 `navigationTitle` 传的是**朗读串**，不是 `shown`：只给 principal 的 `Text` 挂 `accessibilityLabel`
    /// 真机不生效，导航栏元素念的是系统标题（iOS 27，#247）。下一页的返回按钮也靠它，念朗读串正合适。
    func spokenNavigationTitle(_ shown: String, spoken: String) -> some View {
        navigationTitle(spoken)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(shown)
                        .font(.headline)
                        .lineLimit(1)
                        .accessibilityLabel(spoken)
                        .accessibilityAddTraits(.isHeader)
                }
            }
    }
}
