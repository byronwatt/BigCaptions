import SwiftUI

struct ContentView: View {
    @StateObject var speechRecognizer = SpeechRecognizer()
    @AppStorage("fontSize") private var fontSize: Double = 60
    @AppStorage("fontName") private var fontName: String = "System"
    @State private var autoScroll = true
    @State private var showSettings = false
    @State private var isAtBottom = true
    @State private var isDragging = false
    @State private var lastScrollTime = Date()
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.ignoresSafeArea()
            
            // Transcription Area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if speechRecognizer.transcript.isEmpty {
                            Text("Listening...")
                                .font(getFont(size: 30))
                                .foregroundColor(.gray)
                                .padding(.vertical)
                                .padding(.leading, 8)
                        }
                        
                        Text(speechRecognizer.transcript)
                            .font(getFont(size: CGFloat(fontSize)))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical)
                            .padding(.leading, 8)
                            .padding(.trailing, 8)
                        
                        // Robust bottom anchor for scrolling
                        Rectangle()
                            .fill(Color.clear)
                            .frame(height: 120) 
                            .id("bottom_anchor")
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onChange(of: geo.frame(in: .global).maxY) { maxY in
                                            let screenHeight = UIScreen.main.bounds.height
                                            let bottomVisible = maxY <= screenHeight + 150
                                            
                                            if isAtBottom != bottomVisible {
                                                isAtBottom = bottomVisible
                                            }
                                            
                                            // Resume auto-scroll if user returned to bottom manually
                                            if bottomVisible && !autoScroll && !isDragging && Date().timeIntervalSince(lastScrollTime) > 1.0 {
                                                autoScroll = true
                                            }
                                        }
                                }
                            )
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { _ in
                            isDragging = true
                            autoScroll = false
                            lastScrollTime = Date()
                        }
                        .onEnded { _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                isDragging = false
                                lastScrollTime = Date()
                            }
                        }
                )
                .onChange(of: speechRecognizer.transcript) { _ in
                    if autoScroll && !isDragging {
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onChange(of: autoScroll) { newValue in
                    if newValue {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
            
            // Bottom Right Controls
            VStack(alignment: .trailing, spacing: 12) {
                // Error Message (if any)
                if let error = speechRecognizer.errorMessage {
                    Text(error)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                        .padding(8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding(.trailing, 10)
                }

                // Listening Indicator
                if speechRecognizer.isListening {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red)
                    }
                    .padding(.trailing, 10)
                    .opacity(0.6)
                }

                HStack(spacing: 12) {
                    // Jump to Latest
                    if !isAtBottom {
                        Button(action: {
                            autoScroll = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.down.circle")
                                Text("Latest")
                            }
                            .font(.system(size: 14, weight: .medium))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .foregroundColor(.white.opacity(0.5))
                            .background(
                                Capsule()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .transition(.opacity)
                    }
                    
                    // Clear Button (Trash icon)
                    Button(action: {
                        speechRecognizer.clear()
                        autoScroll = true
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.white.opacity(0.3))
                            .font(.system(size: 20))
                            .padding(8)
                    }
                    .accessibilityLabel("Clear Text")
                    
                    // Settings Icon
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.white.opacity(0.3))
                            .font(.system(size: 20))
                            .padding(8)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 20)
        }
        .onAppear {
            speechRecognizer.transcribe()
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.3)) {
            proxy.scrollTo("bottom_anchor", anchor: .bottom)
        }
    }
    
    private func getFont(size: CGFloat) -> Font {
        if fontName == "System" {
            return .system(size: size, weight: .regular)
        } else if fontName == "Serif" {
            return .system(size: size, weight: .regular, design: .serif)
        } else if fontName == "Mono" {
            return .system(size: size, weight: .regular, design: .monospaced)
        } else if fontName == "Round" {
            return .system(size: size, weight: .regular, design: .rounded)
        } else {
            return .custom(fontName, size: size).weight(.regular)
        }
    }
    
    @ViewBuilder
    private var settingsSheet: some View {
        if #available(iOS 16.4, *) {
            SettingsView(fontSize: $fontSize, fontName: $fontName, debugMode: $speechRecognizer.debugMode)
                .presentationDetents([.medium, .fraction(0.6)])
                .presentationBackground(.thinMaterial)
        } else {
            SettingsView(fontSize: $fontSize, fontName: $fontName, debugMode: $speechRecognizer.debugMode)
                .presentationDetents([.medium, .fraction(0.6)])
        }
    }
}

struct SettingsView: View {
    @Binding var fontSize: Double
    @Binding var fontName: String
    @Binding var debugMode: Bool
    @Environment(\.dismiss) var dismiss
    
    let fonts = [
        "System", "Serif", "Mono", "Round",
        "Avenir Next", "Helvetica Neue", "Inter",
        "Optima", "Charter", "Georgia", "Verdana", 
        "Trebuchet MS", "Futura", "Gill Sans"
    ]
    
    var body: some View {
        VStack {
            HStack {
                Text("Settings")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            
            Form {
                Section(header: Text("Appearance")) {
                    VStack(alignment: .leading) {
                        Text("Font Size: \(Int(fontSize))").font(.caption)
                        Slider(value: $fontSize, in: 20...120, step: 1)
                    }
                    
                    Picker("Font Type", selection: $fontName) {
                        ForEach(fonts, id: \.self) { font in
                            Text(font).tag(font)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section(header: Text("Advanced")) {
                    Toggle("Debug Word Timing", isOn: $debugMode)
                }
            }
            .scrollContentBackground(.hidden) 
        }
        .padding(.top)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
