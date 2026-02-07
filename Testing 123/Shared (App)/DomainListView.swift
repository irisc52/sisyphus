//
//  DomainListView.swift
//  Sisyphus
//
//  Add and manage tracked domains
//

import SwiftUI

struct DomainListView: View {
    @ObservedObject var data = SisyphusData.shared
    @State private var newDomain = ""
    @State private var showAddError = false
    
    var body: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                List {
                    Section {
                        HStack(spacing: 12) {
                            TextField("example.com", text: $newDomain)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .onSubmit { addDomain() }
                            
                            Button {
                                addDomain()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.purple)
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowBackground(Color(.systemGray6))
                    } header: {
                        Text("Add domain to track")
                    } footer: {
                        Text("Enter a domain (e.g. tiktok.com, reddit.com) to track scroll time. Resets every 24 hours.")
                    }
                    
                    Section {
                        if data.trackedDomains.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "globe.badge.questionmark")
                                        .font(.system(size: 40))
                                        .foregroundStyle(.secondary)
                                    Text("No domains tracked yet")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Text("Add one above to get started")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 24)
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(data.trackedDomains, id: \.self) { domain in
                                HStack {
                                    Image(systemName: "globe")
                                        .foregroundStyle(.purple)
                                        .frame(width: 24)
                                    Text(domain)
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Button(role: .destructive) {
                                        withAnimation {
                                            data.removeDomain(domain)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.subheadline)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .onDelete(perform: deleteDomains)
                        }
                    } header: {
                        Text("Tracked domains")
                    }
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Domains")
            .alert("Invalid domain", isPresented: $showAddError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Please enter a valid domain (e.g. reddit.com)")
            }
            .onAppear { data.refresh() }
        }
    } else {
            // Fallback on earlier versions
        }
    }
    
    private func addDomain() {
        let trimmed = newDomain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if data.addDomain(trimmed) {
            newDomain = ""
        } else {
            showAddError = true
        }
    }
    
    private func deleteDomains(at offsets: IndexSet) {
        for index in offsets {
            if index < data.trackedDomains.count {
                data.removeDomain(data.trackedDomains[index])
            }
        }
    }
}
