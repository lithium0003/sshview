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
    var localPort: UInt16 = 0
    var remoteHost = "localhost"
    var remotePort: UInt16 = 0

    var serverSockfd: Int32 = 0
    var connSockfds: [Int32: ssh_channel] = [:]
    
    init(localPort: UInt16, remoteHost: String, remotePort: UInt16) {
        self.localPort = localPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
    }
}

class TerminalSession {
    var width = 80
    var height = 24
    var isOpen = true
    
    var stdoutFnc: ((ArraySlice<UInt8>)->Void)?
    var stderrFnc: ((ArraySlice<UInt8>)->Void)?
    var stdinFnc: (()->[UInt8])?

    var channel: ssh_channel
    
    init(channel: ssh_channel) {
        self.channel = channel
    }
}

class SessionHandles {
    var session: ssh_session
    var logger: (String)->Void
    var localForwards: [LocalPortForward] = []
    var terminalSessions: [TerminalSession] = []
    
    init(session: ssh_session, logger: @escaping (String)->Void) {
        self.session = session
        self.logger = logger
    }
}

let handler: @convention(c) (Int32) -> () = { sig in
    // handle the signal somehow
    print("error", sig)
}

class SSHDaemon: ObservableObject {
    let queue = DispatchQueue(label: "sshd")
    let connQueue = DispatchQueue(label: "connect")
    var timer: DispatchSourceTimer
    
    var connections: [SessionHandles] = []

    let buflen = 4 * 1024
    lazy var buffer = [UInt8](repeating: 0, count: buflen)

    init() {
        signal(SIGPIPE, handler)
        
        timer = DispatchSource.makeTimerSource(flags: [], queue: queue)
        queue.async {
            ssh_init()
        }
        timer.schedule(deadline: .now(), repeating: 0.002)
        timer.setEventHandler {
            self.processDataLoop()
        }
        timer.resume()
    }
    
    deinit {
        queue.sync {
            timer.cancel()
            _ = ssh_finalize()
        }
    }
    
    func connect(remoteServer: String, remotePort: Int, user_id: UserIdentity, server_hashkey: inout [UInt8], logger: @escaping (String)->Void) -> ssh_session? {
        connQueue.sync {
            print("SSH connect \(remoteServer):\(remotePort)")

            guard var session = ssh_new() else {
                return nil
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
                return nil
            }

            guard let srv_hkey = verify_knownhost(session) else {
                logger("host key is not match.")
                ssh_disconnect(session)
                ssh_free(session)
                return nil
            }

            logger("server key : " + srv_hkey.map({ String(format: "%02x", $0) }).joined(separator: ":"))
            
            if server_hashkey.count == 0 {
                server_hashkey = srv_hkey
            }
            else {
                if !srv_hkey.elementsEqual(server_hashkey) {
                    logger("server key not match!")
                    ssh_disconnect(session)
                    ssh_free(session)
                    return nil
                }
            }


            let b64_prikey = user_id.b64_prrvateKey.cString(using: .utf8)
            let passphrase = user_id.passphrease.cString(using: .utf8)
            var prikey: ssh_key!
            var pubkey: ssh_key!

            guard ssh_pki_import_privkey_base64(b64_prikey, passphrase, nil, nil, &prikey) == SSH_OK, prikey != nil else {
                logger("private key cannot load")
                ssh_disconnect(session)
                ssh_free(session)
                return nil
            }
            defer {
                ssh_key_free(prikey)
            }
            
            guard ssh_pki_export_privkey_to_pubkey(prikey, &pubkey) == SSH_OK else {
                logger("public key conversion failed")
                ssh_disconnect(session)
                ssh_free(session)
                return nil
            }
            defer {
                ssh_key_free(pubkey)
            }
            
            
            var rc = ssh_userauth_try_publickey(session, nil, pubkey)
            guard rc == SSH_AUTH_SUCCESS.rawValue else {
                logger("auth error \(rc) (public key)")
                ssh_disconnect(session)
                ssh_free(session)
                return nil
            }
            
            rc = ssh_userauth_publickey(session, nil, prikey)
            guard rc == SSH_AUTH_SUCCESS.rawValue else {
                logger("auth error \(rc) (private key)")
                ssh_disconnect(session)
                ssh_free(session)
                return nil
            }

            logger("Connect successfully")

            queue.async {
                self.connections.append(SessionHandles(session: session, logger: logger))
            }
            
            return session
        }
    }
    
