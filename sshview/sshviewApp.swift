//
//  sshviewApp.swift
//  sshview
//
//  Created by rei8 on 2022/04/21.
//

import SwiftUI
import libssh

@main
struct sshviewApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ServerProfile())
                .environmentObject(UserProfile())
                .environmentObject(TabDataList())
                .environmentObject(SSHDaemon())
        }
    }
}
