import SwiftUI

struct ContentView: View {
    @StateObject var speechRecognizer = SpeechRecognizer()
    @State private var isRecording = false
    @State private var fontSize: CGFloat = 60
    @State private var autoScroll = true
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                // Header with Controls
                HStack {
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 30))
                    }
                    .padding()
                    .accessibilityLabel("Settings")
                    
                    Spacer()
                    
                    Button(action: {
                        isRecording.toggle()
                        if isRecording {
                            speechRecognizer.transcribe()
                        } else {
                            speechRecognizer.stopTranscribing()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.red.opacity(0.3) : Color.white.opacity(0.1))
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                                .foregroundColor(isRecording ? .red : .white)
                                .font(.system(size: 40, weight: .bold))
                        }
                    }
                    .padding()
                    .accessibilityLabel(isRecording ? "Stop Recording" : "Start Recording")
                }
                
                // Transcription Area
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading) {
                            if speechRecognizer.transcript.isEmpty && !isRecording {
                                Text("Tap the microphone to start...")
                                    .font(.system(size: 30, weight: .medium))
                                    .foregroundColor(.gray)
                                    .padding()
                            }
                            
                            Text(speechRecognizer.transcript)
                                .font(.system(size: fontSize, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .id("bottom")
                                .onChange(of: speechRecognizer.transcript) { _ in
                                    if autoScroll {
                                        withAnimation {
                                            proxy.scrollTo("bottom", anchor: .bottom)
                                        }
                                    }
                                }
                        }
                    }
                    .simultaneousGesture(
                        DragGesture().onChanged { _ in
                            if autoScroll {
                                autoScroll = false
                            }
                        }
                    )
                }
                
                // Floating "Jump to Latest" Button
                if !autoScroll {
                    Button(action: {
                        autoScroll = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Jump to Latest")
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 15)
                        .padding(.horizontal, 30)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(30)
                        .shadow(radius: 5)
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(fontSize: $fontSize)
        }
    }
}

struct SettingsView: View {
    @Binding var fontSize: CGFloat
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Font Size")) {
                    HStack {
                        Text("A").font(.system(size: 14))
                        Slider(value: $fontSize, in: 20...100, step: 1)
                        Text("A").font(.system(size: 30))
                    }
                    Text("Current Size: \(Int(fontSize))")
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
