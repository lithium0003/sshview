//
//  ServerConnection.swift
//  sshtest
//
//  Created by rei8 on 2022/04/16.
//

import SwiftUI
import libssh

enum ConnectionError: Error {
    case BError
}

class connectionTask {
    let sshDaemon: SSHDaemon
    let depend: connectionTask?
    let localPort: UInt16
    let remoteHost: String
    let remotePort: UInt16
    let server_hashkey: [UInt8]
    let userid: UserIdentity
    let logger: (String)->Void
    let return_hashkey: ([UInt8])->Void
    var session: ssh_session!
    
    init(sshDaemon: SSHDaemon, depend: connectionTask?, localPort: UInt16, remoteHost: String, remotePort: UInt16, server_hashkey: [UInt8], userid: UserIdentity, logger: @escaping (String)->Void, return_hashkey: @escaping ([UInt8])->Void) {
        self.sshDaemon = sshDaemon
        self.depend = depend
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.server_hashkey = server_hashkey
        self.userid = userid
        self.logger = logger
        self.return_hashkey = return_hashkey
        self.session = nil
    }
    
    func run() async throws -> ssh_session {
        if let depend = depend {
            Task {
                try await Task.sleep(for: Duration.seconds(15))
                guard let parentSession = depend.session else {
                    throw ConnectionError.BError
                }
                if await !sshDaemon.checkSession(session: parentSession) {
                    throw ConnectionError.BError
                }
            }
            guard await sshDaemon.localPortFoward(session: try await depend.run(), localPort: localPort, remoteHost: remoteHost, remotePort: UInt16(remotePort)) else {
                throw ConnectionError.BError
            }
            session = try await sshDaemon.connect(remoteServer: "localhost", remotePort: Int(localPort), user_id: userid, server_hashkey: server_hashkey, logger: logger, return_hashkey: return_hashkey)
        }
        else {
            session = try await sshDaemon.connect(remoteServer: remoteHost, remotePort: Int(remotePort), user_id: userid, server_hashkey: server_hashkey, logger: logger, return_hashkey: return_hashkey)
        }
        return session
    }
    
    func session_list() -> [ssh_session] {
        var ret: [ssh_session] = []
        ret.append(session)
        var prev = depend
        while prev != nil {
            ret.append(prev!.session)
            prev = prev!.depend
        }
        return ret
    }
}

struct ServerConnection: View {
    var serverTag: UUID
    var tabTag: UUID
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
    @State var screenWidth = 80
    @State var screenHeight = 24
    
    @State private var isShowing = false
    @ObservedObject var handler = stdHandlers()
    @ObservedObject var term = TerminalScreen()
    @State var isTerminalMode = true
    @State var regexString: String?
    @State var bufStdout: [UInt8] = []
    @State var forwardPort = 0
    @State var fixedPort = 0
    @State var browserURL = ""
    @State var initTimeout = 15
    
    @State var timer1: DispatchSourceTimer?
    @State var timer2: DispatchSourceTimer?
    
    func connect(serverID: UUID) throws -> connectionTask {
        guard let server = serverProfile.servers.first(where: { $0.id == serverID }) else {
            throw ConnectionError.BError
        }
        guard let userID = userProfile.userid.first(where: { $0.id == server.userIDtag }) else {
            throw ConnectionError.BError
        }
        if let proxy = server.proxyServerID {
            let prevTask = try connect(serverID: proxy)
            
            let localPort = UInt16.random(in: 1024...UInt16.max)
            let userIdentity = UserIdentity(userName: userID.userName, b64_prrvateKey: userID.b64_prrvateKey, passphrease: userID.passphrease)

            return connectionTask(sshDaemon: sshDaemon, depend: prevTask, localPort: localPort, remoteHost: server.remoteHost, remotePort: UInt16(server.remotePort), server_hashkey: server.serverKeyHash, userid: userIdentity, logger: { log in
                DispatchQueue.main.async {
                    text += log + "\n"
                }
            }, return_hashkey: { newkey in
                DispatchQueue.main.async {
                    if server.serverKeyHash.isEmpty, let idx = serverProfile.servers.firstIndex(of: server) {
                        serverProfile.servers[idx].serverKeyHash = newkey
                    }
                }
            })
        }
        else {
            let userIdentity = UserIdentity(userName: userID.userName, b64_prrvateKey: userID.b64_prrvateKey, passphrease: userID.passphrease)
            
            return connectionTask(sshDaemon: sshDaemon, depend: nil, localPort: 0, remoteHost: server.remoteHost, remotePort: UInt16(server.remotePort), server_hashkey: server.serverKeyHash, userid: userIdentity, logger: { log in
                DispatchQueue.main.async {
                    text += log + "\n"
                }
            }, return_hashkey: { newkey in
                DispatchQueue.main.async {
                    if server.serverKeyHash.isEmpty, let idx = serverProfile.servers.firstIndex(of: server) {
                        serverProfile.servers[idx].serverKeyHash = newkey
                    }
                }
            })
        }
    }

