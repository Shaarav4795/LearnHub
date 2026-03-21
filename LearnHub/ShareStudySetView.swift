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
            VStack(spacing: 32) {
                // Header Profile Card
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [Color.accentColor.opacity(0.8), Color.accentColor], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 90, height: 90)
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 10, y: 5)
                        
                        Image(systemName: studySet.icon.systemName)
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 32)

                    VStack(spacing: 6) {
                        Text(studySet.title.isEmpty ? "Untitled Study Set" : studySet.title)
                            .font(.title.weight(.bold))
                            .multilineTextAlignment(.center)
                        
                        Text("Created by \(authorName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                // Features
                VStack(alignment: .leading, spacing: 12) {
                    Text("WHAT HAPPENS NEXT")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    VStack(spacing: 0) {
                        infoRow(title: "Public Visibility", description: "Your study set will be featured on Explore for everyone.", icon: "globe", color: .blue)
                        Divider().padding(.leading, 56)
                        infoRow(title: "AI Moderation & Summary", description: "LearnHub AI ensures content safety and auto-generates a neat summary.", icon: "sparkles", color: .purple)
                        Divider().padding(.leading, 56)
                        infoRow(title: "Help Others Learn", description: "Join the community effort by sharing your knowledge.", icon: "person.2.fill", color: .green)
                    }
                    .glassCard(cornerRadius: 16)
                }
                .padding(.horizontal)

                Spacer(minLength: 20)

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
                    .font(.headline)
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
        .background(OLEDBackground().ignoresSafeArea())
    }

    private func infoRow(title: String, description: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding()
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
                    VStack(spacing: 16) {
                        Text("SHARE LINK")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        Text(shareURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                            .font(.callout.monospaced())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                        HStack(spacing: 12) {
                            ShareLink(
                                item: shareURL,
                                subject: Text("LearnHub study set"),
                                message: Text("Check out this LearnHub study set: \(shareURL.absoluteString)\n\nIf it opens in Safari, tap Open in LearnHub, then Save to My Sets.")
                            ) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .tint(Color.accentColor)

                            Button {
                                UIPasteboard.general.string = shareURL.absoluteString
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    }
                    .padding()
                    .glassCard(cornerRadius: 16)
                    .padding(.horizontal)
                }
                
                if !generatedDescription.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI SUMMARY")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(generatedDescription)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding()
                    .glassCard(cornerRadius: 16)
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
                .controlSize(.large)
                .padding(.top, 8)
            } else {
                VStack(spacing: 24) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color.accentColor)
                    
                    Text(publishStatusText)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OLEDBackground().ignoresSafeArea())
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

