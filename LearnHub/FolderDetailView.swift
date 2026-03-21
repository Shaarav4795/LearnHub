import SwiftUI
import SwiftData

struct FolderDetailView: View {
    @Bindable var folder: StudyFolder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var setToRename: StudySet? = nil
    @State private var isShowingRenameSheet: Bool = false
    @State private var renameTitle: String = ""
    @State private var renameIconId: String = "book"
    
    @State private var isShowingFolderRenameSheet = false
    @State private var folderRenameName = ""
    
    private var filteredStudySets: [StudySet] {
        let sets = (folder.studySets ?? []).sorted { $0.dateCreated > $1.dateCreated }
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return sets }
        return sets.filter { set in
            set.title.range(of: text, options: .caseInsensitive) != nil
            || (set.summary?.range(of: text, options: .caseInsensitive) != nil)
            || (set.originalText.range(of: text, options: .caseInsensitive) != nil)
        }
    }
    
    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground)
                .ignoresSafeArea()
            
            if (folder.studySets ?? []).isEmpty {
                ContentUnavailableView {
                    Label("Empty Folder", systemImage: "folder")
                } description: {
                    Text("Move study sets here to organise them.")
                }
            } else if filteredStudySets.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("No study sets match \"\(searchText)\".")
                }
            } else {
                List {
                    ForEach(filteredStudySets) { set in
                        ZStack {
                            NavigationLink(value: set) {
                                EmptyView()
                            }
                            .opacity(0)
                            
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: set.icon.systemName)
                                        .foregroundColor(.white)
                                        .padding(8)
                                        .background(Circle().fill(themeManager.primaryColor))
                                    
                                    Text(set.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                HStack(alignment: .center, spacing: 8) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "calendar")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                        Text("\(set.dateCreated, style: .date)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    HStack(spacing: 4) {
                                        Image(systemName: set.studySetMode == .topic ? "lightbulb.fill" : "doc.text.fill")
                                            .font(.caption2)
                                        Text(set.studySetMode == .topic ? "Learning Topic" : "From Content")
                                            .font(.caption2)
                                    }
                                    .foregroundColor(set.studySetMode == .topic ? .orange : .blue)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background((set.studySetMode == .topic ? Color.orange : Color.blue).opacity(0.14))
                                    .cornerRadius(8)
                                }
                            }
                            .padding()
                            .glassCard(cornerRadius: 16, strokeOpacity: 0.22)
                            .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .contextMenu {
                            Button {
                                setToRename = set
                                renameTitle = set.title
                                renameIconId = set.iconId
                                isShowingRenameSheet = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            
                            Button {
                                withAnimation {
                                    set.folder = nil
                                }
                            } label: {
                                Label("Remove from Folder", systemImage: "folder.badge.minus")
                            }
                            
                            Button(role: .destructive) {
                                withAnimation {
                                    modelContext.delete(set)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                HapticsManager.shared.playTap()
                                setToRename = set
                                renameTitle = set.title
                                renameIconId = set.iconId
                                isShowingRenameSheet = true
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                            
                            Button {
                                HapticsManager.shared.playTap()
                                withAnimation {
                                    set.folder = nil
                                }
                            } label: {
                                Label("Remove", systemImage: "folder.badge.minus")
                            }
                            .tint(.orange)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                HapticsManager.shared.playTap()
                                withAnimation {
                                    modelContext.delete(set)
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                HapticsManager.shared.playTap()
                                withAnimation {
                                    set.folder = nil
                                }
                            } label: {
                                Label("Remove", systemImage: "folder.badge.minus")
                            }
                            .tint(.orange)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(folder.name)
        .searchable(text: $searchText, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search in folder")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        isShowingFolderRenameSheet = true
                    } label: {
                        Label("Edit Folder", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        withAnimation {
                            modelContext.delete(folder)
                            dismiss()
                        }
                    } label: {
                        Label("Delete Folder", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(PressScaleButtonStyle())
            }
        }
        .sheet(isPresented: $isShowingFolderRenameSheet) {
            CreateFolderView(folderToEdit: folder)
        }
        .sheet(isPresented: $isShowingRenameSheet) {
            if let set = setToRename {
                NavigationStack {
                    Form {
                        TextField("Title", text: $renameTitle)
                        
                        Picker("Icon", selection: $renameIconId) {
                            ForEach(StudySetIcon.allIcons) { icon in
                                Label(icon.name, systemImage: icon.systemName)
                                    .tag(icon.id)
                            }
                        }
                    }
                    .navigationTitle("Rename Study Set")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isShowingRenameSheet = false
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                set.title = renameTitle
                                set.iconId = renameIconId
                                isShowingRenameSheet = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}