    @MainActor
    func connect() async throws {
        guard let server = serverProfile.servers.first(where: { $0.id == serverTag }) else {
            throw ConnectionError.BError
        }
        Task { @MainActor in
            remoteHost = server.remoteHost
            remotePort = server.remotePort
        }
        let task = try connect(serverID: server.id)
        
        session = try await task.run()
        session_list = task.session_list()
        
        if let command = server.serverCommand {
            regexString = server.grepPortFoward
            fixedPort = server.portFoward
            try await runCommand(command: Array(command.data(using: .utf8)!) + [0])
        }
        else {
            try await allcateConsole()
        }
    }
    
    func runCommand(command: [UInt8]) async throws{
        guard let session = session else {
            return
        }

        DispatchQueue.main.async {
            isShowing = true
        }

        try await sshDaemon.waitConnection(session: session, timeout: Duration.seconds(15))
        guard let stdInFcn = handler.stdInFcn else {
            return
        }
        guard let stdOutFcn = handler.stdOutFcn else {
            return
        }

        Task {
            defer {
                DispatchQueue.main.async {
                    handler.stdInFcn = nil
                    handler.stdOutFcn = nil
                    handler.screeSizeChange = nil
                }

                Task {
                    for session1 in session_list.reversed() {
                        await sshDaemon.disconnect(session: session1)
                    }
                }
                DispatchQueue.main.async {
                    isShowing = false
                }
                DispatchQueue.main.async {
                    removeTag()
                }
            }

            do {
                try await sshDaemon.runCommand(session: session, comand: command, stdinFnc: stdInFcn, stdoutFnc: stdOutFcn, stderrFnc: stdOutFcn)
                if await sshDaemon.waitCommand(session: session, commandIdx: 0, timeout: Duration.seconds(20)) {
                    while await sshDaemon.checkCommand(session: session, commandIdx: 0) {
                        if forwardPort == 0, let grep = regexString {
                            do {
                                let regex = try NSRegularExpression(pattern: grep, options: NSRegularExpression.Options())
                                let output = String(bytes: bufStdout, encoding: .utf8)!
                                let results  = regex.matches(in: output, range: NSMakeRange(0, output.count))
                                if results.count > 0, results[0].numberOfRanges > 1 {
                                    forwardPort = Int(NSString(string: output).substring(with: results[0].range(at: 1))) ?? 0
                                    if results[0].numberOfRanges > 2 {
                                        browserURL = NSString(string: output).substring(with: results[0].range(at: 2))
                                    }
                                }
                            }
                            catch {
                                print(error)
                                throw ConnectionError.BError
                            }
                            print(forwardPort)
                            if forwardPort > 0 {
                                await browser()
                            }
                        }
                        if forwardPort == 0, fixedPort > 0 {
                            forwardPort = fixedPort
                            print(forwardPort)
                            await browser()
                        }
                        
                        try await Task.sleep(for: Duration.seconds(1))
                    }
                }
            }
            catch {
            }
        }
    }
    
