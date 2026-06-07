import SwiftUI

struct ContentView: View {
    @StateObject var speechRecognizer = SpeechRecognizer()
    
    // UI Settings
    @AppStorage("fontSize") private var fontSize: Double = 60
    @AppStorage("fontName") private var fontName: String = "System"
    @AppStorage("useOnDevice") private var useOnDevice: Bool = false
    @AppStorage("customVocabulary") private var customVocabulary: String = "Dobre rano"
    
    @AppStorage("smallGapLimit") private var smallGapLimit: Double = 1.0
    @AppStorage("mediumGapLimit") private var mediumGapLimit: Double = 2.5
    @AppStorage("largeGapLimit") private var largeGapLimit: Double = 20.0
    @AppStorage("is24Hour") private var is24Hour: Bool = false
    @AppStorage("hideStatusBar") private var hideStatusBar: Bool = true
    @AppStorage("autoDimTimeout") private var autoDimTimeout: Double = 5.0
    
    @State private var showSettings = false
    @State private var isAtBottom = true
    @State private var isDragging = false
    @State private var lastScrollTime = Date()
    @State private var isBooted = false
    @State private var zoomBaseFontSize: Double = 60
    @State private var isDimmed = false
    
    @State private var editingSegment: TranscriptSegment? = nil
    @State private var editText: String = ""
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.black.ignoresSafeArea()
            
