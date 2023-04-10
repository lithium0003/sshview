//
//  sshviewApp.swift
//  sshview
//
//  Created by rei8 on 2022/04/21.
//

import SwiftUI
import libssh

enum Dest: Hashable {
    case connect
    case user
    case editserver(Int, Bool)
    case addnewid
}

class Targets: ObservableObject {
    @Published var showTarget: [Dest] = []
    @Published var userId: UUID = UUID()
}

@main
struct sshviewApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ServerProfile())
                .environmentObject(UserProfile())
                .environmentObject(TabDataList())
                .environmentObject(SSHDaemon())
                .environmentObject(Targets())
        }
    }
}
