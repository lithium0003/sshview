//
//  UserIdItem.swift
//  sshtest
//
//  Created by rei8 on 2022/04/15.
//

import Foundation

struct UserIdItem: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String = ""
    var userName: String = ""
    var b64_prrvateKey: String = ""
    var passphrease: String = ""
}

class UserProfile: ObservableObject {
    @Published var userid: [UserIdItem] {
        didSet {
            let data = try? JSONEncoder().encode(userid)
            UserDefaults.standard.set(data, forKey: "userid")
        }
    }
    
    init() {
        if let data = UserDefaults.standard.data(forKey: "userid") {
            userid = (try? JSONDecoder().decode([UserIdItem].self, from: data)) ?? []
        }
        else {
            userid = []
        }
    }
}
