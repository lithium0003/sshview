//
//  LocalWevView.swift
//  sshtest
//
//  Created by rei8 on 2022/04/16.
//

import SwiftUI

struct LocalWebView: View {
    @State var url: String
    @State private var action: WebViewTest.Action = .none
    @State var canGoBack = false
    @State var canGoForward = false

    var body: some View {
        VStack{
            WebViewTest(url: url, action: $action, canGoBack: $canGoBack, canGoForward: $canGoForward)
            WebToolBarView(action: $action, canGoBack: $canGoBack, canGoForward: $canGoForward)
            Spacer()
        }
        .padding()
    }
}

struct LocalWebView_Previews: PreviewProvider {
    static var previews: some View {
        LocalWebView(url: "")
    }
}
