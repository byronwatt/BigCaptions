import Foundation
import AVFoundation
import Speech
import SwiftUI

/// Represents a distinct chunk of transcription with metadata about the preceding pause.
struct TranscriptSegment: Identifiable {
    enum GapType {
        case none
        case small    // New line
        case medium  // New line + spacer
        case large   // Time divider
        case clearScreen // Manual clear
    }
    
    let id = UUID()
    var text: String
    let timestamp: Date
    let gapType: GapType
}

/// A highly robust helper for speech-to-text with stable history accumulation.
class SpeechRecognizer: ObservableObject {
    @Published var segments: [TranscriptSegment] = []
    @Published var currentLiveText: String = ""
    @Published var currentGapType: TranscriptSegment.GapType = .none
    
    @Published var isListening: Bool = false
    @Published var isInitializing: Bool = false
    @Published var debugMode: Bool = false
    @Published var useOnDevice: Bool = false
    @Published var errorMessage: String? = nil
    @Published var supportsOnDevice: Bool = false
    
    // Thresholds for segmenting based on silence
    @Published var smallGapLimit: Double = 1.0
    @Published var mediumGapLimit: Double = 2.5
    @Published var largeGapLimit: Double = 20.0
    
    @Published var customVocabulary: String = ""
    @Published var sessionDuration: Double = 0
    @Published var batteryLevel: Float = -1.0
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    private var startBatteryLevel: Float = -1.0
    
    var powerUsageSummary: String {
        guard startBatteryLevel > 0 && batteryLevel > 0 else { return "Calculating..." }
        let drain = startBatteryLevel - batteryLevel
        if drain <= 0 { return "Stable" }
        let drainPercent = Int(drain * 100)
        return "-\(drainPercent)% this session"
    }

    var estimatedTimeRemaining: Double? {
        let elapsed = Date().timeIntervalSince(sessionStartTime)
        let drain = startBatteryLevel - batteryLevel
        // Wait for at least 1% drain or 2 mins for a stable estimate
        guard drain >= 0.01 || elapsed > 120 else { return nil }
        guard drain > 0 else { return nil }
        return Double(batteryLevel) / Double(drain) * elapsed
    }

    // Callback to update UI dim state
    var onDimStateChange: ((Bool) -> Void)?
    private var dimTimer: Timer?
    private var dimTimeoutMinutes: Double = 0
    
    private var recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    private var lastSegmentEndTime: Date?
    private var silenceTimer: Timer?
    private var progressTimer: Timer?
    private var isTaskRefreshing: Bool = false
    private var sessionStartTime: Date = Date()
    
    init() {
        // Keep empty to avoid main-thread blocking during app launch
    }
    
    func start() {
        guard !isListening && !isInitializing else { return }
        
        DispatchQueue.main.async {
            self.isInitializing = true
            self.errorMessage = nil
        }
        
        Task {
            // 1. Initialize recognizer on a background task
            let newRecognizer = SFSpeechRecognizer()
            let supportsLocal = newRecognizer?.supportsOnDeviceRecognition ?? false
            
            // 2. Request permissions
            let authStatus = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
            let recordPermission = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            
            DispatchQueue.main.async {
                self.recognizer = newRecognizer
                self.supportsOnDevice = supportsLocal
                self.isInitializing = false
                
                if authStatus == .authorized && recordPermission {
                    self.transcribe()
                } else {
                    self.showError("Permissions denied. Check Settings.")
                }
            }
        }
    }
    
    func transcribe() {
        guard !isListening && !isTaskRefreshing else { return }
        
        do {
            teardownAudio()
            
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            audioEngine = AVAudioEngine()
            startNewTask()
            
            let inputNode = audioEngine!.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer, _) in
                self?.request?.append(buffer)
            }
            
            audioEngine!.prepare()
            try audioEngine!.start()
            
            UIDevice.current.isBatteryMonitoringEnabled = true
            
