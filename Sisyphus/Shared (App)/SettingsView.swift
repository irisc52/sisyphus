//
//  SettingsView.swift
//  Sisyphus
//
//  Time limit and app settings
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var data = SisyphusData.shared

    private let timeOptions = [5, 10, 15, 30, 45, 60, 90, 120]

    private var scrollLimitBinding: Binding<Int> {
        Binding(
            get: {
                let m = data.scrollLimitMinutes
                return timeOptions.contains(m) ? m : 30
            },
            set: { data.scrollLimitMinutes = $0 }
        )
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                Form {
                    Section {
                        Picker("Daily scroll limit", selection: scrollLimitBinding) {
                            ForEach(timeOptions, id: \.self) { mins in
                                Text("\(mins) min").tag(mins)
                            }
                        }
                        .pickerStyle(.menu)
                    } header: {
                        Text("Limit")
                    } footer: {
                        Text("When exceeded on a tracked domain, heavy scroll mode (friction + grayscale) activates. Resets every 24 hours.")
                    }
                    
                    Section {
                        HStack {
                            Label("Safari Extension", systemImage: "safari")
                            Spacer()
                            Text("Required")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Link(destination: URL(string: "https://support.apple.com/guide/iphone/add-extensions-to-safari-iphab0432bf6/ios")!) {
                            HStack {
                                Label("How to enable", systemImage: "questionmark.circle")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Extension")
                    } footer: {
                        Text("Enable Sisyphus in Safari settings to track scroll time on your selected domains.")
                    }
                    
                    Section {
                        HStack {
                            Text("Version")
                            Spacer()
                            Text("1.0")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("About")
                    }
                }
                .navigationTitle("Settings")
                .onAppear {
                    data.refresh()
                    if data.scrollLimitMinutes == 0 {
                        data.scrollLimitMinutes = 30
                    }
                }
            }
        } else {
            // Fallback on earlier versions
        }
    }
}
