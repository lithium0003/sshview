//
//  UserIdentityList.swift
//  sshtest
//
//  Created by rei8 on 2022/04/15.
//

import SwiftUI

struct UserIdList: View {
    @EnvironmentObject var profile: UserProfile
    @State private var addMode = false
    @State private var newid = UUID()
    
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
            .navigationBarItems(trailing: Button(action: {
                  // button activates link
                   self.addMode = true
                 } ) {
                 Image(systemName: "plus")
                     .resizable()
                     .padding(6)
                     .frame(width: 24, height: 24)
                     .background(Color.blue)
                     .clipShape(Circle())
                     .foregroundColor(.white)
            } )
            

            // invisible link inside NavigationView for add mode
            NavigationLink(destination: AddNewId(newId: $newid, isShowSubView: $addMode),
                isActive: $addMode) { EmptyView() }
        }
    }
}

struct UserId_Previews: PreviewProvider {
    static var previews: some View {
        UserIdList()
    }
}
