import SwiftUI

struct ContentView: View {
    @StateObject var speechRecognizer = SpeechRecognizer()
    @State private var fontSize: CGFloat = 60
    @State private var fontDesign: Font.Design = .default
    @State private var autoScroll = true
    @State private var showSettings = false
    
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
                            .frame(height: 100) // Extra padding at bottom for buttons
                            .id("bottom")
                    }
                }
                .simultaneousGesture(
                    DragGesture().onChanged { _ in
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
                // When Jump to Latest is pressed, trigger the scroll
                .onChange(of: autoScroll) { newValue in
                    if newValue {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
            
            // Bottom Right Controls
            HStack(spacing: 15) {
                // Jump to Latest (Outline style)
                if !autoScroll {
                    Button(action: {
                        autoScroll = true
                    }) {
                        Text("Jump to Latest")
                            .font(.system(size: 16, weight: .bold))
                            .padding(.vertical, 8)
                            .padding(.horizontal, 15)
                            .foregroundColor(.white.opacity(0.7))
                            .background(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.4), lineWidth: 2)
                            )
                    }
                }
                
                // Settings Icon
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(size: 24))
                        .padding(10)
                }
                .accessibilityLabel("Settings")
            }
            .padding()
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
