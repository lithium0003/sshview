//
//  UserIdRow.swift
//  sshtest
//
//  Created by rei8 on 2022/04/15.
//

import SwiftUI

struct UserIdRow: View {
    var idItem: UserIdItem
    
    var body: some View {
        HStack {
            Text(idItem.title)
            Spacer()
        }
    }
}

struct UserIdRow_Previews: PreviewProvider {
    static var previews: some View {
        UserIdRow(idItem: UserIdItem(title: "test"))
    }
}
