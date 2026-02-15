import SwiftUI
import SwiftMath

struct MathView: UIViewRepresentable {
    let equation: String
    let fontSize: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    final class Coordinator {
        var lastEquation: String?
        var lastFontSize: CGFloat?
        var lastIsDarkMode: Bool?
    }
    
    init(equation: String, fontSize: CGFloat = 20) {
        self.equation = equation
        self.fontSize = fontSize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIView(context: Context) -> MTMathUILabel {
        let label = MTMathUILabel()
        label.textAlignment = .left
        label.fontSize = fontSize
        label.textColor = colorScheme == .dark ? .white : .label
        label.latex = equation
        context.coordinator.lastEquation = equation
        context.coordinator.lastFontSize = fontSize
        context.coordinator.lastIsDarkMode = (colorScheme == .dark)
        // labelMode defaults to .math, which is what we want for pure LaTeX segments
        return label
    }
    
    func updateUIView(_ uiView: MTMathUILabel, context: Context) {
        let isDarkMode = (colorScheme == .dark)

        if context.coordinator.lastEquation != equation {
            uiView.latex = equation
            context.coordinator.lastEquation = equation
        }

        if context.coordinator.lastFontSize != fontSize {
            uiView.fontSize = fontSize
            context.coordinator.lastFontSize = fontSize
        }

        if context.coordinator.lastIsDarkMode != isDarkMode {
            uiView.textColor = isDarkMode ? .white : .label
            context.coordinator.lastIsDarkMode = isDarkMode
        }
        
        // Adjust color based on environment if needed, but MTMathUILabel defaults to black.
        // Uncomment and use the following if MTMathUILabel supports textColor and you want to use it:
        // if let textColor = UIColor(named: "AccentColor") {
        //     uiView.textColor = textColor
        // }
    }
}
