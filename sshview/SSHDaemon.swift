//
//  SSHDaemon.swift
//  sshtest
//
//  Created by rei8 on 2022/04/14.
//

import Foundation
import libssh
import SwiftUI

struct UserIdentity {
    var userName = ""
    var b64_prrvateKey = ""
    var passphrease = ""
}

class LocalPortForward {
    let queue: DispatchQueue
    let session: ssh_session
    let localPort: UInt16
    let remoteHost: String
    let remotePort: UInt16
    let serverSockfd: Int32

    var connSockfds: [Int32: ssh_channel] = [:]
    
    let buflen = 4 * 1024
    lazy var buffer = [UInt8](repeating: 0, count: buflen)

    init?(queue: DispatchQueue, session: ssh_session, localPort: UInt16, remoteHost: String, remotePort: UInt16) {
        self.queue = queue
        self.session = session
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort

        var hints = addrinfo()
        memset(&hints, 0, MemoryLayout.size(ofValue: hints))
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_PASSIVE

        var ai: addrinfo
        var res: UnsafeMutablePointer<addrinfo>? = nil
        print("getaddrinfo")
        let err = getaddrinfo("localhost", "\(localPort)", &hints, &res)
        guard err == 0 else {
            perror("getaddrinfo() failed: \(err)")
            return nil
        }
        guard let resp = res else {
            perror("getaddrinfo() failed: nullpointer")
            return nil
        }
        ai = resp.pointee

        let serverSockfd = socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol)
        print("socket")
        guard serverSockfd >= 0 else {
            perror("ERROR opening socket")
            return nil
        }

        var reuse = 1
        print("setsockopt")
        guard setsockopt(serverSockfd, SOL_SOCKET, SO_REUSEADDR, withUnsafePointer(to: &reuse) { $0 }, socklen_t(MemoryLayout.size(ofValue: reuse))) >= 0 else {
            perror("setsockopt(SO_REUSEADDR) failed")
            close(serverSockfd)
            return nil
        }
        
        print("bind")
        guard bind(serverSockfd, ai.ai_addr, ai.ai_addrlen) >= 0 else {
            perror("ERROR on binding")
            close(serverSockfd)
            return nil
        }
        
        print("listen")
        listen(serverSockfd, 10)

        self.serverSockfd = serverSockfd
    }
    
    func closeConnection() {
        queue.async { [self] in
            for (fb, channel) in connSockfds {
                close(fb)
                ssh_channel_free(channel)
            }
            connSockfds = [:]
        }
    }
    
    func checkChennels() {
        var delChannels: [Int32] = []
        queue.async { [self] in
            for (fb, channel) in connSockfds {
                if ssh_channel_is_open(channel) != 0, ssh_channel_is_eof(channel) == 0 {
                    continue
                }
                print("del \(fb)")
                delChannels.append(fb)
                close(fb)
                ssh_channel_free(channel)
            }
            for fb in delChannels {
                connSockfds.removeValue(forKey: fb)
            }
        }
    }
    
    func createNewConnection(newsockfd: Int32) {
        queue.async { [self] in
            let forwarding_channel = ssh_channel_new(session)
            guard forwarding_channel != nil else {
                print("ssh_channel_new() failed")
                close(newsockfd)
                return
            }

            let rc = ssh_channel_open_forward(forwarding_channel,
                                          remoteHost, Int32(remotePort),
                                          "127.0.0.1", Int32(localPort))
            guard rc == SSH_OK else {
                print("ssh_channel_open_forward() failed \(rc)")

                ssh_channel_free(forwarding_channel)
                close(newsockfd)
                return
            }
            
            self.connSockfds[newsockfd] = forwarding_channel
        }
    }
    
    func process() {
        var fds = fd_set()
        var maxfd: socket_t = 0
        var timeout = timeval(tv_sec: 0, tv_usec: 0)
        maxfd = max(maxfd, serverSockfd)
        __darwin_fd_set(serverSockfd, &fds)
        for fd in connSockfds.keys {
            maxfd = max(maxfd, fd)
            __darwin_fd_set(fd, &fds)
        }
        maxfd += 1
        
        let in_channels = UnsafeMutablePointer<ssh_channel?>.allocate(capacity: connSockfds.count+1)
        let out_channels = UnsafeMutablePointer<ssh_channel?>.allocate(capacity: connSockfds.count+1)
        for (i, channel) in connSockfds.values.enumerated() {
            in_channels[i] = channel
        }
        in_channels[connSockfds.count] = nil
        
        ssh_select(in_channels, out_channels, maxfd, &fds, &timeout)

        for i in 0..<connSockfds.count {
            guard let channel = out_channels[i] else {
                break
            }
            guard let fd = connSockfds.first(where: { $0.value == channel })?.key else {
                continue
            }
            print("ssh_channel_read")
            let nbytes = buffer.withUnsafeMutableBytes { ssh_channel_read(channel, $0.baseAddress, UInt32(buflen), 0) }
            if nbytes < 0 {
                print("ssh_channel_read() error")
                close(fd)
                ssh_channel_free(channel)
            }
            if nbytes > 0 {
                print("ssh_channel_read() \(nbytes)")
                let n = buffer.withUnsafeMutableBytes { write(fd, $0.baseAddress, Int(nbytes)) }
                if n != nbytes {
                    print("write() error")
                    close(fd)
                    ssh_channel_free(channel)
                }
                print("write \(nbytes)")
            }
        }
        
        for fd in connSockfds.keys {
            if __darwin_fd_isset(fd, &fds) != 0 {
                print(fd)
                if let channel = connSockfds[fd] {
                    let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, buflen) }
                    if n < 0 {
                        print("\(fd) is error")
                    }
                    if n == 0 {
                        print("\(fd) is eof")
                    }
                    print(fd, n)

                    if n > 0 {
                        let nwritten = ssh_channel_write(channel, buffer, UInt32(n))
                        if nwritten != n {
                            print("\(nwritten) of \(n) write, error")
                            close(fd)
                            ssh_channel_free(channel)
                        }
                        else {
                            print("successfly write \(nwritten)")
                        }
                    }
                    else {
                        close(fd)
                        ssh_channel_free(channel)
                    }
                }
            }
        }

        if __darwin_fd_isset(serverSockfd, &fds) != 0 {
            var cli_addr = sockaddr()
            var clilen = socklen_t()
            let newsockfd = accept(serverSockfd, &cli_addr, &clilen)
            print("accept \(newsockfd)")

            createNewConnection(newsockfd: newsockfd)
        }
    }
}

