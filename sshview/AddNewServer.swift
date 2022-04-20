//
//  AddNewServer.swift
//  sshtest
//
//  Created by rei8 on 2022/04/16.
//

import SwiftUI

struct AddNewServer: View {
    @EnvironmentObject var serverProfile: ServerProfile
    @EnvironmentObject var userProfile: UserProfile

    @State private var idname = ""
    @State private var hostname = ""
    @State private var portstr = ""
    @State private var userid = UUID()
    @State private var proxyServer = UUID()

    @Binding var isShowCurrentView: Bool
    @State private var isShowSubView = false
    
    var body: some View {
        VStack {
            Spacer()
            Group {
                TextField("Tag", text: $idname)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.default)
                TextField("HostName", text: $hostname)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                TextField("Port", text: $portstr)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
            Spacer()
            Group {
                Button(action: {
                    self.isShowSubView = true
                }) {
                    Text("New User Identity")
                }
                HStack{
                    Text("User Identity")
                    Picker("User Identity", selection: $userid) {
                        ForEach(userProfile.userid) { item in
                            Text(item.title)
                        }
                    }
                }
            }
            Spacer()
            HStack{
                Text("Proxy jump server")
                Picker("Proxy server", selection: $proxyServer) {
                    Text("none")
                    ForEach(serverProfile.servers) { item in
                        Text(item.title)
                    }
                }
            }
            Spacer()
            Button(action: {
                guard !idname.isEmpty else {
                    return
                }
                guard !hostname.isEmpty else {
                    return
                }
                guard !portstr.isEmpty, let port = Int(portstr) else {
                    return
                }
                guard userProfile.userid.first(where: { $0.id == userid}) != nil else {
                    return
                }
                var proxy: UUID?
                if serverProfile.servers.first(where: { $0.id == proxyServer }) == nil {
                    proxy = nil
                }
                else {
                    proxy = proxyServer
                }
                let newItem = ServerItem(title: idname, remoteHost: hostname, remotePort: port, userIDtag: userid, proxyServerID: proxy)
                serverProfile.servers.append(newItem)
                
                isShowCurrentView = false
            }) {
                Text("Done")
            }
            Spacer()

            NavigationLink(destination: AddNewId(newId: $userid, isShowSubView: $isShowSubView), isActive: $isShowSubView) {
                EmptyView()
            }
        }
        .padding()
        .onAppear() {
            userid = userProfile.userid.first?.id ?? UUID()
        }
    }
}

struct AddNewServer_Previews: PreviewProvider {
    @State static var isShow = false

    static var previews: some View {
        AddNewServer(isShowCurrentView: $isShow)
    }
}
