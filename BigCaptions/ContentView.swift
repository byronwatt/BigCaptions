import SwiftUI

struct ContentView: View {
    @StateObject var speechRecognizer = SpeechRecognizer()
    @State private var fontSize: CGFloat = 60
    @State private var fontDesign: Font.Design = .default
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
                                .font(.system(size: 30, weight: .medium, design: fontDesign))
                                .foregroundColor(.gray)
                                .padding()
                        }
                        
                        Text(speechRecognizer.transcript)
                            .font(.system(size: fontSize, weight: .semibold, design: fontDesign))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        
                        // Invisible element to scroll to
                        Color.clear
                            .frame(height: 100) 
                            .id("bottom")
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onChange(of: geo.frame(in: .global).maxY) { maxY in
                                            let screenHeight = UIScreen.main.bounds.height
                                            let bottomVisible = maxY <= screenHeight + 120
                                            
                                            // Handle the "Is At Bottom" state with logic for manual scrolling
                                            if bottomVisible != isAtBottom {
                                                isAtBottom = bottomVisible
                                            }
                                            
                                            // Auto-resume logic:
                                            // If we hit the bottom AND we're not touching the screen AND enough time has passed
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
                            // Delay allowing auto-scroll to resume after a flick
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                isDragging = false
                                lastScrollTime = Date()
                            }
                        }
                )
                .onChange(of: speechRecognizer.transcript) { _ in
                    // Only perform the auto-scroll if we are in auto mode and not being touched
                    if autoScroll && !isDragging {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: autoScroll) { newValue in
                    // If user manually taps "Latest" button
                    if newValue {
                        withAnimation(.spring()) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
            
            // Bottom Right Controls
            VStack(alignment: .trailing, spacing: 12) {
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
                    // Jump to Latest Button (Subtle Outline)
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
    
    @ViewBuilder
    private var settingsSheet: some View {
        if #available(iOS 16.4, *) {
            SettingsView(fontSize: $fontSize, fontDesign: $fontDesign)
                .presentationDetents([.medium, .fraction(0.3)])
                .presentationBackground(.thinMaterial)
        } else {
            SettingsView(fontSize: $fontSize, fontDesign: $fontDesign)
                .presentationDetents([.medium, .fraction(0.3)])
        }
    }
}

struct SettingsView: View {
    @Binding var fontSize: CGFloat
    @Binding var fontDesign: Font.Design
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            HStack {
                Text("Appearance")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding()
            
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Font Size: \(Int(fontSize))").font(.caption)
                        Slider(value: $fontSize, in: 20...120, step: 1)
                    }
                    
                    Picker("Font Style", selection: $fontDesign) {
                        Text("Default").tag(Font.Design.default)
                        Text("Serif").tag(Font.Design.serif)
                        Text("Monospaced").tag(Font.Design.monospaced)
                        Text("Rounded").tag(Font.Design.rounded)
                    }
                    .pickerStyle(.segmented)
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
