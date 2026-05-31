import Foundation
import AVFoundation
import Speech
import SwiftUI

/// A highly robust helper for speech-to-text with stable history accumulation.
class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    @Published var debugMode: Bool = false
    @Published var useOnDevice: Bool = false
    @Published var errorMessage: String? = nil
    
    var supportsOnDevice: Bool {
        recognizer?.supportsOnDeviceRecognition ?? false
    }
    
    private let recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    // Stable storage for segments that have been "finalized" by a pause
    private var committedSegments: [String] = []
    private var currentLiveText: String = ""
    private var silenceTimer: Timer?
    private var isRefreshingTask: Bool = false
    
    init() {
        recognizer = SFSpeechRecognizer()
    }
    
    func start() {
        Task {
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
                if authStatus == .authorized && recordPermission {
                    self.transcribe()
                } else {
                    self.showError("Permissions denied. Check Settings.")
                }
            }
        }
    }
    
    func transcribe() {
        guard !isListening else { return }
        
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
            
            DispatchQueue.main.async {
                self.isListening = true
                self.errorMessage = nil
                UIApplication.shared.isIdleTimerDisabled = true
            }
        } catch {
            showError("Mic failed: \(error.localizedDescription)")
        }
    }
    
    private func startNewTask() {
        // Cancel previous task if any
        task?.cancel()
        task = nil
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        if supportsOnDevice { request?.requiresOnDeviceRecognition = useOnDevice }
        if #available(iOS 16.0, *) { request?.addsPunctuation = true }
        request?.contextualStrings = ["Dobre rano", "BigCaptions"]
        
        guard let request = request, let recognizer = recognizer else { return }
        
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.currentLiveText = result.bestTranscription.formattedString
                self.updateUI()
                self.resetSilenceTimer()
            }
            
            if let error = error {
                let nsError = error as NSError
                // Don't recurse if we are already refreshing
                if self.isRefreshingTask { return }
                
                // Code 203/1110 are common timeouts. Auto-recover.
                if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 203 || nsError.code == 1110 {
                    self.commitAndRestartTask()
                }
            }
        }
    }
    
    private func resetSilenceTimer() {
        DispatchQueue.main.async {
            self.silenceTimer?.invalidate()
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.commitAndRestartTask()
            }
        }
    }
    
    private func commitAndRestartTask() {
        DispatchQueue.main.async {
            if self.isRefreshingTask { return }
            
            if !self.currentLiveText.isEmpty {
                // Lock the current segment into the history
                self.committedSegments.append(self.currentLiveText)
                self.currentLiveText = ""
                self.updateUI()
                
                // Flag to prevent recursive error handling during task rotation
                self.isRefreshingTask = true
                self.startNewTask()
                
                // Allow error handling again after a brief moment
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isRefreshingTask = false
                }
            }
        }
    }
    
    private func updateUI() {
        DispatchQueue.main.async {
            // Join all history with double newlines, then add the live "working" text
            let history = self.committedSegments.joined(separator: "\n\n")
            
            if history.isEmpty {
                self.transcript = self.currentLiveText
            } else if self.currentLiveText.isEmpty {
                self.transcript = history
            } else {
                self.transcript = history + "\n\n" + self.currentLiveText
            }
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.committedSegments = []
            self.currentLiveText = ""
            self.transcript = ""
            self.errorMessage = nil
            self.startNewTask()
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
}