    func disconnect(session: ssh_session) {
        queue.async { [self] in
            if let idx = connections.firstIndex(where: { $0.session == session }) {
                for tidx in (0..<connections[idx].terminalSessions.count).reversed() {
                    closeTerminal(session: session, terminalIdx: tidx)
                }
                connections.remove(at: idx)
            }
            ssh_disconnect(session)
            ssh_free(session)
        }
    }
    
    func localPortFoward(session: ssh_session, portForward: LocalPortForward) -> Bool {
        guard let idx = queue.sync(execute: { connections.firstIndex(where: { $0.session == session }) }) else {
            print("connection array not found")
            return false
        }
        return connQueue.sync {
            var hints = addrinfo()
            memset(&hints, 0, MemoryLayout.size(ofValue: hints))
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            hints.ai_flags = AI_PASSIVE

            var ai: addrinfo
            var res: UnsafeMutablePointer<addrinfo>? = nil
            print("getaddrinfo")
            let err = getaddrinfo("localhost", "\(portForward.localPort)", &hints, &res)
            guard err == 0 else {
                perror("getaddrinfo() failed: \(err)")
                return false
            }
            guard let resp = res else {
                perror("getaddrinfo() failed: nullpointer")
                return false
            }
            ai = resp.pointee

            let serverSockfd = socket(ai.ai_family, ai.ai_socktype, ai.ai_protocol)
            print("socket")
            guard serverSockfd >= 0 else {
                perror("ERROR opening socket")
                return false
            }

            var reuse = 1
            print("setsockopt")
            guard setsockopt(serverSockfd, SOL_SOCKET, SO_REUSEADDR, withUnsafePointer(to: &reuse) { $0 }, socklen_t(MemoryLayout.size(ofValue: reuse))) >= 0 else {
                perror("setsockopt(SO_REUSEADDR) failed");
                close(serverSockfd)
                return false
            }
            
            print("bind")
            guard bind(serverSockfd, ai.ai_addr, ai.ai_addrlen) >= 0 else {
                perror("ERROR on binding")
                close(serverSockfd)
                return false
            }
            
            print("listen")
            listen(serverSockfd, 10)

            queue.async {
                portForward.serverSockfd = serverSockfd
                self.connections[idx].localForwards.append(portForward)
            }
            
            return true
        }
    }
    
    func createTerminal(session: ssh_session, stdinFnc: (()->[UInt8])?, stdoutFnc: ((ArraySlice<UInt8>)->Void)?, stderrFnc: ((ArraySlice<UInt8>)->Void)?) {
        guard let idx = queue.sync( execute: { connections.firstIndex(where: { $0.session == session }) }) else {
            print("connection array not found")
            return
        }
        connQueue.sync {
            guard let channel = ssh_channel_new(session) else {
                return
            }
            print("createTerminal")
            var rc = ssh_channel_open_session(channel)
            if rc != SSH_OK {
                print("ssh_channel_open_session() failed \(rc)")
                ssh_channel_free(channel)
                return
            }

            rc = ssh_channel_request_pty(channel)
            if rc != SSH_OK {
                print("ssh_channel_request_pty() failed \(rc)")
                _ = self.connections[idx].terminalSessions.popLast()
                ssh_channel_close(channel);
                ssh_channel_send_eof(channel);
                ssh_channel_free(channel)
                return
            }

            let termial = TerminalSession(channel: channel)

            rc = ssh_channel_change_pty_size(channel, Int32(termial.width), Int32(termial.height))
            if rc != SSH_OK {
                print("ssh_channel_change_pty_size() failed \(rc)")
            }
            
            rc = ssh_channel_request_shell(channel)
            if rc != SSH_OK {
                print("ssh_channel_request_shell() failed \(rc)")
                _ = self.connections[idx].terminalSessions.popLast()
                ssh_channel_close(channel);
                ssh_channel_send_eof(channel);
                ssh_channel_free(channel)
                return
            }

            termial.stdinFnc = stdinFnc
            termial.stdoutFnc = stdoutFnc
            termial.stderrFnc = stderrFnc

            queue.sync {
                self.connections[idx].terminalSessions.append(termial)
            }
        }
    }
    
