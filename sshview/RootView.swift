//
//  RootView.swift
//  sshtest
//
//  Created by rei8 on 2022/04/16.
//

import SwiftUI

struct TabDataItem: Identifiable {
    var id = UUID()
    var title: Text
    var image: Image
    var tabView: AnyView
    var childTag: [UUID] = []
}

class TabDataList: ObservableObject {
    @Published var tabData: [TabDataItem]
    @Published var selectedTab = UUID()
    
    init() {
        tabData = [
            TabDataItem(title: Text("Main"), image: Image(systemName: "gear"), tabView: AnyView(MainView())),
        ]
        selectedTab = tabData[0].id
    }
}

struct RootView: View {
    @EnvironmentObject var tabData: TabDataList
    
    var body: some View {
        TabView(selection: $tabData.selectedTab) {
            ForEach(tabData.tabData) { tabItem in
                tabItem.tabView
                    .tabItem {
                        tabItem.title
                        tabItem.image
                    }.tag(tabItem.id)
            }
        }
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}