class TerminalSession {
    let queue: DispatchQueue
    var width = 80
    var height = 24
    var isOpen = true
    
    var stdoutFnc: ((ArraySlice<UInt8>)->Void)?
    var stderrFnc: ((ArraySlice<UInt8>)->Void)?
    var stdinFnc: (()->[UInt8]?)?

    var channel: ssh_channel!
    
    let buflen = 4 * 1024
    lazy var buffer = [UInt8](repeating: 0, count: buflen)

    init?(queue: DispatchQueue, session: ssh_session, stdinFnc: (()->[UInt8]?)?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?) {
        print("createTerminal")
        self.queue = queue
        queue.async { [self] in
            guard let channel = ssh_channel_new(session) else {
                isOpen = false
                return
            }
            self.channel = channel

            guard isOpen else { return }
            var rc = ssh_channel_open_session(channel)
            if rc != SSH_OK {
                print("ssh_channel_open_session() failed \(rc)")
                isOpen = false
                ssh_channel_free(channel)
            }

            guard isOpen else { return }
            rc = ssh_channel_request_pty(channel)
            if rc != SSH_OK {
                print("ssh_channel_request_pty() failed \(rc)")
                isOpen = false
                ssh_channel_close(channel)
                ssh_channel_send_eof(channel)
                ssh_channel_free(channel)
            }

            guard isOpen else { return }
            rc = ssh_channel_change_pty_size(channel, Int32(width), Int32(height))
            if rc != SSH_OK {
                print("ssh_channel_change_pty_size() failed \(rc)")
                isOpen = false
                ssh_channel_close(channel)
                ssh_channel_send_eof(channel)
                ssh_channel_free(channel)
            }

            guard isOpen else { return }
            rc = ssh_channel_request_shell(channel)
            if rc != SSH_OK {
                print("ssh_channel_request_shell() failed \(rc)")
                isOpen = false
                ssh_channel_close(channel)
                ssh_channel_send_eof(channel)
                ssh_channel_free(channel)
            }

            guard isOpen else { return }
            self.stdinFnc = stdinFnc
            self.stdoutFnc = stdoutFnc
            self.stderrFnc = stderrFnc
        }
    }
        
