//
//  SisyphusContentView.swift
//  Sisyphus
//
//  Main SwiftUI interface - TabView with Dashboard, Domains, Settings
//

import SwiftUI

struct SisyphusContentView: View {
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
                .tag(0)
            
            DomainListView()
                .tabItem {
                    Label("Domains", systemImage: "globe")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(.purple)
    }
}

#Preview {
    SisyphusContentView()
}
