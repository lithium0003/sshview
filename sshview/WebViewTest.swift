//
//  WebViewTest.swift
//  sshtest
//
//  Created by rei8 on 2022/04/14.
//

import SwiftUI
import WebKit

struct WebViewTest: UIViewRepresentable {
    private let webView = WKWebView()
    var url: String

    enum Action {
        case none
        case goBack
        case goForward
        case reload
    }
    @Binding var action: Action
    
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        if let newUrl = URL(string: url) {
            webView.load(URLRequest(url: newUrl))
        }
        return webView
    }

    func updateUIView(_ uiView: UIViewType, context: Context) {
        switch action {
        case .goBack:
            uiView.goBack()
        case .goForward:
            uiView.goForward()
        case .reload:
            uiView.reload()
        case .none:
            break
        }
        action = .none
    }
    
    func makeCoordinator() -> WebViewTest.Coordinator {
        let cood = Coordinator(parent: self)
        webView.navigationDelegate = cood
        webView.uiDelegate = cood
        return cood
    }
}

extension WebViewTest {
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let parent: WebViewTest

        init(parent: WebViewTest) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.canGoBack = webView.canGoBack
            parent.canGoForward = webView.canGoForward
            parent.action = .none
        }
        
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil || navigationAction.targetFrame?.isMainFrame == false {
                if let url = navigationAction.request.url?.absoluteString, !url.isEmpty {
                    print(url)
                    webView.load(navigationAction.request)
                }
            }
            return nil
        }
    }
}
