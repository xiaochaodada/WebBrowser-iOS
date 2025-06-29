//
//  ContentView.swift
//  webBrowser
//
//  Created by 超大大 on 2025/6/18.
//

import SwiftUI
@preconcurrency import WebKit
import Photos
import UniformTypeIdentifiers

// MARK: - Constants
struct WebViewConfig {
    static let showBottomToolbar = false
    static let isLoading = true
    static let debug = false
    static let customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static let openUrl = "https://juejin.cn/"

}

// MARK: - WebError
enum WebError: LocalizedError, Equatable {
    case networkError(String)
    case webKitError(String)
    case unknownError(String)

    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return message
        case .webKitError(let message):
            return message
        case .unknownError(let message):
            return message
        }
    }

    static func == (lhs: WebError, rhs: WebError) -> Bool {
        switch (lhs, rhs) {
        case (.networkError(let lhsMessage), .networkError(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.webKitError(let lhsMessage), .webKitError(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.unknownError(let lhsMessage), .unknownError(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}

// MARK: - WebViewModel
@MainActor
class WebViewModel: NSObject, ObservableObject {
    @Published var progress: Double = 0
    @Published var isLoading: Bool = false
    @Published var error: WebError?
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    private var webView: WKWebView?
    private var lastRequestedURL: URL?

    var currentURL: URL? {
        webView?.url
    }

    // 默认URL
    let defaultURL = URL(string:WebViewConfig.openUrl)!
    
    override init() {
        super.init()
    }
    
    // 配置WKWebView
    func configureWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
       
        configuration.userContentController.add(self, name: "locationChange")
        configuration.userContentController.add(self, name: "metaRefresh")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        if !WebViewConfig.customUserAgent.isEmpty {
            webView.customUserAgent = WebViewConfig.customUserAgent
        }
       

        // 观察加载进度
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack), options: .new, context: nil)
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward), options: .new, context: nil)
        
        // debug script
        if WebViewConfig.debug, let debugScript = WebView.loadJSFile(named: "vConsole") {
            let fullScript = debugScript + "\nvar vConsole = new window.VConsole();"
            let userScript = WKUserScript(
                source: fullScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(userScript)
        }
        // load custom script
        if let customScript = WebView.loadJSFile(named: "custom") {
            let userScript = WKUserScript(
                source: customScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            webView.configuration.userContentController.addUserScript(userScript)
        }

        self.webView = webView
        return webView
    }
    
    // 重新加载
    func reload() {
        if let url = webView?.url ?? lastRequestedURL {
            lastRequestedURL = url
            webView?.load(URLRequest(url: url))
        } else {
            webView?.load(URLRequest(url: defaultURL))
        }
    }
    
    // 返回上一页
    func goBack() {
        webView?.goBack()
    }
    
    // 前进
    func goForward() {
        webView?.goForward()
    }
    
    // KVO观察者
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        DispatchQueue.main.async {
            if keyPath == #keyPath(WKWebView.estimatedProgress) {
                self.progress = self.webView?.estimatedProgress ?? 0
                self.isLoading = self.progress < 1.0
            } else if keyPath == #keyPath(WKWebView.canGoBack) {
                self.canGoBack = self.webView?.canGoBack ?? false
            } else if keyPath == #keyPath(WKWebView.canGoForward) {
                self.canGoForward = self.webView?.canGoForward ?? false
            }
        }
    }
    
    deinit {
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoBack))
        webView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.canGoForward))
    }
}

// MARK: - URL Handling
extension WebViewModel {
    private enum URLScheme: String {
        case http = "http"
        case https = "https"
        case weixin = "weixin"
        case alipay = "alipay"
        case mailto = "mailto"
        case tel = "tel"
        case itmsApps = "itms-apps"
        case itmsAppss = "itms-appss"
        
        static var supportedSchemes: [String] {
            return [weixin.rawValue, alipay.rawValue, mailto.rawValue, tel.rawValue, itmsApps.rawValue, itmsAppss.rawValue]
        }
        
        static var webSchemes: [String] {
            return [http.rawValue, https.rawValue]
        }
    }
    
    private func handleURL(_ url: URL, completion: @escaping (Bool) -> Void) {
        let scheme = url.scheme?.lowercased() ?? ""
        
        // 处理 Web 链接
        if URLScheme.webSchemes.contains(scheme) {
            completion(true)
            return
        }
        
        // 处理支持的 scheme
        if URLScheme.supportedSchemes.contains(scheme) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:]) { success in
                    print("Open \(url.absoluteString) success: \(success)")
                    completion(false)
                }
            } else {
                print("Cannot open URL: \(url.absoluteString)")
                completion(false)
            }
            return
        }
        
        // 其他 scheme
        print("Unsupported scheme: \(scheme) for URL: \(url.absoluteString)")
        completion(false)
    }
}