    func closeConnection() {
        queue.async { [self] in
            stdinFnc = nil
            stdoutFnc = nil
            stderrFnc = nil
            guard isOpen else { return }
            isOpen = false
            ssh_channel_close(channel)
            ssh_channel_send_eof(channel)
            ssh_channel_free(channel)
        }
    }
    
    func setNewsizeTerminal(newWidth: Int, newHeight: Int) {
        width = newWidth
        height = newHeight
        queue.async { [self] in
            guard isOpen else { return }
            let rc = ssh_channel_change_pty_size(channel, Int32(width), Int32(height))
            if rc != SSH_OK {
                print("ssh_channel_change_pty_size() failed \(rc)")
                isOpen = false
                ssh_channel_close(channel)
                ssh_channel_send_eof(channel)
                ssh_channel_free(channel)
            }
        }
    }
    
    func check() -> Bool {
        return isOpen && ssh_channel_is_open(channel) != 0 && ssh_channel_is_eof(channel) == 0
    }
    
    func process() {
        guard isOpen else {
            return
        }

        let nbytes = buffer.withUnsafeMutableBytes { ssh_channel_read_timeout(channel, $0.baseAddress, UInt32(buflen), 0, 0) }
        if nbytes < 0 {
            print("ssh_channel_read() error")
            ssh_channel_close(channel)
            ssh_channel_send_eof(channel)
            ssh_channel_free(channel)
            isOpen = false
        }
        else if nbytes > 0 {
            print("ssh_channel_read() \(nbytes)")
            stdoutFnc?(buffer[0..<Int(nbytes)])
        }
        else {
            stdoutFnc?([])
        }
        if let stdinFnc = stdinFnc {
            if let inputbuffer = stdinFnc() {
                if inputbuffer.count > 0 {
                    let nwritten = ssh_channel_write(channel, inputbuffer, UInt32(inputbuffer.count))
                    if nwritten != inputbuffer.count {
                        print("\(nwritten) of \(inputbuffer.count) write, error")
                        ssh_channel_close(channel)
                        ssh_channel_send_eof(channel)
                        ssh_channel_free(channel)
                        isOpen = false
                    }
                    else {
                        print("successfly write \(nwritten)")
                    }
                }
            }
            else {
                // input is done
                ssh_channel_send_eof(channel)
            }
        }
        
        if isOpen, ssh_channel_is_open(channel) == 0, ssh_channel_is_eof(channel) != 0 {
            ssh_channel_close(channel)
            ssh_channel_send_eof(channel)
            ssh_channel_free(channel)
            isOpen = false
        }
    }
}

class CommandSession {
    let queue: DispatchQueue
    var isOpen = true
    
    var stdoutFnc: ((ArraySlice<UInt8>)->Void)?
    var stderrFnc: ((ArraySlice<UInt8>)->Void)?
    var stdinFnc: (()->[UInt8]?)?

    var channel: ssh_channel!

    let buflen = 4 * 1024
    lazy var buffer = [UInt8](repeating: 0, count: buflen)

    init? (queue: DispatchQueue, session: ssh_session, comand: [UInt8], stdinFnc: (()->[UInt8]?)?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?) {
        self.queue = queue
        self.stdinFnc = stdinFnc
        self.stdoutFnc = stdoutFnc
        self.stderrFnc = stderrFnc
        print("runCommand")
        
        queue.async { [self] in
            guard let channel = ssh_channel_new(session) else {
                isOpen = false
                return
            }
            self.channel = channel

            guard isOpen else { return }
            var rc = ssh_channel_open_session(channel)
            if rc != SSH_OK {
                print("ssh_channel_open_session() failed \(rc)")
                isOpen = false
                ssh_channel_free(channel)
            }

            guard isOpen else { return }
            rc = comand.withUnsafeBytes { ssh_channel_request_exec(channel, $0.baseAddress?.bindMemory(to: Int8.self, capacity: comand.count)) }
            if rc != SSH_OK {
                print("ssh_channel_request_exec() failed \(rc)")
                isOpen = false
                ssh_channel_close(channel)
                ssh_channel_send_eof(channel)
                ssh_channel_free(channel)
            }
        }
    }

    func closeConnection() {
        queue.async { [self] in
            stdinFnc = nil
            stdoutFnc = nil
            stderrFnc = nil
            guard isOpen else { return }
            isOpen = false
            ssh_channel_close(channel)
            ssh_channel_send_eof(channel)
            ssh_channel_free(channel)
        }
    }

    func check() -> Bool {
        return isOpen && ssh_channel_is_open(channel) != 0 && ssh_channel_is_eof(channel) == 0
    }
    
