import SwiftUI
import AppKit

@main
struct OneClickMailApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore.shared

    var body: some Scene {
        Window("一键邮", id: "main") {
            RootView()
                .environmentObject(store)
                .frame(
                    minWidth: 820, idealWidth: 900,
                    maxWidth: .infinity,
                    minHeight: 640, idealHeight: 840,
                    maxHeight: .infinity
                )
                .background(WindowConfigurator())
        }
        .defaultSize(width: 900, height: 840)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("选择文件…") {
                    store.chooseFiles()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("清空文件") {
                    store.clearFiles()
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
                .disabled(store.files.isEmpty)
            }

            CommandGroup(replacing: .appInfo) {
                Button("关于 一键邮") {
                    store.showAbout = true
                }
            }

            CommandGroup(after: .appInfo) {
                Button("邮箱设置…") {
                    store.showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(store.needsSetup)
            }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showQuickActionPrompt = false

    var body: some View {
        ZStack {
            AppBackground()

            if store.needsSetup {
                SetupView()
                    .transition(.opacity)
            } else if store.showsFullMailbox {
                FullMailboxView()
                    .transition(.opacity)
            } else {
                MainView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.22), value: store.needsSetup)
        .animation(.easeInOut(duration: 0.18), value: store.showsFullMailbox)
        .sheet(isPresented: $store.showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showQuickActionPrompt) {
            QuickActionPromptView()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.showAbout) {
            AboutView()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if store.shouldOfferQuickActionPrompt {
                    showQuickActionPrompt = true
                }
            }
        }
    }
}
