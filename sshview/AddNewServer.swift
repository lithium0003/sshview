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
    @State private var connType = 0
    @State private var runCommand = ""
    @State private var grepCommand = ""

    @Binding var isShowCurrentView: Bool
    @State private var isShowSubView = false
    
    var body: some View {
        VStack {
            Group {
                Spacer()
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
                Spacer()
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
            Group {
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
            }
            Group {
                Text("Connection type")
                Picker("Connection Type", selection: $connType) {
                    Text("Terminal").tag(0)
                    Text("Command").tag(1)
                    Text("WebBrowser").tag(2)
                }
                .pickerStyle(.segmented)
                if connType == 1 {
                    ZStack {
                        if runCommand.isEmpty {
                            Text("Run commands on remote")
                                .padding()
                        }
                        TextEditor(text: $runCommand)
                            .keyboardType(.asciiCapable)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .opacity(runCommand.isEmpty ? 0.25 : 1)
                            .padding()

                    }
                }
                else if connType == 2 {
                    TextField("Grep regex string for output to find port", text: $grepCommand)
                    ZStack {
                        if runCommand.isEmpty {
                            Text("Run commands on remote")
                                .padding()
                        }
                        TextEditor(text: $runCommand)
                            .keyboardType(.asciiCapable)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .opacity(runCommand.isEmpty ? 0.25 : 1)
                            .padding()

                    }
                }
                Spacer()
            }
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
                var remoteCommand: String?
                var grepStr: String?
                if connType == 1 {
                    remoteCommand = runCommand
                }
                else if connType == 2 {
                    remoteCommand = runCommand
                    grepStr = grepCommand
                }
                let newItem = ServerItem(title: idname, remoteHost: hostname, remotePort: port, userIDtag: userid, proxyServerID: proxy, serverCommand: remoteCommand, grepPortFoward: grepStr)
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