    func setNewsizeTerminal(session: ssh_session, terminalIdx: Int, newWidth: Int, newHeight: Int) {
        queue.async { [self] in
            guard let idx = connections.firstIndex(where: { $0.session == session }) else {
                return
            }
            guard 0 <= terminalIdx, terminalIdx < connections[idx].terminalSessions.count else {
                return
            }
            guard connections[idx].terminalSessions[terminalIdx].isOpen && ssh_channel_is_open(connections[idx].terminalSessions[terminalIdx].channel) != 0 && ssh_channel_is_eof(connections[idx].terminalSessions[terminalIdx].channel) == 0 else {
                return
            }
            
            connections[idx].terminalSessions[terminalIdx].width = newWidth
            connections[idx].terminalSessions[terminalIdx].height = newHeight
            
            connQueue.async { [self] in
                let rc = ssh_channel_change_pty_size(connections[idx].terminalSessions[terminalIdx].channel, Int32(newWidth), Int32(newHeight))
                if rc != SSH_OK {
                    print("ssh_channel_change_pty_size() failed \(rc)")
                }
            }
        }
    }
    
    func checkTerminal(session: ssh_session, terminalIdx: Int) -> Bool {
        queue.sync {
            guard let idx = connections.firstIndex(where: { $0.session == session }) else {
                return false
            }
            guard 0 <= terminalIdx, terminalIdx < connections[idx].terminalSessions.count else {
                return false
            }
            return connections[idx].terminalSessions[terminalIdx].isOpen && ssh_channel_is_open(connections[idx].terminalSessions[terminalIdx].channel) != 0 && ssh_channel_is_eof(connections[idx].terminalSessions[terminalIdx].channel) == 0
        }
    }
    
    func closeTerminal(session: ssh_session, terminalIdx: Int) {
        queue.async { [self] in
            guard let idx = connections.firstIndex(where: { $0.session == session }) else {
                return
            }
            guard 0 <= terminalIdx, terminalIdx < connections[idx].terminalSessions.count else {
                return
            }

            let channel = connections[idx].terminalSessions[terminalIdx].channel
            if connections[idx].terminalSessions[terminalIdx].isOpen {
                ssh_channel_close(channel);
                ssh_channel_send_eof(channel);
                ssh_channel_free(channel)
            }
            connections[idx].terminalSessions[terminalIdx].stdinFnc = nil
            connections[idx].terminalSessions[terminalIdx].stdoutFnc = nil
            connections[idx].terminalSessions[terminalIdx].stderrFnc = nil
            connections[idx].terminalSessions.remove(at: terminalIdx)
        }
    }
    
