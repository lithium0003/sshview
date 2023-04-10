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
    @EnvironmentObject var target: Targets

    var body: some View {
        VStack {
            List {
                ForEach(serverProfile.servers, id: \.id) { serveritem in
                    Button(action: {
                        DispatchQueue.main.async {
                            _ = target.showTarget.popLast()
                        }
                        DispatchQueue.main.async {
                            let tag = UUID()
                            let newTab = TabDataItem(id: tag, title: Text(serveritem.title), image: Image(systemName: "server.rack"), tabView: AnyView(ServerConnection(serverTag: serveritem.id, tabTag: tag)))
                            tabData.tabData[tag] = newTab
                            tabData.tabIdx.append(tag)
                            DispatchQueue.main.asyncAfter(deadline: .now()+0.5) {
                                tabData.selectedTab = tag
                            }
                        }
                    }) {
                        ServerRow(serverItem: serveritem)
                    }
                    .contextMenu(menuItems: {
                        let serverIdx = serverProfile.servers.firstIndex(of: serveritem) ?? 0
                        NavigationLink("Edit", value: Dest.editserver(serverIdx, false))
                        NavigationLink("Duplicate", value: Dest.editserver(serverIdx, true))
                    })
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        let serverIdx = serverProfile.servers.firstIndex(of: serveritem) ?? 0
                        NavigationLink("Edit", value: Dest.editserver(serverIdx, false))
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
            .navigationBarItems(trailing: NavigationLink(value: Dest.editserver(-1, false)) {
                Image(systemName: "plus")
                    .resizable()
                    .padding(6)
                    .frame(width: 24, height: 24)
                    .background(Color.green)
                    .clipShape(Circle())
                    .foregroundColor(.white)
            } )
        }
    }
}

struct ServerList_Previews: PreviewProvider {
    static var previews: some View {
        ServerList()
    }
}
