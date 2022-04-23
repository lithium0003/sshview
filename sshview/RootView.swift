//
//  RootView.swift
//  sshtest
//
//  Created by rei8 on 2022/04/16.
//

import SwiftUI

struct TabDataItem: Identifiable {
    var id: UUID
    var title: Text
    var image: Image
    var tabView: AnyView
    var childTag: [UUID] = []
}

class TabDataList: ObservableObject {
    @Published var tabIdx: [UUID] = []
    @Published var tabData: [UUID: TabDataItem] = [:]
    @Published var selectedTab = UUID()
    
    init() {
        let id = UUID()
        tabData[id] = TabDataItem(id: id, title: Text("Main"), image: Image(systemName: "gear"), tabView: AnyView(MainView()))
        tabIdx.append(id)
        selectedTab = id
    }
}

struct RootView: View {
    @EnvironmentObject var tabData: TabDataList
    
    var body: some View {
        TabView(selection: $tabData.selectedTab) {
            ForEach(tabData.tabIdx, id: \.self) { idx in
                tabData.tabData[idx]!.tabView
                    .tabItem {
                        tabData.tabData[idx]!.title
                        tabData.tabData[idx]!.image
                    }.tag(idx)
            }
        }
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}
