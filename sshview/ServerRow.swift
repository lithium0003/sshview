//
//  ServerRow.swift
//  sshtest
//
//  Created by rei8 on 2022/04/15.
//

import SwiftUI

struct ServerRow: View {
    var serverItem: ServerItem
    
    var body: some View {
        HStack {
            Text(serverItem.title)
            Spacer()
            Text("\(serverItem.remoteHost):\(serverItem.remotePort)")
        }
    }
}

struct ServerRow_Previews: PreviewProvider {
    static var previews: some View {
        ServerRow(serverItem: ServerItem())
    }
}