            if isBooted {
                mainTranscriptionView
            } else {
                VStack {
                    Text("BIG")
                        .font(.system(size: 80, weight: .black, design: .rounded))
                        .foregroundColor(.white.opacity(0.1))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            if isDimmed {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .onTapGesture {
                        speechRecognizer.resetDimTimer(timeoutMinutes: autoDimTimeout)
                    }
            }
        }
        .statusBarHidden(hideStatusBar)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation { self.isBooted = true }
                self.zoomBaseFontSize = fontSize
                speechRecognizer.smallGapLimit = smallGapLimit
                speechRecognizer.mediumGapLimit = mediumGapLimit
                speechRecognizer.largeGapLimit = largeGapLimit
                speechRecognizer.useOnDevice = useOnDevice
                speechRecognizer.customVocabulary = customVocabulary
                
                speechRecognizer.onDimStateChange = { shouldDim in
                    withAnimation(.easeInOut(duration: 1.0)) {
                        self.isDimmed = shouldDim
                    }
                }
                
                speechRecognizer.start()
                speechRecognizer.resetDimTimer(timeoutMinutes: autoDimTimeout)
            }
        }
        .sheet(isPresented: $showSettings) { settingsSheet }
        .sheet(item: $editingSegment) { segment in
            EditSegmentView(text: $editText) { newText in
                speechRecognizer.updateSegment(id: segment.id, newText: newText)
                customVocabulary = speechRecognizer.customVocabulary
            }
        }
    }
    
    private var mainTranscriptionView: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if speechRecognizer.segments.isEmpty && speechRecognizer.currentLiveText.isEmpty {
                            Text("Listening...")
                                .font(getFont(size: 30))
                                .foregroundColor(.gray)
                                .padding(.vertical, 40).padding(.leading, 12)
                        }
                        
                        ForEach(speechRecognizer.segments) { segment in
                            renderSegment(segment.text, timestamp: segment.timestamp, gapType: segment.gapType)
                                .id(segment.id)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    editText = segment.text
                                    editingSegment = segment
                                }
                        }
                        
                        if !speechRecognizer.currentLiveText.isEmpty {
                            renderSegment(speechRecognizer.currentLiveText, timestamp: Date(), gapType: speechRecognizer.currentGapType)
                                .id("live_text_anchor")
                        }
                        
                        // This is where auto-scroll and "Latest" will take you
                        Color.clear
                            .frame(height: 20)
                            .id("text_bottom_anchor")
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onChange(of: geo.frame(in: .global).maxY) { maxY in
                                            // Only update isAtBottom based on scrolling if the user is actually dragging.
                                            // This prevents auto-scrolls from accidentally disabling themselves.
                                            if isDragging {
                                                let screenHeight = UIScreen.main.bounds.height
                                                let atBottom = abs(maxY - screenHeight) < 100
                                                if isAtBottom != atBottom {
                                                    isAtBottom = atBottom
                                                }
                                            }
                                        }
                                }
                            )

                        // HUGE spacer that allows pushing all text off the top
                        Spacer()
                            .frame(height: UIScreen.main.bounds.height)
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { _ in isDragging = true; isAtBottom = false; lastScrollTime = Date() }
                        .onEnded { _ in DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { isDragging = false } }
                )
                .highPriorityGesture(
                    MagnificationGesture()
                        .onChanged { v in fontSize = min(max(zoomBaseFontSize * (1.0 + (v - 1.0) * 0.15), 20), 250) }
                        .onEnded { _ in zoomBaseFontSize = fontSize }
                )
                .onChange(of: speechRecognizer.segments.count) { _ in
                    guard !isDragging else { return }
                    if let last = speechRecognizer.segments.last {
                        // If it's a new session, snap the header to the top
                        if last.gapType == .large || last.gapType == .clearScreen {
                            isAtBottom = true
                            withAnimation(.easeOut(duration: 0.4)) { proxy.scrollTo(last.id, anchor: .top) }
                        } else if isAtBottom {
                            scrollToBottom(proxy: proxy)
                        } else if !isAtBottom {
                            // Any new segment brings us back to the action if we aren't actively scrolling
                            isAtBottom = true
                            scrollToBottom(proxy: proxy)
                        }
                    }
                }
                .onChange(of: speechRecognizer.currentLiveText) { newValue in
                    // Only auto-scroll to bottom if we were already at the bottom.
                    // Removed the aggressive 'snap back' from here to prevent high-frequency UI crashes.
                    if isAtBottom && !newValue.isEmpty && !isDragging {
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onChange(of: isAtBottom) { v in if v && !isDragging { scrollToBottom(proxy: proxy) } }
            }
            
            VStack(alignment: .trailing, spacing: 12) {
                if let error = speechRecognizer.errorMessage {
                    Text(error).font(.system(size: 12, weight: .bold)).foregroundColor(.red).padding(8).background(Color.black.opacity(0.7)).cornerRadius(8).padding(.trailing, 10)
                }
                if speechRecognizer.isListening {
                    HStack(spacing: 4) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("LIVE").font(.system(size: 10, weight: .bold)).foregroundColor(.red)
                    }.padding(.trailing, 10).opacity(0.6)
                }
                HStack(spacing: 12) {
                    if !isAtBottom {
                        Button(action: { isAtBottom = true }) {
                            HStack(spacing: 4) { Image(systemName: "chevron.down.circle"); Text("Latest") }.font(.system(size: 14, weight: .medium)).padding(.vertical, 6).padding(.horizontal, 12).foregroundColor(.white.opacity(0.5)).background(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        }.transition(.opacity)
                    }
                    Button(action: { speechRecognizer.clear(); isAtBottom = true }) { Image(systemName: "trash").foregroundColor(.white.opacity(0.3)).font(.system(size: 20)).padding(8) }
                    Button(action: { showSettings.toggle() }) { Image(systemName: "gearshape").foregroundColor(.white.opacity(0.3)).font(.system(size: 20)).padding(8) }
                }
            }.padding(.trailing, 20).padding(.bottom, 20)
        }
    }
    
    @ViewBuilder
    private func renderSegment(_ text: String, timestamp: Date, gapType: TranscriptSegment.GapType) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if gapType == .large || gapType == .clearScreen { timeDivider(timestamp) }
            else if gapType == .medium { Spacer().frame(height: 60) }
            else if gapType == .small { Spacer().frame(height: 12) }
            if !text.isEmpty {
                Text(text).font(getFont(size: CGFloat(fontSize))).foregroundColor(.white).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).padding(.trailing, 12).padding(.vertical, 8)
            }
        }
    }
    
    private func timeDivider(_ date: Date) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = is24Hour ? "HH:mm" : "h:mma"
        let timeString = formatter.string(from: date).lowercased()
        return HStack(spacing: 0) {
            Rectangle().fill(Color.gray.opacity(0.2)).frame(height: 1)
            Text(timeString).font(.system(size: 18, weight: .bold, design: .monospaced)).foregroundColor(.gray.opacity(0.5)).padding(.horizontal, 12)
            Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 40, height: 1)
        }.padding(.vertical, 25).padding(.horizontal, 10)
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) { withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("text_bottom_anchor", anchor: .bottom) } }
    
    private func getFont(size: CGFloat) -> Font {
        if fontName == "Serif" { return .system(size: size, weight: .regular, design: .serif) }
        else if fontName == "Mono" { return .system(size: size, weight: .regular, design: .monospaced) }
        else if fontName == "Round" { return .system(size: size, weight: .regular, design: .rounded) }
        else if fontName != "System" { return .custom(fontName, size: size).weight(.regular) }
        return .system(size: size, weight: .regular)
    }
    
    @ViewBuilder
    private var settingsSheet: some View {
        NavigationView {
            SettingsView(fontSize: $fontSize, fontName: $fontName, useOnDevice: $useOnDevice, smallGap: $smallGapLimit, mediumGap: $mediumGapLimit, largeGap: $largeGapLimit, is24Hour: $is24Hour, hideStatusBar: $hideStatusBar, autoDimTimeout: $autoDimTimeout, speechRecognizer: speechRecognizer)
        }
    }
}

