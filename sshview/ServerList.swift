//
//  ServerList.swift
//  sshtest
//
//  Created by rei8 on 2022/04/15.
//

import SwiftUI

struct ServerList: View {
    @EnvironmentObject var serverProfile: ServerProfile
    @EnvironmentObject var userProfile: UserProfile
    @EnvironmentObject var tabData: TabDataList
    @State private var addMode = false
    @State private var editMode = false
    @State private var serverIdx = 0
    @Binding var isShowing: Bool

    var body: some View {
        VStack {
            List {
                ForEach(serverProfile.servers, id: \.id) { serveritem in
                    Button(action: {
                        DispatchQueue.main.async {
                            isShowing = false
                        }
                        DispatchQueue.main.async {
                            let newTab = TabDataItem(title: Text(serveritem.title), image: Image(systemName: "server.rack"), tabView: AnyView(ServerConnection(serverTag: serveritem.id)))
                            tabData.tabData.append(newTab)
                            DispatchQueue.main.asyncAfter(deadline: .now()+0.5) {
                                tabData.selectedTab = newTab.id
                            }
                        }
                    }) {
                        ServerRow(serverItem: serveritem)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button("Edit") {
                            serverIdx = serverProfile.servers.firstIndex(of: serveritem) ?? 0
                            editMode = true
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete") {
                            guard let idx = serverProfile.servers.firstIndex(of: serveritem) else {
                                return
                            }
                            serverProfile.servers.remove(at: idx)
                        }
                        .tint(.red)
                    }
                }
            }
            .navigationBarTitle(Text("Server list"), displayMode: .inline)
            .navigationBarItems(trailing: Button(action: {
                  // button activates link
                   self.addMode = true
                 } ) {
                 Image(systemName: "plus")
                     .resizable()
                     .padding(6)
                     .frame(width: 24, height: 24)
                     .background(Color.green)
                     .clipShape(Circle())
                     .foregroundColor(.white)
            } )
            
            // invisible link inside NavigationView for add mode
            NavigationLink(destination: AddNewServer(isShowCurrentView: $addMode),
                isActive: $addMode) { EmptyView() }
            NavigationLink(destination: EditServer(serverIdx: serverIdx, isShowCurrentView: $editMode),
                           isActive: $editMode) { EmptyView() }
        }
    }
}

struct ServerList_Previews: PreviewProvider {
    @State static var isShowing = false
    
    static var previews: some View {
        ServerList(isShowing: $isShowing)
    }
}