    func allcateConsole() async throws {
        guard let session = session else {
            return
        }

        DispatchQueue.main.async {
            handler.screeSizeChange = { newWidth, newHeight in
                Task {
                    try? await sshDaemon.setNewsizeTerminal(session: session, terminalIdx: 0, newWidth: newWidth, newHeight: newHeight)
                }
            }
            isShowing = true
        }

        try await sshDaemon.waitConnection(session: session, timeout: Duration.seconds(15))
        guard let stdInFcn = handler.stdInFcn else {
            return
        }
        guard let stdOutFcn = handler.stdOutFcn else {
            return
        }

        Task {
            defer {
                DispatchQueue.main.async {
                    handler.stdInFcn = nil
                    handler.stdOutFcn = nil
                    handler.screeSizeChange = nil
                }

                Task {
                    for session1 in session_list.reversed() {
                        await sshDaemon.disconnect(session: session1)
                    }
                }
                DispatchQueue.main.async {
                    isShowing = false
                }
                DispatchQueue.main.async {
                    removeTag()
                }
            }

            do {
                try await sshDaemon.createTerminal(session: session, stdinFnc: stdInFcn, stdoutFnc: stdOutFcn, stderrFnc: nil)
                if await sshDaemon.waitTerminal(session: session, terminalIdx: 0, timeout: Duration.seconds(20)) {
                    while await sshDaemon.checkTerminal(session: session, terminalIdx: 0) {
                        try await Task.sleep(for: Duration.seconds(1))
                    }
                }
            }
            catch {
            }
        }
    }
        
    func removeTag() {
        DispatchQueue.main.async {
            guard let curTab = tabData.tabData[tabTag] else {
                return
            }

            let rmtag = [tabTag] + curTab.childTag
            tabData.tabIdx = tabData.tabIdx.filter({ !rmtag.contains($0) })
            for uuid in rmtag {
                tabData.tabData.removeValue(forKey: uuid)
            }
            
            if tabData.selectedTab != tabTag {
                return
            }
            guard let id = tabData.tabIdx.first else {
                return
            }
            DispatchQueue.main.async {
                tabData.selectedTab = id
            }
        }
    }
    
    func browser() async {
        guard let session = session else {
            return
        }

        let localPort = UInt16.random(in: 1024...UInt16.max)
        if await sshDaemon.localPortFoward(session: session, localPort: localPort, remoteHost: "localhost", remotePort: UInt16(forwardPort)) {
            DispatchQueue.main.async {
                guard var curTab = tabData.tabData[tabTag] else {
                    return
                }
                
                let newTag = UUID()
                let newTab = TabDataItem(id: newTag, title: Text("Brower"), image: Image(systemName: "network"), tabView: AnyView(LocalWebView(url: "http://localhost:\(localPort)/\(browserURL)")))
                tabData.tabData[newTag] = newTab
                tabData.tabIdx.append(newTag)
                
                curTab.childTag.append(newTag)
                tabData.tabData[tabTag] = curTab
                
                tabData.selectedTab = newTag
            }
        }
    }
    
    var body: some View {
        ZStack {
            if isTerminalMode {
                ConsoleView(isActive: $isShowing, handler: handler, term: term)
                    .opacity(isShowing ? 1: 0)
            }
            else {
                CommandView(isActive: $isShowing, handler: handler, term: term, bufferStdOut: $bufStdout)
                    .opacity(isShowing ? 1: 0)
            }
            VStack(alignment: .leading) {
                HStack {
                    Text("\(remoteHost):\(remotePort)")
                    Spacer()
                    Button(role:.destructive, action: {
                        for session1 in session_list.reversed() {
                            Task.detached {
                                await sshDaemon.disconnect(session: session1)
                            }
                        }
                        removeTag()
                    }) {
                        Image(systemName: "trash")
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
        .task {
            if isInit {
                return
            }
            isInit = true
            guard let server = serverProfile.servers.first(where: { $0.id == serverTag }) else {
                return
            }
            isTerminalMode = server.serverCommand == nil
            if !isTerminalMode {
                term.expandLF = true
            }
            do {
                try await connect()
            }
            catch {
                removeTag()
            }
        }
    }
}

struct ServerConnection_Previews: PreviewProvider {
    @State static var id = UUID()
    @StateObject static var term = TerminalScreen()
    
    static var previews: some View {
        ServerConnection(serverTag: UUID(), tabTag: id, term: term)
    }
}
