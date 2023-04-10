//
//  MainView.swift
//  sshtest
//
//  Created by rei8 on 2022/04/16.
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject var serverProfile: ServerProfile
    @EnvironmentObject var userProfile: UserProfile
    @EnvironmentObject var target: Targets
    
    var body: some View {
        NavigationStack(path: $target.showTarget) {
            List {
                Section("Connect") {
                    NavigationLink("Servers", value: Dest.connect)
                }
                Section("User") {
                    NavigationLink("User ID", value: Dest.user)
                }
                Section("Help") {
                    Link("Online Help", destination: URL(string: "https://lithium03.info/ios/sshview.en.html#help")!)
                }
            }
            .navigationTitle("SSH View")
            .navigationDestination(for: Dest.self) { dst in
                switch dst {
                case .connect:
                    ServerList()
                case .user:
                    UserIdList()
                case let .editserver(idx, dup):
                    EditServer(serverIdx: idx, duplicate: dup)
                case .addnewid:
                    AddNewId()
                }
            }
        }
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