    func process() {
        guard isOpen else {
            return
        }

        let nbytes = buffer.withUnsafeMutableBytes { ssh_channel_read_timeout(channel, $0.baseAddress, UInt32(buflen), 0, 0) }
        if nbytes < 0 {
            print("ssh_channel_read() error")
            ssh_channel_close(channel)
            ssh_channel_send_eof(channel)
            ssh_channel_free(channel)
            isOpen = false
        }
        else if nbytes > 0 {
            print("ssh_channel_read() \(nbytes)")
            stdoutFnc?(buffer[0..<Int(nbytes)])
        }
        else {
            stdoutFnc?([])
        }
        let nbytes2 = buffer.withUnsafeMutableBytes { ssh_channel_read_timeout(channel, $0.baseAddress, UInt32(buflen), 1, 0) }
        if nbytes2 < 0 {
            print("ssh_channel_read() error")
            ssh_channel_close(channel)
            ssh_channel_send_eof(channel)
            ssh_channel_free(channel)
            isOpen = false
        }
        else if nbytes2 > 0 {
            print("ssh_channel_read() \(nbytes2)")
            stderrFnc?(buffer[0..<Int(nbytes2)])
        }
        else {
            stderrFnc?([])
        }
        if let stdinFnc = stdinFnc {
            if let inputbuffer = stdinFnc() {
                if inputbuffer.count > 0 {
                    let nwritten = ssh_channel_write(channel, inputbuffer, UInt32(inputbuffer.count))
                    if nwritten != inputbuffer.count {
                        print("\(nwritten) of \(inputbuffer.count) write, error")
                        ssh_channel_close(channel)
                        ssh_channel_send_eof(channel)
                        ssh_channel_free(channel)
                        isOpen = false
                    }
                    else {
                        print("successfly write \(nwritten)")
                    }
                }
            }
            else {
                ssh_channel_request_send_signal(channel, "INT")
                ssh_channel_request_send_signal(channel, "INT")
                ssh_channel_send_eof(channel)
            }
        }
        
        if isOpen, ssh_channel_is_open(channel) == 0, ssh_channel_is_eof(channel) != 0 {
            ssh_channel_close(channel)
            ssh_channel_send_eof(channel)
            ssh_channel_free(channel)
            isOpen = false
        }
    }
}

class SessionHandles {
    let queue: DispatchQueue
    var session: ssh_session
    var logger: (String)->Void
    var localForwards: [LocalPortForward] = []
    var terminalSessions: [TerminalSession] = []
    var commandSessions: [CommandSession] = []
    
    init(queue: DispatchQueue, session: ssh_session, logger: @escaping (String)->Void) {
        self.queue = queue
        self.session = session
        self.logger = logger
    }
    
    func disconnect() {
        for tidx in (0..<terminalSessions.count).reversed() {
            terminalSessions[tidx].closeConnection()
            terminalSessions.remove(at: tidx)
        }
        for cidx in (0..<commandSessions.count).reversed() {
            commandSessions[cidx].closeConnection()
            commandSessions.remove(at: cidx)
        }
        for fidx in (0..<localForwards.count).reversed() {
            localForwards[fidx].closeConnection()
            localForwards.remove(at: fidx)
        }
        queue.async { [self] in
            ssh_disconnect(session)
            ssh_free(session)
            
            ssh_finalize()
        }
    }
    
    func process() {
        queue.async { [self] in
            for localForward in localForwards {
                localForward.process()
            }
            for terminalSession in terminalSessions {
                terminalSession.process()
            }
            for commandSession in commandSessions {
                commandSession.process()
            }
            for localForward in localForwards {
                localForward.checkChennels()
            }
        }
    }
    
    func localPortFoward(localPort: UInt16, remoteHost: String, remotePort: UInt16) -> Bool {
        guard let newForward = LocalPortForward(queue: queue, session: session, localPort: localPort, remoteHost: remoteHost, remotePort: remotePort) else {
            return false
        }
        localForwards.append(newForward)
        return true
    }
    
    func runCommand(comand: [UInt8], stdinFnc: (()->[UInt8]?)?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?) {
        guard let newCommand = CommandSession(queue: queue, session: session, comand: comand, stdinFnc: stdinFnc, stdoutFnc: stdoutFnc, stderrFnc: stderrFnc) else {
            return
        }
        commandSessions.append(newCommand)
    }
    
