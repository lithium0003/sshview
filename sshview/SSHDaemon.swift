//
//  SSHDaemon.swift
//  sshtest
//
//  Created by rei8 on 2022/04/14.
//

import Foundation
import libssh
import SwiftUI

enum SSHError: Error {
    case AError
}

struct UserIdentity {
    var userName = ""
    var b64_prrvateKey = ""
    var passphrease = ""
}

actor PollWait {
    init() {
        ssh_init()
    }
    deinit {
        ssh_finalize()
    }
    
    func _ssh_connect(_ session: ssh_session) -> Int32 {
        ssh_connect(session)
    }
    
    func _ssh_channel_open_session(_ channel: ssh_channel) -> Int32 {
        ssh_channel_open_session(channel)
    }

    func _ssh_channel_request_pty(_ channel: ssh_channel) -> Int32 {
        ssh_channel_request_pty(channel)
    }

    func _ssh_channel_change_pty_size(_ channel: ssh_channel, _ width: Int32, _ height: Int32) -> Int32 {
        ssh_channel_change_pty_size(channel, width, height)
    }
    
    func _ssh_channel_request_shell(_ channel: ssh_channel) -> Int32 {
        ssh_channel_request_shell(channel)
    }
    
    func _ssh_channel_request_exec(_ channel: ssh_channel, _ comand: [UInt8]) -> Int32 {
        comand.withUnsafeBytes { ssh_channel_request_exec(channel, $0.baseAddress?.bindMemory(to: Int8.self, capacity: comand.count)) }
    }
    
    func _ssh_channel_open_forward(_ forwarding_channel: ssh_channel?, _ remotehost: String, _ remotePort: Int32, _ localhost: String, _ localPort: Int32) -> Int32 {
        ssh_channel_open_forward(forwarding_channel, remotehost, remotePort, localhost, localPort)
    }
    
    func _ssh_select(_ in_channels: [ssh_channel?], _ out_channels: UnsafeMutablePointer<ssh_channel?>?, _ maxfd: socket_t, _ fds: UnsafeMutablePointer<fd_set>, _ timeout: UnsafeMutablePointer<timeval>) {
        var in_channels = in_channels
        in_channels.withUnsafeMutableBufferPointer { in_channels in
            ssh_select(in_channels.baseAddress!, out_channels, maxfd, fds, timeout)
        }
    }
}

actor LocalPortForward {
    let localPort: UInt16
    let remoteHost: String
    let remotePort: UInt16
    let serverSockfd: Int32

    let session: ssh_session
    
    var connSockfds: [Int32: ssh_channel] = [:]
        
    static let buflen = 512 * 1024
    var buffer = [UInt8](repeating: 0, count: buflen)

    init?(session: ssh_session, localPort: UInt16, remoteHost: String, remotePort: UInt16)  {
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
        for (fb, channel) in connSockfds {
            close(fb)
            ssh_channel_free(channel)
        }
        connSockfds = [:]
    }
    
    func checkChennels() async {
        var delChannels: [Int32] = []
        for (fb, channel) in connSockfds {
            if ssh_channel_is_open(channel) != 0, ssh_channel_is_eof(channel) == 0 {
                continue
            }
            delChannels.append(fb)
        }
        for fb in delChannels {
            if let channel = connSockfds.removeValue(forKey: fb) {
                print("del \(fb)")
                close(fb)
                ssh_channel_free(channel)
            }
        }
    }
    
    func createNewConnection(newsockfd: Int32) async throws {
        do {
            let forwarding_channel = ssh_channel_new(session)
            guard forwarding_channel != nil else {
                print("ssh_channel_new() failed")
                throw SSHError.AError
            }
            do {
                var rc: Int32
                repeat {
                    rc = await SSHDaemon.pollwait._ssh_channel_open_forward(forwarding_channel,
                                                  remoteHost, Int32(remotePort),
                                                  "127.0.0.1", Int32(localPort))
                } while rc == SSH_AGAIN
                if rc != SSH_OK {
                    print("ssh_channel_open_forward() failed \(rc)")
                    throw SSHError.AError
                }
                connSockfds[newsockfd] = forwarding_channel
            }
            catch {
                ssh_channel_free(forwarding_channel)
                throw error
            }
        }
        catch {
            close(newsockfd)
            throw error
        }
    }
    
    func process() async throws {
        var fds = fd_set()
        var maxfd: socket_t = 0
        var timeout = timeval(tv_sec: 0, tv_usec: 0)
        
        var channels: [ssh_channel?] = []
        maxfd = max(maxfd, serverSockfd)
        __darwin_fd_set(serverSockfd, &fds)
        for fd in connSockfds.keys {
            maxfd = max(maxfd, fd)
            __darwin_fd_set(fd, &fds)
            channels.append(connSockfds[fd])
        }
        channels.append(nil)
        maxfd += 1

        let out_channels = UnsafeMutablePointer<ssh_channel?>.allocate(capacity: channels.count)
        defer {
            out_channels.deallocate()
        }
        await SSHDaemon.pollwait._ssh_select(channels, out_channels, maxfd, &fds, &timeout)

        for i in 0..<channels.count {
            guard let channel = out_channels[i] else {
                break
            }
            guard let fd = connSockfds.first(where: { $0.value == channel })?.key else {
                continue
            }
            print("ssh_channel_read")
            let nbytes = buffer.withUnsafeMutableBytes { ssh_channel_read(channel, $0.baseAddress, UInt32(LocalPortForward.buflen), 0) }
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
                    let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, LocalPortForward.buflen) }
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
            
            Task.detached {
                try await self.createNewConnection(newsockfd: newsockfd)
            }
        }
    }
}