struct VocabularyListView: View {
    @Binding var vocabulary: String
    @State private var newWord: String = ""
    
    var words: [String] {
        vocabulary.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    var body: some View {
        List {
            Section(header: Text("Add New Word")) {
                HStack {
                    TextField("Enter word or phrase", text: $newWord)
                    Button(action: addWord) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            
            Section(header: Text("Current Vocabulary")) {
                if words.isEmpty {
                    Text("No custom words added yet.")
                        .foregroundColor(.gray)
                        .font(.caption)
                } else {
                    ForEach(words, id: \.self) { word in
                        HStack {
                            Text(word)
                            Spacer()
                            Button(action: { deleteWord(named: word) }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red.opacity(0.7))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .onDelete(perform: deleteWords)
                }
            }
        }
        .navigationTitle("Custom Vocabulary")
    }
    
    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        var current = words
        if !current.contains(trimmed) {
            current.append(trimmed)
            vocabulary = current.joined(separator: ", ")
        }
        newWord = ""
    }
    
    private func deleteWord(named word: String) {
        var current = words
        current.removeAll { $0 == word }
        vocabulary = current.joined(separator: ", ")
    }
    
    private func deleteWords(at offsets: IndexSet) {
        var current = words
        current.remove(atOffsets: offsets)
        vocabulary = current.joined(separator: ", ")
    }
}

struct EditSegmentView: View {
    @Binding var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View {
        NavigationView {
            VStack { TextEditor(text: $text).padding().font(.title3) }
            .navigationTitle("Correct Text")
            .navigationBarItems(leading: Button("Cancel") { dismiss() }, trailing: Button("Save") { onSave(text); dismiss() }.bold())
        }
    }
}

struct SettingsView: View {
    @Binding var fontSize: Double
    @Binding var fontName: String
    @Binding var useOnDevice: Bool
    @Binding var smallGap: Double
    @Binding var mediumGap: Double
    @Binding var largeGap: Double
    @Binding var is24Hour: Bool
    @Binding var hideStatusBar: Bool
    @Binding var autoDimTimeout: Double
    @ObservedObject var speechRecognizer: SpeechRecognizer
    @Environment(\.dismiss) var dismiss
    
    private var vocabularyCount: Int {
        speechRecognizer.customVocabulary.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .count
    }
    
    let fonts = ["System", "Serif", "Mono", "Round", "Avenir Next", "Helvetica Neue", "Inter", "Optima", "Charter", "Georgia", "Verdana", "Trebuchet MS", "Futura", "Gill Sans"]
    var body: some View {
        VStack {
            HStack { Text("Settings").font(.headline); Spacer(); Button("Done") { dismiss() } }.padding()
            Form {
                Section(header: Text("Custom Vocabulary")) {
                    NavigationLink(destination: VocabularyListView(vocabulary: $speechRecognizer.customVocabulary)) {
                        HStack {
                            Text("Manage Words")
                            Spacer()
                            Text("\(vocabularyCount)")
                                .foregroundColor(.gray)
                        }
                    }
                }
                Section(header: Text("Silence Gaps (seconds)")) {
                    VStack(alignment: .leading) { Text("New Line: \(smallGap, specifier: "%.1f")s"); Slider(value: $smallGap, in: 0.5...5.0, step: 0.1) }
                        .onChange(of: smallGap) { speechRecognizer.smallGapLimit = $0 }
                    VStack(alignment: .leading) { Text("Big Spacer: \(mediumGap, specifier: "%.1f")s"); Slider(value: $mediumGap, in: 2.0...10.0, step: 0.5) }
                        .onChange(of: mediumGap) { speechRecognizer.mediumGapLimit = $0 }
                    VStack(alignment: .leading) { Text("Time Divider: \(largeGap, specifier: "%.0f")s"); Slider(value: $largeGap, in: 10.0...120.0, step: 5) }
                        .onChange(of: largeGap) { speechRecognizer.largeGapLimit = $0 }
                }
                Section(header: Text("Appearance")) {
                    VStack(alignment: .leading) { Text("Font Size: \(Int(fontSize))").font(.caption); Slider(value: $fontSize, in: 20...200, step: 1) }
                    Picker("Font Type", selection: $fontName) { ForEach(fonts, id: \.self) { font in Text(font).tag(font) } }.pickerStyle(.menu)
                    Toggle("24-Hour Time", isOn: $is24Hour)
                    Toggle("Hide Status Bar", isOn: $hideStatusBar)
                    VStack(alignment: .leading) {
                        Text("Auto-Dim Timeout: \(Int(autoDimTimeout)) min").font(.caption)
                        Slider(value: $autoDimTimeout, in: 0...20, step: 1)
                            .onChange(of: autoDimTimeout) { newValue in
                                speechRecognizer.resetDimTimer(timeoutMinutes: newValue)
                            }
                        if autoDimTimeout == 0 {
                            Text("Always Bright").font(.caption2).foregroundColor(.gray)
                        }
                    }
                }
                Section(header: Text("Engine")) {
                    Toggle("On-Device Mode", isOn: $useOnDevice)
                        .disabled(!speechRecognizer.supportsOnDevice)
                        .onChange(of: useOnDevice) { newValue in
                            speechRecognizer.useOnDevice = newValue
                            speechRecognizer.clear()
                        }
                }
                
                Section(header: Text("Session Info")) {
                    HStack { Text("Uptime"); Spacer(); Text(formatDuration(speechRecognizer.sessionDuration)).foregroundColor(.gray) }
                    HStack { Text("Battery Level"); Spacer(); Text(formatBattery(speechRecognizer.batteryLevel)).foregroundColor(.gray) }
                    HStack { 
                        Text("Remaining (est)"); 
                        Spacer(); 
                        Text(speechRecognizer.estimatedTimeRemaining.map { formatDuration($0) } ?? "Calculating...")
                            .foregroundColor(.gray) 
                    }
                    HStack { Text("Power Impact"); Spacer(); Text(speechRecognizer.powerUsageSummary).foregroundColor(.gray) }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Thermal Status").font(.caption).foregroundColor(.gray)
                        HStack(spacing: 4) {
                            ForEach([ProcessInfo.ThermalState.nominal, .fair, .serious, .critical], id: \.self) { state in
                                thermalPill(state, active: speechRecognizer.thermalState == state)
                            }
                        }
                    }.padding(.vertical, 4)
                }
                }
                .scrollContentBackground(.hidden) 
                }.padding(.top)
                }

                private func thermalPill(_ state: ProcessInfo.ThermalState, active: Bool) -> some View {
                Text(shortThermalName(state))
                .font(.system(size: 10, weight: .bold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(active ? thermalColor(state) : Color.gray.opacity(0.1))
                .foregroundColor(active ? .white : .gray.opacity(0.5))
                .cornerRadius(4)
                }

                private func shortThermalName(_ state: ProcessInfo.ThermalState) -> String {
                switch state {
                case .nominal: return "NOMINAL"
                case .fair: return "FAIR"
                case .serious: return "THROTTLE"
                case .critical: return "CRITICAL"
                @unknown default: return "?"
                }
                }
    
    private func thermalColor(_ state: ProcessInfo.ThermalState) -> Color {
        switch state {
        case .nominal: return .gray
        case .fair: return .yellow
        case .serious: return .orange
        case .critical: return .red
        @unknown default: return .gray
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? "0s"
    }
    
    private func formatBattery(_ level: Float) -> String {
        guard level >= 0 else { return "Unknown" }
        return "\(Int(level * 100))%"
    }
}
