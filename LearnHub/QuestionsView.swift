import SwiftUI
import SwiftData
import SwiftUIIntrospect
import ConfettiSwiftUI

struct QuestionsView: View {
    let studySet: StudySet
    @State private var questions: [Question]
    @State private var isShowingQuiz = false
    @StateObject private var themeManager = ThemeManager.shared
    @EnvironmentObject private var guideManager: GuideManager
    @State private var showEditQuestions = false
    @State private var quizConfettiCounter = 0
    
    init(studySet: StudySet) {
        self.studySet = studySet
        _questions = State(initialValue: studySet.questions)
    }
    
    var body: some View {
        List {
            Section {
                Button(action: {
                    HapticsManager.shared.playTap()
                    isShowingQuiz = true
                }) {
                    Label("Start Quiz", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(themeManager.primaryColor.opacity(0.1))
                .buttonStyle(PressScaleButtonStyle())
                .guideTarget(.questionsStartQuiz)
            }

            Section {
                Button(action: {
                    HapticsManager.shared.playTap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showEditQuestions = true
                    }
                }) {
                    Label("Edit Questions", systemImage: "square.and.pencil")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(themeManager.primaryColor.opacity(0.1))
                .buttonStyle(PressScaleButtonStyle())
            }

            ForEach(questions) { question in
                DisclosureGroup(
                    content: {
                        MathTextView(question.answer, fontSize: 15)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    },
                    label: {
                        MathTextView(question.prompt, fontSize: 17)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Question: \(question.prompt)")
                    }
                )
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(8)
        .introspect(.scrollView, on: .iOS(.v17)) { scrollView in
            scrollView.keyboardDismissMode = .interactive
            scrollView.delaysContentTouches = false
        }
        .navigationTitle("Study Questions")
        .sheet(isPresented: $isShowingQuiz) {
            NavigationStack {
                QuizView(studySet: studySet)
            }
        }
        .fullScreenCover(isPresented: $showEditQuestions) {
            NavigationStack {
                QuestionsEditorView(studySet: studySet) {
                    questions = studySet.questions
                }
            }
        }
        .onChange(of: isShowingQuiz) { _, newValue in
            // When the quiz sheet closes, advance the guide step and refresh questions.
            if newValue == false, guideManager.currentStep == .exploreQuiz {
                guideManager.advanceAfterVisitedQuiz()
            }
            if newValue == false {
                questions = studySet.questions
                quizConfettiCounter += 1
            }
        }
        .confettiCannon(counter: $quizConfettiCounter)
    }
}