actor TerminalSession {
    var width = 80
    var height = 24
    var isOpen = true
    
    var stdoutFnc: ((ArraySlice<UInt8>)->Void)?
    var stderrFnc: ((ArraySlice<UInt8>)->Void)?
    var stdinFnc: (()->[UInt8]?)?

    var channel: ssh_channel!
    
    static let buflen = 512 * 1024
    var buffer = [UInt8](repeating: 0, count: buflen)

    init?(session: ssh_session, stdinFnc: (()->[UInt8]?)?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?) async throws {
        print("createTerminal")

        guard let channel = ssh_channel_new(session) else {
            isOpen = false
            throw SSHError.AError
        }
        self.channel = channel

        do {
            let t = Task {
                do {
                    var rc: Int32
                    repeat {
                        rc = await SSHDaemon.pollwait._ssh_channel_open_session(channel)
                    } while rc == SSH_AGAIN
                    if rc != SSH_OK {
                        print("ssh_channel_open_session() failed \(rc)")
                        throw SSHError.AError
                    }
                    
                    do {
                        repeat {
                            rc = await SSHDaemon.pollwait._ssh_channel_request_pty(channel)
                        } while rc == SSH_AGAIN
                        if rc != SSH_OK {
                            print("ssh_channel_request_pty() failed \(rc)")
                            throw SSHError.AError
                        }

                        repeat {
                            rc = await SSHDaemon.pollwait._ssh_channel_change_pty_size(channel, Int32(width), Int32(height))
                        } while rc == SSH_AGAIN
                        if rc != SSH_OK {
                            print("ssh_channel_change_pty_size() failed \(rc)")
                            throw SSHError.AError
                        }

                        repeat {
                            rc = await SSHDaemon.pollwait._ssh_channel_request_shell(channel)
                        } while rc == SSH_AGAIN
                        if rc != SSH_OK {
                            print("ssh_channel_request_shell() failed \(rc)")
                            throw SSHError.AError
                        }
                    }
                    catch {
                        ssh_channel_close(channel)
                        ssh_channel_send_eof(channel)
                        throw error
                    }
                }
                catch {
                    ssh_channel_free(channel)
                    throw error
                }
            }
            try await t.result
        }
        catch {
            isOpen = false
            throw error
        }
        self.stdinFnc = stdinFnc
        self.stdoutFnc = stdoutFnc
        self.stderrFnc = stderrFnc
    }
        
    func closeConnection() {
        stdinFnc = nil
        stdoutFnc = nil
        stderrFnc = nil
        guard isOpen else { return }
        isOpen = false
        ssh_channel_close(channel)
        ssh_channel_send_eof(channel)
        ssh_channel_free(channel)
    }
    
    func setNewsizeTerminal(newWidth: Int, newHeight: Int) async throws {
        width = newWidth
        height = newHeight
        guard isOpen else { return }

        do {
            var rc: Int32
            repeat {
                rc = await SSHDaemon.pollwait._ssh_channel_change_pty_size(channel, Int32(width), Int32(height))
            } while rc == SSH_AGAIN
            if rc != SSH_OK {
                print("ssh_channel_change_pty_size() failed \(rc)")
                throw SSHError.AError
            }
        }
        catch {
            isOpen = false
            ssh_channel_close(channel)
            ssh_channel_send_eof(channel)
            ssh_channel_free(channel)
            throw error
        }
    }
    
    func check() -> Bool {
        return isOpen && ssh_channel_is_open(channel) != 0 && ssh_channel_is_eof(channel) == 0
    }
    
    func process() {
        guard isOpen else {
            return
        }

        let nbytes = buffer.withUnsafeMutableBytes { ssh_channel_read_timeout(channel, $0.baseAddress, UInt32(TerminalSession.buflen), 0, 0) }
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

actor CommandSession {
    var isOpen = true
    
    var stdoutFnc: ((ArraySlice<UInt8>)->Void)?
    var stderrFnc: ((ArraySlice<UInt8>)->Void)?
    var stdinFnc: (()->[UInt8]?)?

    var channel: ssh_channel!

    static let buflen = 512 * 1024
    var buffer = [UInt8](repeating: 0, count: buflen)

    init? (session: ssh_session, comand: [UInt8], stdinFnc: (()->[UInt8]?)?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?) async throws {
        self.stdinFnc = stdinFnc
        self.stdoutFnc = stdoutFnc
        self.stderrFnc = stderrFnc
        print("runCommand")
        guard let channel = ssh_channel_new(session) else {
            throw SSHError.AError
        }
        self.channel = channel
        do {
            let t = Task {
                do {
                    var rc: Int32
                    repeat {
                        rc = await SSHDaemon.pollwait._ssh_channel_open_session(channel)
                    } while rc == SSH_AGAIN
                    if rc != SSH_OK {
                        print("ssh_channel_open_session() failed \(rc)")
                        throw SSHError.AError
                    }

                    do {
                        repeat {
                            rc = await SSHDaemon.pollwait._ssh_channel_request_exec(channel, comand)
                        } while rc == SSH_AGAIN
                        if rc != SSH_OK {
                            print("ssh_channel_request_exec() failed \(rc)")
                            throw SSHError.AError
                        }
                    }
                    catch {
                        ssh_channel_close(channel)
                        ssh_channel_send_eof(channel)
                        throw error
                    }
                }
                catch {
                    ssh_channel_free(channel)
                    throw error
                }
            }
            try await t.result
        }
        catch {
            isOpen = false
            throw error
        }
    }

    func closeConnection() {
        stdinFnc = nil
        stdoutFnc = nil
        stderrFnc = nil
        guard isOpen else { return }
        isOpen = false
        ssh_channel_close(channel)
        ssh_channel_send_eof(channel)
        ssh_channel_free(channel)
    }

    func check() -> Bool {
        return isOpen && ssh_channel_is_open(channel) != 0 && ssh_channel_is_eof(channel) == 0
    }
    
    func process() {
        guard isOpen else {
            return
        }

        let nbytes = buffer.withUnsafeMutableBytes { ssh_channel_read_timeout(channel, $0.baseAddress, UInt32(CommandSession.buflen), 0, 0) }
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
        let nbytes2 = buffer.withUnsafeMutableBytes { ssh_channel_read_timeout(channel, $0.baseAddress, UInt32(CommandSession.buflen), 1, 0) }
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
    var session: ssh_session
    var logger: (String)->Void
    actor Sessions {
        var localForwards: [LocalPortForward] = []
        var terminalSessions: [TerminalSession] = []
        var commandSessions: [CommandSession] = []
        
        func addLocalForwards(forward: LocalPortForward) {
            localForwards.append(forward)
        }
        
        func addCommandSessions(command: CommandSession) {
            commandSessions.append(command)
        }
        
        func addTerminalSessions(terminal: TerminalSession) {
            terminalSessions.append(terminal)
        }
        
        func clear() async {
            for tidx in (0..<terminalSessions.count).reversed() {
                await terminalSessions[tidx].closeConnection()
                terminalSessions.remove(at: tidx)
            }
            for cidx in (0..<commandSessions.count).reversed() {
                await commandSessions[cidx].closeConnection()
                commandSessions.remove(at: cidx)
            }
            for fidx in (0..<localForwards.count).reversed() {
                await localForwards[fidx].closeConnection()
                localForwards.remove(at: fidx)
            }
        }

        func closeTerminal(terminalIdx: Int) async {
            guard terminalIdx >= 0, terminalIdx < terminalSessions.count else {
                return
            }
            await terminalSessions[terminalIdx].closeConnection()
            terminalSessions.remove(at: terminalIdx)
        }
    }
    let sessions = Sessions()
    
    init(session: ssh_session, logger: @escaping (String)->Void) {
        self.session = session
        self.logger = logger
    }
    
    func disconnect() async {
        await sessions.clear()
        ssh_disconnect(session)
        ssh_free(session)
    }
    
    func process() async throws {
        for localForward in await sessions.localForwards {
            try await localForward.process()
        }
        for terminalSession in await sessions.terminalSessions {
            await terminalSession.process()
        }
        for commandSession in await sessions.commandSessions {
            await commandSession.process()
        }
        for localForward in await sessions.localForwards {
            await localForward.checkChennels()
        }
    }
    
    func localPortFoward(localPort: UInt16, remoteHost: String, remotePort: UInt16) async -> Bool {
        guard let newForward = await LocalPortForward(session: session, localPort: localPort, remoteHost: remoteHost, remotePort: remotePort) else {
            return false
        }
        await sessions.addLocalForwards(forward: newForward)
        return true
    }
    
    func runCommand(comand: [UInt8], stdinFnc: (()->[UInt8]?)?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?) async throws {
        guard let newCommand = try await CommandSession(session: session, comand: comand, stdinFnc: stdinFnc, stdoutFnc: stdoutFnc, stderrFnc: stderrFnc) else {
            return
        }
        await sessions.addCommandSessions(command: newCommand)
    }
    
    func createTerminal(stdinFnc: (()->[UInt8]?)?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?) async throws {
        guard let newTerminal = try await TerminalSession(session: session, stdinFnc: stdinFnc, stdoutFnc: stdoutFnc, stderrFnc: stderrFnc) else {
            return
        }
        await sessions.addTerminalSessions(terminal: newTerminal)
    }
    
    func setNewsizeTerminal(terminalIdx: Int, newWidth: Int, newHeight: Int) async throws {
        guard terminalIdx >= 0, await terminalIdx < sessions.terminalSessions.count else {
            return
        }
        try await sessions.terminalSessions[terminalIdx].setNewsizeTerminal(newWidth: newWidth, newHeight: newHeight)
    }
    
    func checkTerminal(terminalIdx: Int) async -> Bool {
        guard terminalIdx >= 0, await terminalIdx < sessions.terminalSessions.count else {
            return false
        }
        return await sessions.terminalSessions[terminalIdx].check()
    }
    
    func closeTerminal(terminalIdx: Int) async {
        await sessions.closeTerminal(terminalIdx: terminalIdx)
    }

    func checkCommand(commandIdx: Int) async -> Bool {
        guard commandIdx >= 0, await commandIdx < sessions.commandSessions.count else {
            return false
        }
        return await sessions.commandSessions[commandIdx].check()
    }
    
}

let handler: @convention(c) (Int32) -> () = { sig in
    // handle the signal somehow
    print("error", sig)
}

class SSHDaemon: ObservableObject {
    static let pollwait = PollWait()
    
    actor Connections {
        var connections: [SessionHandles] = []

        func add(newConnection: SessionHandles) {
            connections.append(newConnection)
        }
        
        func disconnect(session: ssh_session) async {
            for i in 0..<connections.count {
                if connections[i].session == session {
                    await connections[i].disconnect()
                    connections.remove(at: i)
                    break
                }
            }
        }
    }
    let connection = Connections()

    static let buflen = 512 * 1024
    var buffer = [UInt8](repeating: 0, count: buflen)
    var task = Task<Void, Never> {}
    
    init() {
        signal(SIGPIPE, handler)
        
        task = Task {
            while true {
                await processDataLoop()
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
    }
    
    deinit {
        task.cancel()
    }
    

    func connect(remoteServer: String, remotePort: Int, user_id: UserIdentity, server_hashkey: [UInt8], logger: @escaping (String)->Void, return_hashkey: @escaping ([UInt8])->Void) async throws -> ssh_session {
        
        print("SSH connect \(remoteServer):\(remotePort)")

        guard var session = ssh_new() else {
            throw SSHError.AError
        }
        do {
            ssh_set_blocking(session, 0);

            var verbosity = SSH_LOG_PROTOCOL
            let remoteServer = remoteServer.cString(using: .utf8)
            var remotePort = remotePort
            let userName = user_id.userName.cString(using: .utf8)

            ssh_options_set(session, SSH_OPTIONS_HOST, remoteServer)
            ssh_options_set(session, SSH_OPTIONS_LOG_VERBOSITY, &verbosity)
            ssh_options_set(session, SSH_OPTIONS_PORT, &remotePort)
            ssh_options_set(session, SSH_OPTIONS_USER, userName)

            var ret: Int32
            repeat {
                ret = await SSHDaemon.pollwait._ssh_connect(session)
            } while ret == SSH_AGAIN
            if ret == SSH_ERROR {
                let e = String(cString: ssh_get_error(&session))
                logger("ssh_connect() failed " + e)
                throw SSHError.AError
            }

            do {
                guard let srv_hkey = SSHDaemon.verify_knownhost(session) else {
                    logger("host key is not match.")
                    throw SSHError.AError
                }

                logger("server key : " + srv_hkey.map({ String(format: "%02x", $0) }).joined(separator: ":"))

                if server_hashkey.count > 0 {
                    if !srv_hkey.elementsEqual(server_hashkey) {
                        logger("server key not match!")
                        throw SSHError.AError
                    }
                }

                return_hashkey(srv_hkey)

                let b64_prikey = user_id.b64_prrvateKey.cString(using: .utf8)
                let passphrase = user_id.passphrease.cString(using: .utf8)
                var prikey: ssh_key!
                var pubkey: ssh_key!

                guard ssh_pki_import_privkey_base64(b64_prikey, passphrase, nil, nil, &prikey) == SSH_OK, prikey != nil else {
                    logger("private key cannot load")
                    throw SSHError.AError
                }
                defer {
                    ssh_key_free(prikey)
                }

                guard ssh_pki_export_privkey_to_pubkey(prikey, &pubkey) == SSH_OK, pubkey != nil else {
                    logger("public key cannot convert")
                    throw SSHError.AError
                }
                defer {
                    ssh_key_free(pubkey)
                }

                var rc: Int32
                repeat {
                    rc = ssh_userauth_try_publickey(session, nil, pubkey)
                } while rc == SSH_AUTH_AGAIN.rawValue
                if rc != SSH_AUTH_SUCCESS.rawValue {
                    logger("auth error (public key) \(rc)")
                    throw SSHError.AError
                }

                repeat {
                    rc = ssh_userauth_publickey(session, nil, prikey)
                } while rc == SSH_AUTH_AGAIN.rawValue
                if rc != SSH_AUTH_SUCCESS.rawValue {
                    logger("auth error (public key) \(rc)")
                    throw SSHError.AError
                }
                
                logger("Connect successfully")
                
                await connection.add(newConnection: SessionHandles(session: session, logger: logger))
            }
            catch {
                ssh_disconnect(session)
                throw error
            }
        }
        catch {
            ssh_free(session)
            throw error
        }

        return session
    }
    
    func disconnect(session: ssh_session) async {
        await connection.disconnect(session: session)
    }
    
    func localPortFoward(session: ssh_session, localPort: UInt16, remoteHost: String, remotePort: UInt16) async -> Bool {
        for i in await 0..<connection.connections.count {
            if await connection.connections[i].session == session {
                return await connection.connections[i].localPortFoward(localPort: localPort, remoteHost: remoteHost, remotePort: remotePort)
            }
        }
        return false
    }
    
    func runCommand(session: ssh_session, comand: [UInt8], stdinFnc: (()->[UInt8]?)?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?) async throws {
        for i in await 0..<connection.connections.count {
            if await connection.connections[i].session == session {
                try await connection.connections[i].runCommand(comand: comand, stdinFnc: stdinFnc, stdoutFnc: stdoutFnc, stderrFnc: stderrFnc)
            }
        }
    }
    
    func createTerminal(session: ssh_session, stdinFnc: (()->[UInt8]?)?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?) async throws {
        for i in await 0..<connection.connections.count {
            if await connection.connections[i].session == session {
                try await connection.connections[i].createTerminal(stdinFnc: stdinFnc, stdoutFnc: stdoutFnc, stderrFnc: stderrFnc)
            }
        }
    }
    
    func setNewsizeTerminal(session: ssh_session, terminalIdx: Int, newWidth: Int, newHeight: Int) async throws {
        for i in await 0..<connection.connections.count {
            if await connection.connections[i].session == session {
                try await connection.connections[i].setNewsizeTerminal(terminalIdx: terminalIdx, newWidth: newWidth, newHeight: newHeight)
            }
        }
    }
    
    func waitConnection(session: ssh_session, timeout: Duration) async throws {
        let task = Task {
            while await !checkSession(session: session) {
                try Task.checkCancellation()
                try await Task.sleep(for: Duration.seconds(1))
            }
        }
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            task.cancel()
        }
        try await task.value
        timeoutTask.cancel()
    }
    
    func checkSession(session: ssh_session) async -> Bool {
        for i in await 0..<connection.connections.count {
            if await connection.connections[i].session == session {
                return true
            }
        }
        return false
    }

    func waitTerminal(session: ssh_session, terminalIdx: Int, timeout: Duration) async -> Bool {
        let task = Task {
            do {
                while await !checkTerminal(session: session, terminalIdx: terminalIdx) {
                    try Task.checkCancellation()
                    try await Task.sleep(for: Duration.seconds(1))
                }
                return true
            }
            catch {
                return false
            }
        }
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            task.cancel()
        }
        let pass = await task.value
        timeoutTask.cancel()
        return pass
    }

    func checkTerminal(session: ssh_session, terminalIdx: Int) async -> Bool {
        for i in await 0..<connection.connections.count {
            if await connection.connections[i].session == session {
                return await connection.connections[i].checkTerminal(terminalIdx: terminalIdx)
            }
        }
        return false
    }
    
    func closeTerminal(session: ssh_session, terminalIdx: Int) async {
        for i in await 0..<connection.connections.count {
            if await connection.connections[i].session == session {
                return await connection.connections[i].closeTerminal(terminalIdx: terminalIdx)
            }
        }
    }

    func waitCommand(session: ssh_session, commandIdx: Int, timeout: Duration) async -> Bool {
        let task = Task {
            do {
                while await !checkCommand(session: session, commandIdx: commandIdx) {
                    try Task.checkCancellation()
                    try await Task.sleep(for: Duration.seconds(1))
                }
                return true
            }
            catch {
                return false
            }
        }
        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            task.cancel()
        }
        let pass = await task.value
        timeoutTask.cancel()
        return pass
    }

    func checkCommand(session: ssh_session, commandIdx: Int) async -> Bool {
        for i in await 0..<connection.connections.count {
            if await connection.connections[i].session == session {
                return await connection.connections[i].checkCommand(commandIdx: commandIdx)
            }
        }
        return false
    }

    func processDataLoop() async {
        for c in await connection.connections {
            try? await c.process()
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
