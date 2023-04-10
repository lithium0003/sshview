//
//  EditServer.swift
//  sshtest
//
//  Created by rei8 on 2022/04/16.
//

import SwiftUI

extension UIApplication {
    func closeKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct EditServer: View {
    @EnvironmentObject var serverProfile: ServerProfile
    @EnvironmentObject var userProfile: UserProfile
    @EnvironmentObject var target: Targets

    var serverIdx: Int
    var duplicate = false
    
    @State private var idname = ""
    @State private var hostname = ""
    @State private var portstr = ""
    @State private var serverKey = ""
    @State private var proxyServer = UUID()
    @State private var connType = 0
    @State private var runCommand = ""
    @State private var portType = 0
    @State private var fixedPort = ""
    @State private var grepCommand = ""
    @State private var grepCommandType = 0

    @State private var showSheet = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    UIApplication.shared.closeKeyboard()
                }
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
                    HStack{
                        Text("User identity")
                        Picker("User identity", selection: $target.userId) {
                            Text("(select)")
                            ForEach(userProfile.userid) { item in
                                Text(item.title)
                            }
                        }
                        Text(" or ")
                        NavigationLink(value: Dest.addnewid) {
                            Image(systemName: "person.badge.plus")
                            Text("New")
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
                    if connType > 0  {
                        Button(action: {
                            showSheet = true
                        }, label: {
                            Text("Open detail")
                        })
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
                        guard userProfile.userid.first(where: { $0.id == target.userId}) != nil else {
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
                        var forwardPort = 0
                        if connType == 1 {
                            guard !runCommand.isEmpty else {
                                return
                            }
                            remoteCommand = runCommand
                        }
                        else if connType == 2 {
                            remoteCommand = runCommand
                            if portType == 0 {
                                guard let port = Int(fixedPort) else {
                                    return
                                }
                                forwardPort = port
                            }
                            else {
                                grepStr = grepCommand
                            }
                        }
                        if serverIdx >= 0 && !duplicate {
                            serverProfile.servers[serverIdx].title = idname
                            serverProfile.servers[serverIdx].remoteHost = hostname
                            serverProfile.servers[serverIdx].remotePort = port
                            serverProfile.servers[serverIdx].userIDtag = target.userId
                            serverProfile.servers[serverIdx].proxyServerID = proxy
                            serverProfile.servers[serverIdx].serverCommand = remoteCommand
                            serverProfile.servers[serverIdx].grepPortFoward = grepStr
                            serverProfile.servers[serverIdx].portFoward = forwardPort
                        }
                        else {
                            let newItem = ServerItem(title: idname, remoteHost: hostname, remotePort: port, userIDtag: target.userId, proxyServerID: proxy, serverCommand: remoteCommand, grepPortFoward: grepStr, portFoward: forwardPort)
                            serverProfile.servers.append(newItem)
                        }

                        _ = target.showTarget.popLast()
                    }) {
                        Text("Done").font(.title)
                    }
                    Spacer()
                    Button(role: .cancel, action: {
                        _ = target.showTarget.popLast()
                    }) {
                        Text("Cancel").font(.title)
                    }
                    Spacer()
                }
                .padding()

            }
            .padding()
            .onAppear() {
                if serverIdx >= 0 {
                    idname = serverProfile.servers[serverIdx].title
                    hostname = serverProfile.servers[serverIdx].remoteHost
                    portstr = String(serverProfile.servers[serverIdx].remotePort)
                    target.userId = serverProfile.servers[serverIdx].userIDtag
                    proxyServer = serverProfile.servers[serverIdx].proxyServerID ?? UUID()
                    serverKey = serverProfile.servers[serverIdx].serverKeyHash.map({ String(format: "%02x", $0) }).joined(separator: ":")
                    if let command = serverProfile.servers[serverIdx].serverCommand {
                        runCommand = command
                        if let grep = serverProfile.servers[serverIdx].grepPortFoward {
                            connType = 2
                            portType = 1
                            grepCommand = grep
                        }
                        else if serverProfile.servers[serverIdx].portFoward > 0 {
                            connType = 2
                            portType = 0
                            fixedPort = String(serverProfile.servers[serverIdx].portFoward)
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
        .sheet(isPresented: $showSheet) {
            Group {
                HStack {
                    Spacer()
                    Button(action: {
                        showSheet = false
                    }, label: {
                        Text("Done")
                    })
                }
                if connType == 1 {
                    Text("Command")
                        .font(.title)
                    Spacer()
                    VStack {
                        Text("Run commands on remote")
                        TextEditor(text: $runCommand)
                            .keyboardType(.asciiCapable)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                    }
                }
                else if connType == 2 {
                    Text("WebBrowser")
                        .font(.title)
                    Spacer()
                    VStack {
                        HStack {
                            Text("Open port on localhost")
                            Picker("Port Type", selection: $portType) {
                                Text("Fixed port").tag(0)
                                Text("Grep from output").tag(1)
                            }
                        }
                        if portType == 0 {
                            TextField("port", text: $fixedPort)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.numberPad)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        else if portType == 1 {
                            Picker("Grep text", selection: $grepCommandType) {
                                Text("User specified").tag(0)
                                Text("Tensorboard").tag(1)
                                Text("Jupyter notebook").tag(2)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: grepCommandType) { value in
                                if value == 1 {
                                    grepCommand = #"TensorBoard.*localhost:(\d+)"#
                                }
                                else if value == 2 {
                                    grepCommand = #"http://localhost:(\d+)/(\?token=[0-9a-f]+)"#
                                }
                            }
                            TextField("Grep regex string for output to find port", text: $grepCommand)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.asciiCapable)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                        }
                        Spacer()
                        Text("Run commands on remote")
                        TextEditor(text: $runCommand)
                            .keyboardType(.asciiCapable)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.gray, lineWidth: 1)
                            )
                    }
                }
            }
            .padding()
        }
    }
}

struct EditServer_Previews: PreviewProvider {
    static var previews: some View {
        EditServer(serverIdx: 0)
    }
}