// MARK: - WKNavigationDelegate
extension WebViewModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        error = nil
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error, url: webView.url)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error, url: webView.url)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
              decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        
        print("Navigation to URL: \(url.absoluteString), scheme: \(url.scheme?.lowercased() ?? "unknown")")
        
        handleURL(url) { shouldAllow in
            decisionHandler(shouldAllow ? .allow : .cancel)
        }
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        if let url = webView.url {
            print("Server redirect to URL: \(url.absoluteString)")
            
            handleURL(url) { shouldAllow in
                if !shouldAllow {
                    webView.stopLoading()
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let url = navigationResponse.response.url {
            print("Navigation response for URL: \(url.absoluteString)")
            print("Response MIME type: \(navigationResponse.response.mimeType ?? "unknown")")
            
            handleURL(url) { shouldAllow in
                decisionHandler(shouldAllow ? .allow : .cancel)
            }
        } else {
            decisionHandler(.allow)
        }
    }
    
    private func handleNavigationError(_ error: Error, url: URL?) {
        if let url = url {
            print("Failed URL: \(url.absoluteString)")
            lastRequestedURL = url
        }
        
        let nsError = error as NSError
        var errorMessage = ""
        
        switch nsError.domain {
        case NSURLErrorDomain:
            switch nsError.code {
            case NSURLErrorCancelled:
                errorMessage = "加载取消"
                return
            case NSURLErrorTimedOut:
                errorMessage = "请求超时"
            case NSURLErrorCannotFindHost:
                errorMessage = "找不到主机"
            case NSURLErrorNotConnectedToInternet:
                errorMessage = "无网络连接"
            case NSURLErrorNetworkConnectionLost:
                errorMessage = "网络连接中断"
            case NSURLErrorCannotConnectToHost:
                errorMessage = "无法连接到服务器"
            default:
                errorMessage = "其他网络错误: \(nsError.code)"
            }
            self.error = .networkError(errorMessage)
        case "WebKitErrorDomain":
            switch nsError.code {
            case 102:
                errorMessage = "帧加载被中断"
                return
            default:
                errorMessage = "其他 WebKit 错误: \(nsError.code)"
            }
            self.error = .webKitError(errorMessage)
        default:
            errorMessage = "未知错误域: \(nsError.domain), code: \(nsError.code)"
            self.error = .unknownError(errorMessage)
        }
        
        print(errorMessage)
        
        // 只有非取消错误才显示给用户
        if nsError.domain != NSURLErrorDomain || nsError.code != NSURLErrorCancelled {
            isLoading = false
        }
    }
}

// MARK: - WKUIDelegate
extension WebViewModel: WKUIDelegate {
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        // 处理JavaScript alert
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler()
        })
        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
    }
    
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        // 处理JavaScript confirm
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completionHandler(false)
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(true)
        })
        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
    }
    
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        // 处理JavaScript prompt
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = defaultText
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            completionHandler(nil)
        })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        UIApplication.shared.windows.first?.rootViewController?.present(alert, animated: true)
    }
}

// MARK: - WKScriptMessageHandler
extension WebViewModel: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "locationChange":
            if let urlString = message.body as? String,
               let url = URL(string: urlString) {
                let scheme = url.scheme?.lowercased() ?? ""
                print("JavaScript location change to: \(urlString)")
                if !scheme.hasPrefix("http") {
                    print("Blocked non-HTTP(S) JavaScript location change to: \(urlString)")
                    webView?.stopLoading()
                }
            }
        case "metaRefresh":
            if let urlString = message.body as? String,
               let url = URL(string: urlString) {
                let scheme = url.scheme?.lowercased() ?? ""
                print("Meta refresh to: \(urlString)")
                if !scheme.hasPrefix("http") {
                    print("Blocked non-HTTP(S) meta refresh to: \(urlString)")
                    webView?.stopLoading()
                }
            }
        default:
            break
        }
    }
}

// MARK: - WebView
struct WebView: UIViewRepresentable {
    @ObservedObject var webViewModel: WebViewModel
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = webViewModel.configureWebView()
        webView.load(URLRequest(url: webViewModel.defaultURL))
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // 更新视图（如果需要）
    }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var webViewModel = WebViewModel()
    @State private var showError = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 进度条
                if WebViewConfig.isLoading {
                    ProgressView(value: webViewModel.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 2)
                }
                
                // WebView
                WebView(webViewModel: webViewModel)
                    .overlay(
                        // 错误视图
                        Group {
                            if showError {
                                WebErrorView(
                                    message: errorMessage,
                                    retryAction: {
                                        showError = false
                                        webViewModel.reload()
                                    }
                                )
                            }
                        }
                    )
                
                // 底部工具栏
                if WebViewConfig.showBottomToolbar {
                    HStack(spacing: 20) {
                        Button(action: {
                            webViewModel.goBack()
                        }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(webViewModel.canGoBack ? .blue : .gray)
                        }
                        .disabled(!webViewModel.canGoBack)
                        
                        Button(action: {
                            webViewModel.goForward()
                        }) {
                            Image(systemName: "chevron.right")
                                .foregroundColor(webViewModel.canGoForward ? .blue : .gray)
                        }
                        .disabled(!webViewModel.canGoForward)
                        
                        Spacer()
                        
                        Button(action: {
                            webViewModel.reload()
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .shadow(radius: 2)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: webViewModel.error) { newError in
            if let error = newError {
                showError = true
                errorMessage = error.localizedDescription
            } else {
                showError = false
                errorMessage = ""
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

extension WebView {
    static func loadJSFile(named filename: String) -> String? {
        guard let path = Bundle.main.path(forResource: filename, ofType: "js") else {
            print("Could not find \(filename).js in bundle")
            return nil
        }
        
        do {
            let jsString = try String(contentsOfFile: path, encoding: .utf8)
            return jsString
        } catch {
            print("Error loading \(filename).js: \(error)")
            return nil
        }
    }
}