    func createTerminal(stdinFnc: (()->[UInt8]?)?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?) {
        guard let newTerminal = TerminalSession(queue: queue, session: session, stdinFnc: stdinFnc, stdoutFnc: stdoutFnc, stderrFnc: stderrFnc) else {
            return
        }
        terminalSessions.append(newTerminal)
    }
    
    func setNewsizeTerminal(terminalIdx: Int, newWidth: Int, newHeight: Int) {
        guard terminalIdx >= 0, terminalIdx < terminalSessions.count else {
            return
        }
        terminalSessions[terminalIdx].setNewsizeTerminal(newWidth: newWidth, newHeight: newHeight)
    }
    
    func checkTerminal(terminalIdx: Int) -> Bool {
        guard terminalIdx >= 0, terminalIdx < terminalSessions.count else {
            return false
        }
        return terminalSessions[terminalIdx].check()
    }
    
    func closeTerminal(terminalIdx: Int) {
        guard terminalIdx >= 0, terminalIdx < terminalSessions.count else {
            return
        }
        terminalSessions[terminalIdx].closeConnection()
        terminalSessions.remove(at: terminalIdx)
    }

    func checkCommand(commandIdx: Int) -> Bool {
        guard commandIdx >= 0, commandIdx < commandSessions.count else {
            return false
        }
        return commandSessions[commandIdx].check()
    }
    
}

let handler: @convention(c) (Int32) -> () = { sig in
    // handle the signal somehow
    print("error", sig)
}

class SSHDaemon: ObservableObject {
    var connections: [SessionHandles] = []
    let opQueue = OperationQueue()
    var timer: DispatchSourceTimer

    let buflen = 4 * 1024
    lazy var buffer = [UInt8](repeating: 0, count: buflen)

    init() {
        signal(SIGPIPE, handler)
        
        ssh_init()
        
        timer = DispatchSource.makeTimerSource(flags: [], queue: .global())
        timer.schedule(deadline: .now(), repeating: 0.005)
        timer.setEventHandler {
            self.processDataLoop()
        }
        timer.resume()
    }
    
    deinit {
        timer.cancel()
        _ = ssh_finalize()
    }
    

    func connect(remoteServer: String, remotePort: Int, user_id: UserIdentity, server_hashkey: [UInt8], logger: @escaping (String)->Void, return_hashkey: @escaping ([UInt8])->Void) -> ssh_session? {
        
        print("SSH connect \(remoteServer):\(remotePort)")
        let queue = DispatchQueue(label: "session")

        let session = queue.sync { () -> ssh_session? in
            ssh_init()

            guard let session = ssh_new() else {
                return nil
            }
            return session
        }
        
        queue.async { [self] in
            guard var session = session else {
                return
            }

            var verbosity = SSH_LOG_PROTOCOL
            let remoteServer = remoteServer.cString(using: .utf8)
            var remotePort = remotePort
            let userName = user_id.userName.cString(using: .utf8)

            ssh_options_set(session, SSH_OPTIONS_HOST, remoteServer)
            ssh_options_set(session, SSH_OPTIONS_LOG_VERBOSITY, &verbosity)
            ssh_options_set(session, SSH_OPTIONS_PORT, &remotePort)
            ssh_options_set(session, SSH_OPTIONS_USER, userName)

            guard ssh_connect(session) == SSH_OK else {
                let e = String(cString: ssh_get_error(&session))
                logger("ssh_connect() failed " + e)
                ssh_free(session)
                return
            }

            guard let srv_hkey = SSHDaemon.verify_knownhost(session) else {
                logger("host key is not match.")
                ssh_disconnect(session)
                ssh_free(session)
                return
            }
            logger("server key : " + srv_hkey.map({ String(format: "%02x", $0) }).joined(separator: ":"))

            if server_hashkey.count > 0 {
                if !srv_hkey.elementsEqual(server_hashkey) {
                    logger("server key not match!")
                    ssh_disconnect(session)
                    ssh_free(session)
                    return
                }
            }
            return_hashkey(srv_hkey)

            let b64_prikey = user_id.b64_prrvateKey.cString(using: .utf8)
            let passphrase = user_id.passphrease.cString(using: .utf8)
            var prikey: ssh_key!
            var pubkey: ssh_key!

            guard ssh_pki_import_privkey_base64(b64_prikey, passphrase, nil, nil, &prikey) == SSH_OK, prikey != nil else {
                logger("private key cannot load")
                ssh_disconnect(session)
                ssh_free(session)
                return
            }
            defer {
                ssh_key_free(prikey)
            }

            guard ssh_pki_export_privkey_to_pubkey(prikey, &pubkey) == SSH_OK else {
                logger("public key conversion failed")
                ssh_disconnect(session)
                ssh_free(session)
                return
            }
            defer {
                ssh_key_free(pubkey)
            }
            
            var rc = ssh_userauth_try_publickey(session, nil, pubkey)
            guard rc == SSH_AUTH_SUCCESS.rawValue else {
                logger("auth error (public key) \(rc)")
                ssh_disconnect(session)
                ssh_free(session)
                return
            }

            rc = ssh_userauth_publickey(session, nil, prikey)
            guard rc == SSH_AUTH_SUCCESS.rawValue else {
                logger("auth error (public key) \(rc)")
                ssh_disconnect(session)
                ssh_free(session)
                return
            }

            logger("Connect successfully")

            connections.append(SessionHandles(queue: queue, session: session, logger: logger))
        }
        return session
    }
    
