# LearnHub

## The Ultimate AI-Powered Study Companion for iOS

LearnHub is an intelligent study aid built with **SwiftUI** and **SwiftData** for iOS 26+. It leverages advanced AI to transform your study materials into interactive learning tools.

**Key Capabilities:**

- **AI Summaries:** Instantly condense long notes and PDFs.
- **Quiz Generator:** Create multiple-choice questions automatically.
- **Flashcards:** Generate study decks from any text or document.
- **Gamification:** Earn XP, track streaks, and unlock achievements.
- **Local AI** Choose the Apple Intelligence AI model for a fully local, offline experience.

Perfect for students looking to optimize their revision with **AI study tools**, **Quizlet-like flashcards**, and **smart quizzes**.

Generate summaries, quizzes, and flashcards from your notes (paste, scan, or import a PDF), track progress with gamification, and keep learning with widgets and notifications.

## Features

- Create study sets from pasted text, scanned pages (OCR), or uploaded PDFs
- Two modes: generate from your content or ask the AI to teach you a new topic
- AI summaries, multiple-choice questions, and flashcards via Groq
- Quiz and flashcard practice flows, plus math rendering (SwiftMath)
- Gamification: levels, XP, streaks, achievements, theming, and guide overlays
- Widgets and notifications to keep study streaks alive
- Choose your model - Apple Intelligence or Groq

## Screenshots

<table>
   <tr>
      <td align="center">
         <p><strong>Home</strong></p>
         <img src="Media/Home%20Screen.png" alt="Home Screen" width="180" />
      </td>
      <td align="center">
         <p><strong>Achievements</strong></p>
         <img src="Media/Achievements%20View.png" alt="Achievements View" width="180" />
      </td>
      <td align="center">
         <p><strong>Flashcards</strong></p>
         <img src="Media/Flashcards%20View.png" alt="Flashcards View" width="180" />
      </td>
   </tr>
   <tr>
      <td align="center">
         <p><strong>Profile</strong></p>
         <img src="Media/Profile%20View.png" alt="Profile View" width="180" />
      </td>
      <td align="center">
         <p><strong>Quiz</strong></p>
         <img src="Media/Quiz%20View.png" alt="Quiz View" width="180" />
      </td>
      <td align="center">
         <p><strong>Summary</strong></p>
         <img src="Media/Summary%20View.png" alt="Summary View" width="180" />
      </td>
   </tr>
   <tr>
      <td align="center">
         <p><strong>Widgets &amp; Icon</strong></p>
         <img src="Media/Widgets%20and%20App%20Icon.png" alt="Widgets and App Icon" width="180" />
      </td>
      <td align="center">
         <p><strong>Model Settings</strong></p>
         <img src="Media/Model%20Selection.png" alt="Model Selection"
         width="180" />
      </td>
      <td></td>
   </tr>
</table>

## Requirements

- macOS with Xcode 26 (or newer) and the latest iOS SDK
- iOS 26.0+ simulator or device
- Groq API key (free/paid), and network access for AI features

## Quick start

```bash
# 1) Clone
git clone https://github.com/Shaarav4795/LearnHub.git
cd LearnHub

# 2) Open in Xcode
xed .
```

In Xcode, select the `LearnHub` scheme and press **Cmd+R** to run on a simulator or device. The widget target (`LearnHubWidgetsExtension`) builds alongside the app.

## Configure Groq (required for live AI, completely free)

1. Get a key: sign up at <https://console.groq.com>, create an API key, and copy it.
2. Input your key in the app's settings menu.

## Configure Explore sharing (optional, free)

To enable the new Explore feed + sharing, follow the Supabase setup guide in `docs/ExploreBackendSetup.md`.

## Using the app

1. Launch and allow notifications if you want streak reminders.
2. Choose your preferred AI model in the app's settings menu
3. Tap **+** on Home to create a study set.

   - **From Content:** paste notes, scan with the camera, or upload a PDF; set counts for questions/flashcards and generate.
   - **Learn Topic:** describe the topic; the AI generates a guided summary, quiz, and flashcards.
4. Open a study set to view tabs:
   - **Summary/Guide:** AI-written overview in paragraph or bullet form.
   - **Questions:** multiple-choice with explanations (and Quiz practice flow).
   - **Flashcards:** swipe through concise Q/A cards.
   - **Tutor:** a smart AI tutor with context of your work to assist you
5. Track progress with levels, XP, streaks, achievements, and theme switching from the profile.
6. Add the LearnHub widget from the Home Screen to keep studying top of mind.

## Development and testing

- Dependencies: SwiftPM only (SwiftMath).
- Run tests: select `LearnHub` and press **Cmd+U**.
- Reset badge counts and notifications are handled in-app; no extra setup needed.

## Repository hygiene

- Standard Xcode/macOS build outputs are ignored via `.gitignore`.
- Licensed under MIT (see `LICENSE`).

## Project structure (high level)

- `LearnHub/` — main app sources (SwiftUI views, AI integration, data models, guides, theming)
- `LearnHubWidgets/` — widget extension
- `LearnHubTests/`, `LearnHubUITests/` — unit and UI tests
