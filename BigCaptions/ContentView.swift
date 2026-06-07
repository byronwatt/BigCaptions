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
    @AppStorage("totalSecondsOfUsage") private var totalSecondsOfUsage: Double = 0
    @AppStorage("totalPercentOfDrain") private var totalPercentOfDrain: Double = 0
    
    @State private var showSettings = false
    @State private var isAtBottom = true
    @State private var isDragging = false
    @State private var isScrolledPastText = false
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
                
                speechRecognizer.onUpdateLifetimeStats = { seconds, drain in
                    self.totalSecondsOfUsage += seconds
                    self.totalPercentOfDrain += max(0, drain)
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
                                            let screenHeight = UIScreen.main.bounds.height
                                            let atBottom = abs(maxY - screenHeight) < 100
                                            if isAtBottom != atBottom {
                                                isAtBottom = atBottom
                                            }
                                            
                                            // Detect if the user has swiped all text off the top of the screen
                                            let pastText = maxY < 0
                                            if isScrolledPastText != pastText {
                                                isScrolledPastText = pastText
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
                        .onChanged { _ in isDragging = true }
                        .onEnded { _ in DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { isDragging = false } }
                )
                .highPriorityGesture(
                    MagnificationGesture()
                        .onChanged { v in fontSize = min(max(zoomBaseFontSize * (1.0 + (v - 1.0) * 0.15), 20), 250) }
                        .onEnded { _ in zoomBaseFontSize = fontSize }
                )
                .onChange(of: speechRecognizer.segments.count) { _ in
                    guard !isDragging else { return }
                    if isAtBottom {
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("text_bottom_anchor", anchor: .bottom) }
                    }
                }
                .onChange(of: speechRecognizer.currentLiveText) { newValue in
                    if isScrolledPastText && !newValue.isEmpty {
                        // User swiped everything away, start a new visual session at the top
                        speechRecognizer.forceSessionMarker()
                        isScrolledPastText = false
                        isAtBottom = false // Force snap to top
                        
                        // Scroll the live text anchor to the top with an animation
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("live_text_anchor", anchor: .top)
                        }
                    } else if isAtBottom && !newValue.isEmpty && !isDragging {
                        // High-frequency live text updates should NOT use animations.
                        proxy.scrollTo("text_bottom_anchor", anchor: .bottom)
                    }
                }
                .onChange(of: isAtBottom) { v in 
                    if v && !isDragging { 
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("text_bottom_anchor", anchor: .bottom) }
                    } 
                }
            }
            
            VStack(alignment: .trailing, spacing: 12) {
                if let error = speechRecognizer.errorMessage {
                    Text(error).font(.system(size: 12, weight: .bold)).foregroundColor(.red).padding(8).background(Color.black.opacity(0.7)).cornerRadius(8).padding(.trailing, 10)
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
    
    @AppStorage("totalSecondsOfUsage") private var totalSecondsOfUsage: Double = 0
    @AppStorage("totalPercentOfDrain") private var totalPercentOfDrain: Double = 0
    
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
                    let totalUptimeMins = Int(round((totalSecondsOfUsage + speechRecognizer.sessionBatteryDuration) / 60.0))
                    let totalDrainPercent = Int(round(totalPercentOfDrain + Double(max(0, speechRecognizer.powerDrain) * 100)))
                    let historicalRemaining = calculateHistoricalRemaining(currentBattery: Double(speechRecognizer.batteryLevel))
                    let maxMins = calculateLifetimeMaxMinutes()
                    let remainingMins = Int(round(historicalRemaining / 60.0))
                    let isCharging = speechRecognizer.batteryState == .charging || speechRecognizer.batteryState == .full

                    HStack { Text("Uptime (On Battery)"); Spacer(); Text("\(totalUptimeMins) min").foregroundColor(.gray) }
                    HStack { Text("Total Power Usage"); Spacer(); Text("\(totalDrainPercent)%").foregroundColor(.gray) }
                    HStack { Text("Battery Level"); Spacer(); Text(formatBattery(speechRecognizer.batteryLevel)).foregroundColor(.gray) }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if isCharging {
                            Text("charging...").font(.caption).foregroundColor(.green)
                        } else {
                            let preciseRemaining = Int(round(historicalRemaining / 60.0))
                            let roundedMax = Int(round(maxMins / 10.0) * 10.0)
                            Text("time left - \(formatHHMM(preciseRemaining)) / \(formatHHMM(roundedMax))")
                                .font(.caption).foregroundColor(.gray)
                        }
                        ProgressView(value: min(max(historicalRemaining / max(maxMins * 60, 1), 0), 1))
                            .tint(isCharging ? .green : thermalColor(speechRecognizer.thermalState))
                    }.padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Power Impact").font(.caption).foregroundColor(.gray)
                        if isCharging {
                            Text("CHARGING").font(.system(size: 13, weight: .bold)).foregroundColor(.green).padding(.vertical, 6)
                        } else {
                            HStack(spacing: 4) {
                                ForEach(["STABLE", "LOW", "MID", "HIGH", "HEAVY"], id: \.self) { bucket in
                                    powerPill(bucket, active: currentPowerBucket(speechRecognizer.powerDrain) == bucket)
                                }
                            }
                        }
                    }.padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Thermal Status").font(.caption).foregroundColor(.gray)
                        HStack(spacing: 4) {
                            ForEach([ProcessInfo.ThermalState.nominal, .fair, .serious, .critical], id: \.self) { state in
                                thermalPill(state, active: speechRecognizer.thermalState == state)
                            }
                        }
                    }.padding(.vertical, 4)
                }
                
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2"))")
                            .foregroundColor(.gray)
                    }
                    HStack {
                        Text("Git Hash")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["GitHash"] as? String ?? "unknown")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.gray)
                    }
                    Link(destination: URL(string: "https://github.com/byronwatt/BigCaptions")!) {
                        HStack {
                            Text("GitHub Repository")
                            Spacer()
                            Image(systemName: "safari")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden) 
        }.padding(.top)
    }

    private func calculateLifetimeMaxMinutes() -> Double {
        let totalS = totalSecondsOfUsage + speechRecognizer.sessionBatteryDuration
        let totalD = totalPercentOfDrain + Double(max(0, speechRecognizer.powerDrain) * 100)
        guard totalD > 0.5 else { return 300 } // Default 5 hours until we have data
        let secondsPerPercent = totalS / totalD
        return (secondsPerPercent * 100) / 60.0
    }

    private func calculateHistoricalRemaining(currentBattery: Double) -> Double {
        guard currentBattery > 0 else { return 0 }
        let totalS = totalSecondsOfUsage + speechRecognizer.sessionBatteryDuration
        let totalD = totalPercentOfDrain + Double(max(0, speechRecognizer.powerDrain) * 100)
        guard totalD > 0.5 else { return 0 }
        let secondsPerPercent = totalS / totalD
        return secondsPerPercent * (currentBattery * 100)
    }

    private func currentPowerBucket(_ drain: Float) -> String {
        let p = drain * 100
        if p <= 0 { return "STABLE" }
        if p <= 3 { return "LOW" }
        if p <= 10 { return "MID" }
        if p <= 20 { return "HIGH" }
        return "HEAVY"
    }

    private func powerPill(_ bucket: String, active: Bool) -> some View {
        Text(bucket)
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(active ? Color.blue : Color.gray.opacity(0.1))
            .foregroundColor(active ? .white : .gray.opacity(0.5))
            .cornerRadius(6)
    }

    private func thermalPill(_ state: ProcessInfo.ThermalState, active: Bool) -> some View {
        Text(shortThermalName(state))
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(active ? thermalColor(state) : Color.gray.opacity(0.1))
            .foregroundColor(active ? .white : .gray.opacity(0.5))
            .cornerRadius(6)
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

    private func formatHHMM(_ minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        return String(format: "%d:%02d", h, m)
    }
}
