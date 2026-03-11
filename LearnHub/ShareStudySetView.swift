import SwiftUI
import SwiftData
import UIKit

struct ShareStudySetView: View {
    let studySet: StudySet
    let authorName: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isPublishing = false
    @State private var publishError: String?
    @State private var publishStatusText: String = ""
    @State private var successSnapshotID: String?
    @State private var successShortCode: String?
    @State private var successShareURL: URL?
    @State private var generatedDescription: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                if isPublishing || successSnapshotID != nil || publishError != nil {
                    publishingView
                } else {
                    mainView
                }
            }
            .navigationTitle("Share to Explore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if successSnapshotID == nil {
                        Button {
                            dismiss()
                        } label: {
                            // iOS native close icon
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                        .disabled(isPublishing)
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    if successSnapshotID != nil {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .interactiveDismissDisabled(isPublishing)
    }

    private var mainView: some View {
        ScrollView {
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: studySet.icon.systemName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.top, 24)

                VStack(spacing: 8) {
                    Text(studySet.title.isEmpty ? "Untitled Study Set" : studySet.title)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    
                    Text("by \(authorName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                VStack(spacing: 12) {
                    infoRow(title: "Public Visibility", description: "Visible to everyone on Explore.", icon: "globe")
                    infoRow(title: "AI Moderation", description: "Our AI checks content and creates a short summary.", icon: "wand.and.stars")
                    infoRow(title: "Community Growth", description: "Help others learn from your study material.", icon: "person.2.fill")
                }
                .padding(.horizontal)

                Spacer(minLength: 40)

                Button {
                    HapticsManager.shared.playTap()
                    withAnimation {
                        isPublishing = true
                    }
                    Task { await publish() }
                } label: {
                    HStack {
                        Image(systemName: "paperplane.fill")
                        Text("Share to Explore")
                            .fontWeight(.bold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.accentColor.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }

    private func infoRow(title: String, description: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color.accentColor.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var publishingView: some View {
        VStack(spacing: 24) {
            Spacer()

            if successSnapshotID != nil {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                    .symbolEffect(.bounce, value: successSnapshotID)
                
                Text("Shared Successfully!")
                    .font(.title2.bold())
                
                Text("Your study set is now live on Explore.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let shortCode = successShortCode,
                   let shareURL = successShareURL {
                    VStack(spacing: 10) {
                        Text("Share Link")
                            .font(.caption.bold())
                            .foregroundStyle(Color.accentColor)

                        Text("learnhub.shaarav.xyz/share/\(shortCode)")
                            .font(.footnote.monospaced())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 6)

                        HStack(spacing: 10) {
                            ShareLink(
                                item: shareURL,
                                subject: Text("LearnHub study set"),
                                message: Text("Check out this LearnHub study set: \(shareURL.absoluteString)\n\nIf it opens in Safari, tap Open in LearnHub, then Save to My Sets.")
                            ) {
                                Label("Share Link", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                UIPasteboard.general.string = shareURL.absoluteString
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal)

                }
                
                if !generatedDescription.isEmpty {
                    VStack(spacing: 8) {
                        Text("AI Summary")
                            .font(.caption.bold())
                            .foregroundStyle(Color.accentColor)
                        Text(generatedDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                    .padding()
                    .background(Color.accentColor.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
            } else if let error = publishError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)
                
                Text("Sharing Failed")
                    .font(.title3.bold())
                
                Text(error)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                
                Button("Try Again") {
                    Task { await publish() }
                }
                .buttonStyle(.bordered)
            } else {
                ProgressView()
                    .scaleEffect(1.5)
                
                Text(publishStatusText)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
            
            Spacer()
        }
        .padding()
    }

    private func publish() async {
        publishError = nil
        publishStatusText = "Checking content safety..."

        let moderation = await ExploreModerationService.shared.moderate(studySet: studySet)
        generatedDescription = moderation.generatedDescription
        guard moderation.approved else {
            isPublishing = false
            publishStatusText = ""
            publishError = "Moderation Failed: \(moderation.reason)"
            HapticsManager.shared.error()
            return
        }

        publishStatusText = "Broadcasting to LearnHub..."

        do {
            let result = try await ExploreService.shared.publish(
                studySet: studySet,
                authorName: authorName,
                generatedDescription: moderation.generatedDescription,
                tags: moderation.tags
            )

            switch result {
            case .published(let snapshotID, let shortCode), .alreadyPublished(let snapshotID, let shortCode):
                studySet.sharedSnapshotId = snapshotID
                successSnapshotID = snapshotID
                successShortCode = shortCode
                successShareURL = ExploreService.shared.shareURL(shortCode: shortCode)
            }

            try modelContext.save()
            HapticsManager.shared.success()
            isPublishing = false
        } catch {
            isPublishing = false
            publishStatusText = ""
            publishError = error.localizedDescription
            HapticsManager.shared.error()
        }
    }
}

