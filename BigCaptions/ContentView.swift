import SwiftUI

struct ContentView: View {
    @StateObject var speechRecognizer = SpeechRecognizer()
    @State private var isRecording = false
    @State private var fontSize: CGFloat = 40
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
                            .font(.title)
                    }
                    .padding()
                    
                    Spacer()
                    
                    Button(action: {
                        isRecording.toggle()
                        if isRecording {
                            speechRecognizer.transcribe()
                        } else {
                            speechRecognizer.stopTranscribing()
                        }
                    }) {
                        Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                            .foregroundColor(isRecording ? .red : .white)
                            .font(.system(size: 44))
                    }
                    .padding()
                }
                
                // Transcription Area
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading) {
                            Text(speechRecognizer.transcript)
                                .font(.system(size: fontSize, weight: .bold))
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
                            // If user drags (scrolls), disable auto-scroll
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
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                    }
                    .padding(.bottom)
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
