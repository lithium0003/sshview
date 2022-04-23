//
//  ServerConnection.swift
//  sshtest
//
//  Created by rei8 on 2022/04/16.
//

import SwiftUI
import libssh

class connectionOperation: Operation {
    let sshDaemon: SSHDaemon
    let depend: connectionOperation?
    let localPort: UInt16
    let remoteHost: String
    let remotePort: UInt16
    let server_hashkey: [UInt8]
    let userid: UserIdentity
    let logger: (String)->Void
    let return_hashkey: ([UInt8])->Void
    var session: ssh_session!
    
    init(sshDaemon: SSHDaemon, depend: connectionOperation?, localPort: UInt16, remoteHost: String, remotePort: UInt16, server_hashkey: [UInt8], userid: UserIdentity, logger: @escaping (String)->Void, return_hashkey: @escaping ([UInt8])->Void) {
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
    
    override func main() {
        if let depend = depend {
            guard let parentSession = depend.session else {
                return
            }
            var timeout = 15
            while timeout > 0, !sshDaemon.checkSession(session: parentSession) {
                Thread.sleep(forTimeInterval: 1.0)
                timeout -= 1
            }
            guard sshDaemon.localPortFoward(session: parentSession, localPort: localPort, remoteHost: remoteHost, remotePort: UInt16(remotePort)) else {
                return
            }
            session = sshDaemon.connect(remoteServer: "localhost", remotePort: Int(localPort), user_id: userid, server_hashkey: server_hashkey, logger: logger, return_hashkey: return_hashkey)
        }
        else {
            session = sshDaemon.connect(remoteServer: remoteHost, remotePort: Int(remotePort), user_id: userid, server_hashkey: server_hashkey, logger: logger, return_hashkey: return_hashkey)
        }
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
    
    @State var queue = OperationQueue()
    @State var timer1: DispatchSourceTimer?
    @State var timer2: DispatchSourceTimer?
    
    func connect(serverID: UUID) -> [connectionOperation] {
        guard let server = serverProfile.servers.first(where: { $0.id == serverID }) else {
            return []
        }
        guard let userID = userProfile.userid.first(where: { $0.id == server.userIDtag }) else {
            return []
        }
        if let proxy = server.proxyServerID {
            let operations = connect(serverID: proxy)
            guard let proxyOperation = operations.last else {
                return []
            }
            
            let localPort = UInt16.random(in: 1024...UInt16.max)
            let userIdentity = UserIdentity(userName: userID.userName, b64_prrvateKey: userID.b64_prrvateKey, passphrease: userID.passphrease)

            let op = connectionOperation(sshDaemon: sshDaemon, depend: proxyOperation, localPort: localPort, remoteHost: server.remoteHost, remotePort: UInt16(server.remotePort), server_hashkey: server.serverKeyHash, userid: userIdentity, logger: { log in
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
            op.addDependency(proxyOperation)
            return operations + [op]
        }
        else {
            let userIdentity = UserIdentity(userName: userID.userName, b64_prrvateKey: userID.b64_prrvateKey, passphrease: userID.passphrease)
            
            let op = connectionOperation(sshDaemon: sshDaemon, depend: nil, localPort: 0, remoteHost: server.remoteHost, remotePort: UInt16(server.remotePort), server_hashkey: server.serverKeyHash, userid: userIdentity, logger: { log in
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
            return [op]
        }
    }

    func connect() {
        guard let server = serverProfile.servers.first(where: { $0.id == serverTag }) else {
            removeTag()
            return
        }
        remoteHost = server.remoteHost
        remotePort = server.remotePort
        let operations = connect(serverID: server.id)
        if operations.isEmpty {
            removeTag()
            return
        }
        
        queue.addOperations(operations, waitUntilFinished: true)
        
        session = operations.last?.session
        guard session != nil else {
            removeTag()
            return
        }
        session_list = operations.map({ $0.session })
        
        if let command = server.serverCommand {
            regexString = server.grepPortFoward
            fixedPort = server.portFoward
            runCommand(command: Array(command.data(using: .utf8)!) + [0])
        }
        else {
            allcateConsole()
        }
    }
    
    func runCommand(command: [UInt8]) {
        guard let session = session else {
            return
        }

        DispatchQueue.main.async {
            isShowing = true
        }

        timer1 = DispatchSource.makeTimerSource(flags: [], queue: .global(qos: .background))
        timer1?.schedule(deadline: .now(), repeating: 1.0)
        timer1?.setEventHandler {
            if initTimeout > 0 {
                if !sshDaemon.checkSession(session: session) {
                    initTimeout -= 1
                    return
                }
                guard let stdInFcn = handler.stdInFcn else {
                    return
                }
                guard let stdOutFcn = handler.stdOutFcn else {
                    return
                }

                timer1?.cancel()
                
                sshDaemon.runCommand(session: session, comand: command, stdinFnc: stdInFcn, stdoutFnc: stdOutFcn, stderrFnc: stdOutFcn)

                var timeout = 20
                while timeout > 0, !sshDaemon.checkCommand(session: session, commandIdx: 0) {
                    Thread.sleep(forTimeInterval: 1.0)
                    timeout -= 1
                }
            }
            else {
                timer1?.cancel()
            }
            timer2?.resume()
        }
        timer1?.resume()

        timer2 = DispatchSource.makeTimerSource(flags: [], queue: .global(qos: .background))
        timer2?.schedule(deadline: .now(), repeating: 5.0)
        timer2?.setEventHandler {
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
                }
                print(forwardPort)
                if forwardPort > 0 {
                    browser()
                }
            }
            if forwardPort == 0, fixedPort > 0 {
                forwardPort = fixedPort
                print(forwardPort)
                browser()
            }
            
            if sshDaemon.checkCommand(session: session, commandIdx: 0) {
                return
            }
            timer2?.cancel()
            
            DispatchQueue.main.async {
                handler.stdInFcn = nil
                handler.stdOutFcn = nil
            }
        }
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

        timer1 = DispatchSource.makeTimerSource(flags: [], queue: .global(qos: .background))
        timer1?.schedule(deadline: .now(), repeating: 1.0)
        timer1?.setEventHandler {
            if initTimeout > 0 {
                if !sshDaemon.checkSession(session: session) {
                    initTimeout -= 1
                    return
                }
                guard let stdInFcn = handler.stdInFcn else {
                    return
                }
                guard let stdOutFcn = handler.stdOutFcn else {
                    return
                }
                timer1?.cancel()

                sshDaemon.createTerminal(session: session, stdinFnc: stdInFcn, stdoutFnc: stdOutFcn, stderrFnc: nil)

                var timeout = 20
                while timeout > 0, !sshDaemon.checkTerminal(session: session, terminalIdx: 0) {
                    Thread.sleep(forTimeInterval: 1.0)
                    timeout -= 1
                }
            }
            else {
                timer1?.cancel()
            }
            timer2?.resume()
        }
        timer1?.resume()

        timer2 = DispatchSource.makeTimerSource(flags: [], queue: .global(qos: .background))
        timer2?.schedule(deadline: .now(), repeating: 1.0)
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
    
    func browser() {
        guard let session = session else {
            return
        }

        let localPort = UInt16.random(in: 1024...UInt16.max)
        if sshDaemon.localPortFoward(session: session, localPort: localPort, remoteHost: "localhost", remotePort: UInt16(forwardPort)) {
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
        .onAppear() {
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
            
            queue.name = "Server"
            queue.qualityOfService = .userInteractive
            queue.maxConcurrentOperationCount = 1

            DispatchQueue.global().async {
                connect()
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