    func processDataLoop() {
        for c in connections {
            let logger = c.logger
            for f in c.localForwards {
                var fds = fd_set()
                var maxfd: socket_t = 0
                var timeout = timeval(tv_sec: 0, tv_usec: 0)
                maxfd = max(maxfd, f.serverSockfd)
                __darwin_fd_set(f.serverSockfd, &fds)
                for fd in f.connSockfds.keys {
                    maxfd = max(maxfd, fd)
                    __darwin_fd_set(fd, &fds)
                }
                maxfd += 1
                
                let in_channels = UnsafeMutablePointer<ssh_channel?>.allocate(capacity: f.connSockfds.count+1)
                let out_channels = UnsafeMutablePointer<ssh_channel?>.allocate(capacity: f.connSockfds.count+1)
                for (i, channel) in f.connSockfds.values.enumerated() {
                    in_channels[i] = channel
                }
                in_channels[f.connSockfds.count] = nil
                
                ssh_select(in_channels, out_channels, maxfd, &fds, &timeout)

                for i in 0..<f.connSockfds.count {
                    guard let channel = out_channels[i] else {
                        break
                    }
                    guard let fd = f.connSockfds.first(where: { $0.value == channel })?.key else {
                        continue
                    }
                    print("ssh_channel_read")
                    let nbytes = buffer.withUnsafeMutableBytes { ssh_channel_read_timeout(channel, $0.baseAddress, UInt32(buflen), 0, 0) }
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
                
                for fd in f.connSockfds.keys {
                    if __darwin_fd_isset(fd, &fds) != 0 {
                        print(fd)
                        if let channel = f.connSockfds[fd] {
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

                if __darwin_fd_isset(f.serverSockfd, &fds) != 0 {
                    var cli_addr = sockaddr()
                    var clilen = socklen_t()
                    let newsockfd = accept(f.serverSockfd, &cli_addr, &clilen)
                    print("accept \(newsockfd)")

                    let forwarding_channel = ssh_channel_new(c.session)
                    guard forwarding_channel != nil else {
                        logger("ssh_channel_new() failed")
                        
                        close(newsockfd)
                        continue
                    }

                    let rc = ssh_channel_open_forward(forwarding_channel,
                                                  f.remoteHost, Int32(f.remotePort),
                                                  "127.0.0.1", Int32(f.localPort))
                    guard rc == SSH_OK else {
                        logger("ssh_channel_open_forward() failed \(rc)")

                        ssh_channel_free(forwarding_channel)
                        close(newsockfd)
                        continue
                    }

                    f.connSockfds[newsockfd] = forwarding_channel
                }

                var delChannels: [Int32] = []
                for (fb, channel) in f.connSockfds {
                    if ssh_channel_is_open(channel) != 0, ssh_channel_is_eof(channel) == 0 {
                        continue
                    }
                    print("del \(fb)")
                    delChannels.append(fb)
                    close(fb)
                    ssh_channel_free(channel)
                }
                for fb in delChannels {
                    f.connSockfds.removeValue(forKey: fb)
                }
            }
            for t in c.terminalSessions {
                guard t.isOpen else {
                    continue
                }

                let nbytes = buffer.withUnsafeMutableBytes { ssh_channel_read_timeout(t.channel, $0.baseAddress, UInt32(buflen), 0, 0) }
                if nbytes < 0 {
                    print("ssh_channel_read() error")
                    ssh_channel_close(t.channel);
                    ssh_channel_send_eof(t.channel);
                    ssh_channel_free(t.channel)
                    t.isOpen = false
                }
                else if nbytes > 0 {
                    print("ssh_channel_read() \(nbytes)")
                    t.stdoutFnc?(buffer[0..<Int(nbytes)])
                }
                else {
                    t.stdoutFnc?([])
                }
                if let inputbuffer = t.stdinFnc?(), inputbuffer.count > 0 {
                    let nwritten = ssh_channel_write(t.channel, inputbuffer, UInt32(inputbuffer.count))
                    if nwritten != inputbuffer.count {
                        print("\(nwritten) of \(inputbuffer.count) write, error")
                        ssh_channel_close(t.channel);
                        ssh_channel_send_eof(t.channel);
                        ssh_channel_free(t.channel)
                        t.isOpen = false
                    }
                    else {
                        print("successfly write \(nwritten)")
                    }
                }
                
                if t.isOpen, ssh_channel_is_open(t.channel) == 0, ssh_channel_is_eof(t.channel) != 0 {
                    ssh_channel_close(t.channel);
                    ssh_channel_send_eof(t.channel);
                    ssh_channel_free(t.channel)
                    t.isOpen = false
                }
            }
        }
    }
    
    func verify_knownhost(_ session: ssh_session) -> [UInt8]? {
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
