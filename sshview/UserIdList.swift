//
//  UserIdentityList.swift
//  sshtest
//
//  Created by rei8 on 2022/04/15.
//

import SwiftUI

struct UserIdList: View {
    @EnvironmentObject var profile: UserProfile
    @EnvironmentObject var target: Targets
    
    var body: some View {
        VStack {
            List {
                ForEach(profile.userid, id: \.id) { idItem in
                    NavigationLink(destination: UserIdDetail(idItem: idItem)) {
                        UserIdRow(idItem: idItem)
                    }
                }
                .onDelete { indexSet in
                    profile.userid.remove(atOffsets: indexSet)
                }
            }
            .navigationBarTitle(Text("User ID"), displayMode: .inline)
            .navigationBarItems(trailing: NavigationLink(value: Dest.addnewid) {
                Image(systemName: "plus")
                    .resizable()
                    .padding(6)
                    .frame(width: 24, height: 24)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .foregroundColor(.white)
            } )
        }
    }
}

struct UserId_Previews: PreviewProvider {
    static var previews: some View {
        UserIdList()
    }
}
