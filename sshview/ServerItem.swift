//
//  ServerItem.swift
//  sshtest
//
//  Created by rei8 on 2022/04/15.
//

import Foundation

struct ServerItem: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var title: String = ""
    var remoteHost: String = ""
    var remotePort: Int = 22
    var userIDtag: UUID = UUID()
    var proxyServerID: UUID?
    var serverKeyHash: [UInt8] = []
    var serverCommand: String?
    var grepPortFoward: String?
}

class ServerProfile: ObservableObject {
    @Published var servers: [ServerItem] {
        didSet {
            let data = try? JSONEncoder().encode(servers)
            UserDefaults.standard.set(data, forKey: "servers")
        }
    }
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "servers") {
            servers = (try? JSONDecoder().decode([ServerItem].self, from: data)) ?? []
        }
        else {
            servers = []
        }
    }
}
