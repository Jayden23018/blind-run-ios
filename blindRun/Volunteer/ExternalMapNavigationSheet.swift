import SwiftUI

struct ExternalMapNavigationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: ExternalMapNavigationRequest

    private var providers: [ExternalMapNavigationProvider] {
        ExternalMapNavigationAvailability.availableProviders()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(providers) { provider in
                        Button {
                            ExternalMapNavigationLauncher.open(provider: provider, request: request)
                            dismiss()
                        } label: {
                            Label(provider.displayName, systemImage: provider.systemImageName)
                                .font(AppFonts.body().weight(.semibold))
                        }
                        .accessibilityLabel("使用\(provider.displayName)导航到出发地点")
                        .accessibilityHint("打开外部地图进行步行导航")
                    }
                } footer: {
                    Text("使用步行导航。")
                }
            }
            .navigationTitle("选择地图导航")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}
