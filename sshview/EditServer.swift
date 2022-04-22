//
//  EditServer.swift
//  sshtest
//
//  Created by rei8 on 2022/04/16.
//

import SwiftUI

struct EditServer: View {
    @EnvironmentObject var serverProfile: ServerProfile
    @EnvironmentObject var userProfile: UserProfile

    var serverIdx: Int
    
    @State private var idname = ""
    @State private var hostname = ""
    @State private var portstr = ""
    @State private var serverKey = ""
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
            Group {
                Button(action: {
                    serverProfile.servers[serverIdx].serverKeyHash = []
                    serverKey = ""
                }) {
                    Text("Remove know server key")
                }
                .opacity(serverKey.isEmpty ? 0 : 1)
                Text(serverKey)
            }
            HStack {
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
                    var remoteCommand: String?
                    var grepStr: String?
                    if connType == 1 {
                        remoteCommand = runCommand
                    }
                    else if connType == 2 {
                        remoteCommand = runCommand
                        grepStr = grepCommand
                    }
                    serverProfile.servers[serverIdx].title = idname
                    serverProfile.servers[serverIdx].remoteHost = hostname
                    serverProfile.servers[serverIdx].remotePort = port
                    serverProfile.servers[serverIdx].userIDtag = userid
                    serverProfile.servers[serverIdx].proxyServerID = proxy
                    serverProfile.servers[serverIdx].serverCommand = remoteCommand
                    serverProfile.servers[serverIdx].grepPortFoward = grepStr

                    isShowCurrentView = false
                }) {
                    Text("Done")
                }
                Spacer()
                Button(role: .cancel, action: {
                    isShowCurrentView = false
                }) {
                    Text("Cancel")
                }
                Spacer()
            }
            .padding()

            NavigationLink(destination: AddNewId(newId: $userid, isShowSubView: $isShowSubView), isActive: $isShowSubView) {
                EmptyView()
            }
        }
        .padding()
        .onAppear() {
            idname = serverProfile.servers[serverIdx].title
            hostname = serverProfile.servers[serverIdx].remoteHost
            portstr = String(serverProfile.servers[serverIdx].remotePort)
            userid = serverProfile.servers[serverIdx].userIDtag
            proxyServer = serverProfile.servers[serverIdx].proxyServerID ?? UUID()
            serverKey = serverProfile.servers[serverIdx].serverKeyHash.map({ String(format: "%02x", $0) }).joined(separator: ":")
            if let command = serverProfile.servers[serverIdx].serverCommand {
                runCommand = command
                if let grep = serverProfile.servers[serverIdx].grepPortFoward {
                    connType = 2
                    grepCommand = grep
                }
                else {
                    connType = 1
                }
            }
            else {
                connType = 0
            }
        }
    }
}

struct EditServer_Previews: PreviewProvider {
    @State static var isShow = false
    
    static var previews: some View {
        EditServer(serverIdx: 0, isShowCurrentView: $isShow)
    }
}
