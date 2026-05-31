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
                                            
                                            // Update isAtBottom state without triggering auto-scroll
                                            if bottomVisible != isAtBottom {
                                                isAtBottom = bottomVisible
                                            }
                                            
                                            // If we are at bottom, make sure autoScroll is synced
                                            if bottomVisible && !autoScroll {
                                                autoScroll = true
                                            }
                                        }
                                }
                            )
                    }
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
                        // User started dragging, pause auto-scroll
                        if autoScroll {
                            autoScroll = false
                        }
                    }
                )
                .onChange(of: speechRecognizer.transcript) { _ in
                    if autoScroll {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: autoScroll) { newValue in
                    if newValue {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
            
            // Bottom Right Controls
            HStack(spacing: 12) {
                // Jump to Latest (Only show if NOT at bottom)
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
            SettingsView(fontSize: $fontSize, fontDesign: $fontDesign)
        }
    }
}

struct SettingsView: View {
    @Binding var fontSize: CGFloat
    @Binding var fontDesign: Font.Design
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Appearance")) {
                    HStack {
                        Text("Size").font(.caption)
                        Slider(value: $fontSize, in: 20...120, step: 1)
                        Text("\(Int(fontSize))").font(.headline)
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
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
