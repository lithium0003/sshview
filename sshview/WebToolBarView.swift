//
//  WebToolBarView.swift
//  sshtest
//
//  Created by rei8 on 2022/04/14.
//

import SwiftUI

struct WebToolBarView: View {
    @Binding var action: WebViewTest.Action
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool

    var body: some View {
        VStack() {
            HStack() {
                Button("Back") { action = .goBack }.disabled(!canGoBack)
                Button("Forward") { action = .goForward }.disabled(!canGoForward)
                Button("Reload") { action = .reload }
            }
        }
    }
}
