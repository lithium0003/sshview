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
    @State var isShowServer = false
    
    var body: some View {
        NavigationView {
            List {
                NavigationLink("Servers", destination: ServerList(isShowing: $isShowServer), isActive: $isShowServer)
                NavigationLink("User ID", destination: UserIdList())
            }
            .navigationTitle("SSH Client")
        }
        .navigationViewStyle(.stack)
    }
}

struct MainView_Previews: PreviewProvider {
    static var previews: some View {
        MainView()
    }
}
