import SwiftUI

struct ContentView: View {
    @StateObject var speechRecognizer = SpeechRecognizer()
    @State private var fontSize: CGFloat = 60
    @State private var fontDesign: Font.Design = .default
    @State private var autoScroll = true
    @State private var showSettings = false
    @State private var isAtBottom = true
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.ignoresSafeArea()
            
            // Transcription Area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading) {
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
                                            // Detect if we are close to the bottom
                                            let bottomVisible = maxY <= screenHeight + 150
                                            
                                            // Update isAtBottom state
                                            if isAtBottom != bottomVisible {
                                                isAtBottom = bottomVisible
                                                // If we've manually returned to the bottom, resume auto-scroll
                                                if bottomVisible {
                                                    autoScroll = true
                                                }
                                            }
                                        }
                                }
                            )
                    }
                }
                .simultaneousGesture(
                    // Using a simpler gesture to detect manual scroll away from bottom
                    DragGesture().onChanged { _ in
                        if autoScroll {
                            autoScroll = false
                        }
                    }
                )
                .onChange(of: speechRecognizer.transcript) { _ in
                    // Smooth auto-scroll when new text arrives
                    if autoScroll {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: autoScroll) { newValue in
                    // If user manually taps "Latest"
                    if newValue {
                        withAnimation(.spring()) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
            
            // Bottom Right Controls
            HStack(spacing: 12) {
                // Jump to Latest (Subtle Outline style)
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
                
                // Settings Icon (Very subtle)
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.white.opacity(0.3))
                        .font(.system(size: 20))
                        .padding(8)
                }
                .accessibilityLabel("Settings")
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
