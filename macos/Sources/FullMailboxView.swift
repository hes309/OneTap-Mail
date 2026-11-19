import SwiftUI
import WebKit
import AppKit

struct FullMailboxView: View {
    @EnvironmentObject private var store: AppStore
    @State private var reloadToken = UUID()
    @State private var browserStatus = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            if let url = store.webmailURL {
                WebMailView(url: url, reloadToken: reloadToken, status: $browserStatus)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Palette.softBorder, lineWidth: 1)
                    )
            } else {
                noWebmailView
            }
        }
        .background(AppBackground())
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                store.showsFullMailbox = false
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("一键邮")
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(Palette.secondary)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(Capsule().fill(Color.white.opacity(0.85)))
                .overlay(Capsule().stroke(Palette.softBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("返回一键邮")

            ZStack {
                Circle().fill(Palette.blueSoft)
                Image(systemName: "envelope.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.blue)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text("完整邮箱")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.ink)
                Text(store.config.provider.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Palette.tertiary)
            }

            Spacer()

            if !browserStatus.isEmpty {
                Text(browserStatus)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 330, alignment: .trailing)
            }

            Button {
                reloadToken = UUID()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("刷新")

            if let url = store.webmailURL {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Image(systemName: "safari")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondary)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .help("在默认浏览器中打开")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 12)
    }

    private var noWebmailView: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Palette.tertiary)
            Text("当前邮箱没有网页版地址")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.ink)
            Text("请在邮箱设置中选择服务商，或使用浏览器打开邮箱。")
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.secondary)
            Button("打开邮箱设置") {
                store.showsFullMailbox = false
                store.showSettings = true
            }
            .buttonStyle(SecondaryButtonStyle(compact: false))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WebMailView: NSViewRepresentable {
    let url: URL
    let reloadToken: UUID
    @Binding var status: String

    func makeCoordinator() -> Coordinator {
        Coordinator(status: $status)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        context.coordinator.lastURL = url
        context.coordinator.lastReload = reloadToken
        webView.load(URLRequest(url: url))
        status = "正在加载邮箱…"
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastURL != url || context.coordinator.lastReload != reloadToken {
            context.coordinator.lastURL = url
            context.coordinator.lastReload = reloadToken
            webView.load(URLRequest(url: url))
            status = "正在重新加载邮箱…"
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        @Binding var status: String
        var lastURL: URL?
        var lastReload: UUID?
        private var lastDestination: URL?

        init(status: Binding<String>) {
            _status = status
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            status = "正在加载邮箱…"
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            status = ""
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            status = "加载失败：\(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            status = "加载失败：\(error.localizedDescription)"
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.targetFrame == nil,
               let target = navigationAction.request.url {
                NSWorkspace.shared.open(target)
                decisionHandler(.cancel)
                return
            }
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if let http = navigationResponse.response as? HTTPURLResponse,
               let disposition = http.value(forHTTPHeaderField: "Content-Disposition"),
               disposition.lowercased().contains("attachment") {
                decisionHandler(.download)
                return
            }
            decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
            }
            return nil
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String
        ) async -> URL? {
            let manager = FileManager.default
            let downloads = manager.urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? manager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
            try? manager.createDirectory(at: downloads, withIntermediateDirectories: true)

            let rawName = URL(fileURLWithPath: suggestedFilename).lastPathComponent
            let name = rawName.isEmpty ? "一键邮下载文件" : rawName
            var destination = downloads.appendingPathComponent(name)
            let ext = destination.pathExtension
            let base = destination.deletingPathExtension().lastPathComponent
            var index = 1
            while manager.fileExists(atPath: destination.path) {
                let numbered = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
                destination = downloads.appendingPathComponent(numbered)
                index += 1
            }

            lastDestination = destination
            status = "正在下载：\(destination.lastPathComponent)"
            return destination
        }

        func downloadDidFinish(_ download: WKDownload) {
            status = "已保存到下载文件夹：\(lastDestination?.lastPathComponent ?? "文件")"
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            status = "下载失败：\(error.localizedDescription)"
        }
    }
}
