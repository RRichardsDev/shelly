//
//  TerminalCanvas.swift
//  Shelly
//
//  Custom Canvas-based terminal renderer for pixel-perfect display
//

import SwiftUI
import UIKit

struct TerminalCanvas: View {
    let state: TerminalState
    let colorScheme: ColorScheme

    private var theme: TerminalTheme {
        TerminalThemeManager.shared.currentTheme
    }

    private var backgroundColor: Color {
        theme.background.color
    }

    private var textColor: UIColor {
        theme.foreground.uiColor
    }

    private var bgUIColor: UIColor {
        theme.background.uiColor
    }

    var body: some View {
        SelectableTerminalText(
            text: combinedText,
            textColor: textColor,
            backgroundColor: bgUIColor
        )
        .background(backgroundColor)
    }

    private var combinedText: String {
        if state.lines.isEmpty {
            return "$ "
        }
        return state.lines.map { $0.text }.joined(separator: "\n")
    }
}

// MARK: - UIKit TextView Wrapper for Proper Text Selection

struct SelectableTerminalText: UIViewRepresentable {
    let text: String
    let textColor: UIColor
    let backgroundColor: UIColor

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.alwaysBounceVertical = true
        textView.dataDetectorTypes = []
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        let shouldScroll = isAtBottom(textView)

        // Render ANSI codes to attributed string
        let attributedText = ANSIRenderer.render(text, defaultForeground: textColor, defaultBackground: backgroundColor)
        textView.attributedText = attributedText
        textView.backgroundColor = backgroundColor

        // Auto-scroll to bottom if we were already at bottom
        if shouldScroll {
            scrollToBottom(textView)
        }
    }

    private func isAtBottom(_ textView: UITextView) -> Bool {
        let bottomOffset = textView.contentSize.height - textView.bounds.height + textView.contentInset.bottom
        return textView.contentOffset.y >= bottomOffset - 50 || textView.contentSize.height <= textView.bounds.height
    }

    private func scrollToBottom(_ textView: UITextView) {
        let bottomOffset = CGPoint(
            x: 0,
            y: max(0, textView.contentSize.height - textView.bounds.height + textView.contentInset.bottom)
        )
        textView.setContentOffset(bottomOffset, animated: false)
    }
}

// MARK: - Future Canvas Implementation

/*
 For full terminal emulation with ANSI support, replace the above with a Canvas-based renderer:

 Canvas { context, size in
     let cellWidth: CGFloat = 8.5  // Monospace character width
     let cellHeight: CGFloat = 16  // Line height

     for (rowIndex, line) in state.lines.enumerated() {
         for (colIndex, cell) in line.cells.enumerated() {
             let x = CGFloat(colIndex) * cellWidth
             let y = CGFloat(rowIndex) * cellHeight

             // Draw background if not default
             if let bgColor = cell.backgroundColor {
                 context.fill(
                     Path(CGRect(x: x, y: y, width: cellWidth, height: cellHeight)),
                     with: .color(bgColor)
                 )
             }

             // Draw character
             let text = Text(String(cell.character))
                 .font(.system(size: 14, design: .monospaced))
                 .foregroundColor(cell.foregroundColor ?? textColor)

             context.draw(text, at: CGPoint(x: x, y: y), anchor: .topLeading)
         }
     }

     // Draw cursor
     if state.cursorVisible {
         let cursorX = CGFloat(state.cursorCol) * cellWidth
         let cursorY = CGFloat(state.cursorRow) * cellHeight
         context.fill(
             Path(CGRect(x: cursorX, y: cursorY, width: cellWidth, height: cellHeight)),
             with: .color(.white.opacity(0.7))
         )
     }
 }
 */

#Preview {
    let state = TerminalState()
    state.appendLine("$ ls -la")
    state.appendLine("total 32")
    state.appendLine("drwxr-xr-x  5 user  staff   160 Dec 16 10:00 .")
    state.appendLine("drwxr-xr-x  3 user  staff    96 Dec 15 09:00 ..")
    state.appendLine("-rw-r--r--  1 user  staff  1234 Dec 16 10:00 file.txt")

    return TerminalCanvas(state: state, colorScheme: .dark)
        .frame(height: 300)
}