            DispatchQueue.main.async {
                self.isListening = true
                self.errorMessage = nil
                self.sessionStartTime = Date()
                self.startBatteryLevel = UIDevice.current.batteryLevel
                self.startProgressTimer()
                UIApplication.shared.isIdleTimerDisabled = true
            }
        } catch {
            showError("Mic failed: \(error.localizedDescription)")
            teardownAudio()
        }
    }
    
    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.sessionDuration = Date().timeIntervalSince(self.sessionStartTime)
                self.batteryLevel = UIDevice.current.batteryLevel
                self.thermalState = ProcessInfo.processInfo.thermalState
            }
        }
    }
    
    func startNewTask() {
        task?.cancel()
        task = nil
        currentLiveText = "" 
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        
        if #available(iOS 13.0, *) {
            if recognizer?.supportsOnDeviceRecognition ?? false {
                request?.requiresOnDeviceRecognition = useOnDevice
            }
        }
        
        if #available(iOS 16.0, *) { request?.addsPunctuation = true }
        
        let vocab = customVocabulary.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        request?.contextualStrings = vocab.isEmpty ? ["Dobre rano"] : vocab
        
        guard let request = request, let recognizer = recognizer else { return }
        
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            if let result = result {
                self.handleResult(result.bestTranscription.formattedString)
                self.resetSilenceTimer()
            }
            if let error = error {
                let nsError = error as NSError
                if self.isTaskRefreshing { return }
                // Codes 203/1110 often mean the server cut us off; just restart.
                if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 203 || nsError.code == 1110 {
                    self.lockInAndRestart()
                }
            }
        }
    }
    
    private func handleResult(_ text: String) {
        DispatchQueue.main.async {
            // New speech always wakes the screen
            self.wakeAndResetDimTimer()
            
            if self.currentLiveText.isEmpty && !text.isEmpty {
                let now = Date()
                let gapDuration = self.lastSegmentEndTime.map { now.timeIntervalSince($0) }
                
                if gapDuration == nil || gapDuration! > self.largeGapLimit {
                    self.currentGapType = .large
                } else if gapDuration! > self.mediumGapLimit {
                    self.currentGapType = .medium
                } else if gapDuration! > self.smallGapLimit {
                    self.currentGapType = .small
                } else {
                    self.currentGapType = .none
                }
            }
            self.currentLiveText = text
        }
    }
    
    private func resetSilenceTimer() {
        DispatchQueue.main.async {
            self.silenceTimer?.invalidate()
            
            // In On-Device mode, we don't need to force restarts as aggressively
            // as server mode (which has a 60s limit). However, a long pause (5s+)
            // is still a good time to "lock in" and reset the engine's internal 
            // state to maintain accuracy over long sessions.
            let timeout = self.useOnDevice ? 5.0 : self.smallGapLimit
            
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                self?.lockInAndRestart()
            }
        }
    }
    
    private func lockInAndRestart() {
        DispatchQueue.main.async {
            if self.isTaskRefreshing { return }
            if !self.currentLiveText.isEmpty {
                let newSegment = TranscriptSegment(text: self.currentLiveText, timestamp: Date(), gapType: self.currentGapType)
                self.segments.append(newSegment)
                self.lastSegmentEndTime = Date()
                self.currentLiveText = ""
                self.currentGapType = .none
                self.isTaskRefreshing = true
                self.startNewTask()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.isTaskRefreshing = false
                }
            }
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.segments.removeAll()
            self.currentLiveText = ""
            self.currentGapType = .none
            self.lastSegmentEndTime = nil
            self.errorMessage = nil
            self.startNewTask()
        }
    }
    
    func updateSegment(id: UUID, newText: String) {
        if let idx = segments.firstIndex(where: { $0.id == id }) {
            segments[idx].text = newText
            
            // "Learn" the corrected words
            let words = newText.lowercased()
                .components(separatedBy: CharacterSet.punctuationCharacters)
                .joined()
                .components(separatedBy: .whitespaces)
                .filter { $0.count > 2 }
            
            var currentVocab = customVocabulary.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            
            var learned = false
            for word in words {
                if !currentVocab.contains(word) {
                    currentVocab.append(word)
                    learned = true
                }
            }
            
            if learned {
                customVocabulary = currentVocab.filter { !$0.isEmpty }.joined(separator: ", ")
                self.startNewTask() // Refresh engine with new vocab
            }
        }
    }
    
    private func teardownAudio() {
        task?.cancel()
        task = nil
        request = nil
        if let engine = audioEngine {
            if engine.isRunning { engine.stop() }
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        silenceTimer?.invalidate()
        progressTimer?.invalidate()
    }
    
    func stopTranscribing() {
        teardownAudio()
        DispatchQueue.main.async {
            self.isListening = false
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
    
    private func showError(_ message: String) {
        DispatchQueue.main.async { self.errorMessage = message }
    }
    
    // MARK: - Battery Saver (Auto-Dim)
    
    func resetDimTimer(timeoutMinutes: Double) {
        DispatchQueue.main.async {
            self.dimTimeoutMinutes = timeoutMinutes
            self.wakeAndResetDimTimer()
        }
    }
    
    private func wakeAndResetDimTimer() {
        self.dimTimer?.invalidate()
        self.onDimStateChange?(false)
        
        guard dimTimeoutMinutes > 0 else { return }
        
        let seconds = dimTimeoutMinutes * 60.0
        self.dimTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.onDimStateChange?(true)
            }
        }
    }
}
