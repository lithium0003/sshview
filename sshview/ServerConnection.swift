//
//  ServerConnection.swift
//  sshtest
//
//  Created by rei8 on 2022/04/16.
//

import SwiftUI
import libssh

struct ServerConnection: View {
    var serverTag: UUID
    @EnvironmentObject var serverProfile: ServerProfile
    @EnvironmentObject var userProfile: UserProfile
    @EnvironmentObject var tabData: TabDataList
    @EnvironmentObject var sshDaemon: SSHDaemon

    @State var text: String = ""
    @State var session: ssh_session?
    @State var session_list: [ssh_session] = []
    @State var remoteHost = ""
    @State var remotePort = 0
    @State var isInit = false
    @State var timer: DispatchSourceTimer?
    @State var timer2: DispatchSourceTimer?
    @State var windowTitle: String = ""
    @State var screenWidth = 80
    @State var screenHeight = 24
    
    @State private var isShowing = false
    @StateObject var handler = stdHandlers()

    func connect() {
        guard let server = serverProfile.servers.first(where: { $0.id == serverTag }) else {
            removeTag()
            return
        }
        remoteHost = server.remoteHost
        remotePort = server.remotePort
        windowTitle = "\(remoteHost):\(remotePort)"
        session = connect(serverID: server.id)
        
        allcateConsole()
    }
    
    func allcateConsole() {
        guard let session = session else {
            return
        }
                
        DispatchQueue.main.async {
            handler.screeSizeChane = { newWidth, newHeight in
                sshDaemon.setNewsizeTerminal(session: session, terminalIdx: 0, newWidth: newWidth, newHeight: newHeight)
            }

            isShowing = true
        }
        timer = DispatchSource.makeTimerSource(flags: [], queue: .global())
        timer?.schedule(deadline: .now(), repeating: 1)
        timer?.setEventHandler {
            guard let stdInFcn = handler.stdInFcn else {
                return
            }
            guard let stdOutFcn = handler.stdOutFcn else {
                return
            }
            timer?.cancel()

            sshDaemon.createTerminal(session: session, stdinFnc: stdInFcn, stdoutFnc: stdOutFcn, stderrFnc: nil)
            
            timer2 = DispatchSource.makeTimerSource(flags: [], queue: .global())
            timer2?.schedule(deadline: .now()+5, repeating: 2)
            timer2?.setEventHandler {
                if sshDaemon.checkTerminal(session: session, terminalIdx: 0) {
                    return
                }
                timer2?.cancel()
                DispatchQueue.main.async {
                    handler.stdInFcn = nil
                    handler.stdOutFcn = nil
                    handler.screeSizeChane = nil
                }
                for session1 in session_list.reversed() {
                    sshDaemon.disconnect(session: session1)
                }
                DispatchQueue.main.async {
                    isShowing = false
                }
                DispatchQueue.main.async {
                    removeTag()
                }
            }
            timer2?.resume()
        }
        timer?.resume()
    }
    
    func connect(serverID: UUID) -> ssh_session? {
        guard let server = serverProfile.servers.first(where: { $0.id == serverID }) else {
            return nil
        }
        guard let userID = userProfile.userid.first(where: { $0.id == server.userIDtag }) else {
            return nil
        }
        if let proxy = server.proxyServerID {
            guard let proxySession = connect(serverID: proxy) else {
                return nil
            }

            let localPort = UInt16.random(in: 1024...UInt16.max)
            let portForward = LocalPortForward(localPort: localPort, remoteHost: server.remoteHost, remotePort: UInt16(server.remotePort))

            if sshDaemon.localPortFoward(session: proxySession, portForward: portForward) {
                var serverKeyHash = server.serverKeyHash
                let userIdentity = UserIdentity(userName: userID.userName, b64_prrvateKey: userID.b64_prrvateKey, passphrease: userID.passphrease)
                let newsession = sshDaemon.connect(remoteServer: "localhost", remotePort: Int(localPort), user_id: userIdentity, server_hashkey: &serverKeyHash, logger: { log in
                    DispatchQueue.main.async {
                        text += log + "\n"
                    }
                })
                guard let newsession = newsession else {
                    return nil
                }
                session_list.append(newsession)

                if server.serverKeyHash.isEmpty, let idx = serverProfile.servers.firstIndex(of: server) {
                    serverProfile.servers[idx].serverKeyHash = serverKeyHash
                }
                return newsession
            }
            return nil
        }
        else {
            var serverKeyHash = server.serverKeyHash
            let userIdentity = UserIdentity(userName: userID.userName, b64_prrvateKey: userID.b64_prrvateKey, passphrease: userID.passphrease)
            let newsession = sshDaemon.connect(remoteServer: server.remoteHost, remotePort: server.remotePort, user_id: userIdentity, server_hashkey: &serverKeyHash, logger: { log in
                DispatchQueue.main.async {
                    text += log + "\n"
                }
            })
            guard let newsession = newsession else {
                return nil
            }
            session_list.append(newsession)

            if server.serverKeyHash.isEmpty, let idx = serverProfile.servers.firstIndex(of: server) {
                DispatchQueue.main.async {
                    serverProfile.servers[idx].serverKeyHash = serverKeyHash
                }
            }
            return newsession
        }
    }
    
    func removeTag() {
        guard let idx = tabData.tabData.firstIndex(where: { $0.id == tabData.selectedTab }) else {
            return
        }

        let children = tabData.tabData[idx].childTag
        for child in children {
            guard let idx = tabData.tabData.firstIndex(where: { $0.id == child }) else {
                continue
            }
            tabData.tabData.remove(at: idx)
        }

        DispatchQueue.main.async {
            tabData.tabData.remove(at: idx)
        }

        guard let id = tabData.tabData.first?.id else {
            return
        }
        DispatchQueue.main.async {
            tabData.selectedTab = id
        }
    }
    
    func browser() {
        guard let session = session else {
            return
        }

        let localPort = UInt16.random(in: 1024...UInt16.max)
        let portForward = LocalPortForward(localPort: localPort, remoteHost: "go.com", remotePort: 80)
        if sshDaemon.localPortFoward(session: session, portForward: portForward) {
            guard let idx = tabData.tabData.firstIndex(where: { $0.id == tabData.selectedTab }) else {
                return
            }

            let newTab = TabDataItem(title: Text("Brower"), image: Image(systemName: "network"), tabView: AnyView(LocalWebView(url: "http://localhost:\(localPort)")))
            tabData.tabData.append(newTab)
            
            tabData.tabData[idx].childTag.append(newTab.id)
            
            tabData.selectedTab = newTab.id
        }
    }
    
    var body: some View {
        ZStack {
            ConsoleView(isActive: $isShowing, handler: handler, windowTitle: $windowTitle)
                .opacity(isShowing ? 1: 0)
            VStack(alignment: .leading) {
                HStack {
                    Text("\(remoteHost):\(remotePort)")
                    Spacer()
                    Button(action: {
                        for session1 in session_list.reversed() {
                            sshDaemon.disconnect(session: session1)
                        }
                        removeTag()
                    }) {
                        Text("Disconnect")
                    }
                }
                ScrollView {
                    Text(text)
                        .lineLimit(nil)
                }
            }
            .opacity(isShowing ? 0: 1)
        }
        .padding()
        .onAppear() {
            if isInit {
                return
            }
            isInit = true
            
            DispatchQueue.global().async {
                connect()
            }
        }
    }
}

struct ServerConnection_Previews: PreviewProvider {
    static var previews: some View {
        ServerConnection(serverTag: UUID())
    }
}