    func disconnect(session: ssh_session) {
        for i in 0..<connections.count {
            if connections[i].session == session {
                connections[i].disconnect()
                connections.remove(at: i)
                break
            }
        }
    }
    
    func localPortFoward(session: ssh_session, localPort: UInt16, remoteHost: String, remotePort: UInt16) -> Bool {
        for i in 0..<connections.count {
            if connections[i].session == session {
                return connections[i].localPortFoward(localPort: localPort, remoteHost: remoteHost, remotePort: remotePort)
            }
        }
        return false
    }
    
    func runCommand(session: ssh_session, comand: [UInt8], stdinFnc: (()->[UInt8]?)?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?)  {
        for i in 0..<connections.count {
            if connections[i].session == session {
                connections[i].runCommand(comand: comand, stdinFnc: stdinFnc, stdoutFnc: stdoutFnc, stderrFnc: stderrFnc)
            }
        }
    }
    
    func createTerminal(session: ssh_session, stdinFnc: (()->[UInt8]?)?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?) {
        for i in 0..<connections.count {
            if connections[i].session == session {
                connections[i].createTerminal(stdinFnc: stdinFnc, stdoutFnc: stdoutFnc, stderrFnc: stderrFnc)
            }
        }
    }
    
    func setNewsizeTerminal(session: ssh_session, terminalIdx: Int, newWidth: Int, newHeight: Int) {
        for i in 0..<connections.count {
            if connections[i].session == session {
                connections[i].setNewsizeTerminal(terminalIdx: terminalIdx, newWidth: newWidth, newHeight: newHeight)
            }
        }
    }
    
    func checkSession(session: ssh_session) -> Bool {
        for i in 0..<connections.count {
            if connections[i].session == session {
                return true
            }
        }
        return false
    }
    
    func checkTerminal(session: ssh_session, terminalIdx: Int) -> Bool {
        for i in 0..<connections.count {
            if connections[i].session == session {
                return connections[i].checkTerminal(terminalIdx: terminalIdx)
            }
        }
        return false
    }
    
    func closeTerminal(session: ssh_session, terminalIdx: Int) {
        for i in 0..<connections.count {
            if connections[i].session == session {
                return connections[i].closeTerminal(terminalIdx: terminalIdx)
            }
        }
    }

    func checkCommand(session: ssh_session, commandIdx: Int) -> Bool {
        for i in 0..<connections.count {
            if connections[i].session == session {
                return connections[i].checkCommand(commandIdx: commandIdx)
            }
        }
        return false
    }

    func processDataLoop() {
        for c in connections {
            c.process()
        }
    }
    
    class func verify_knownhost(_ session: ssh_session) -> [UInt8]? {
        var session = session
        var srv_pubkey: ssh_key!
        var hash: UnsafeMutablePointer<UInt8>!
        var hlen = 0
        if ssh_get_server_publickey(session, &srv_pubkey) < 0 {
            let e = String(cString: ssh_get_error(&session))
            print(e)
            return nil
        }
        defer {
            ssh_key_free(srv_pubkey)
        }
        if ssh_get_publickey_hash(srv_pubkey, SSH_PUBLICKEY_HASH_SHA1, &hash, &hlen) < 0 {
            let e = String(cString: ssh_get_error(&session))
            print(e)
            return nil
        }
        defer {
            ssh_clean_pubkey_hash(&hash)
        }
        
        return Array(UnsafeBufferPointer(start: hash, count: hlen))
    }
}
