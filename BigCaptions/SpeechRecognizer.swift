import Foundation
import AVFoundation
import Speech
import SwiftUI

/// A highly robust helper for speech-to-text that handles "mind-changing" engines (like numeric counts).
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
    
    private var committedHistory: String = ""
    private var currentLiveText: String = ""
    private var silenceTimer: Timer?
    
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
            showError("Mic Start Failed: \(error.localizedDescription)")
        }
    }
    
    private func startNewTask() {
        task?.cancel()
        task = nil
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        if supportsOnDevice { request?.requiresOnDeviceRecognition = useOnDevice }
        if #available(iOS 16.0, *) { request?.addsPunctuation = true }
        request?.contextualStrings = ["Dobre rano", "BigCaptions"]
        
        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.currentLiveText = result.bestTranscription.formattedString
                self.updateUI()
                self.resetSilenceTimer()
            }
            
            if let error = error {
                let nsError = error as NSError
                // Auto-recover from engine timeouts
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
            if !self.currentLiveText.isEmpty {
                if self.committedHistory.isEmpty {
                    self.committedHistory = self.currentLiveText
                } else {
                    self.committedHistory += "\n\n" + self.currentLiveText
                }
                self.currentLiveText = ""
                self.transcript = self.committedHistory
                
                // Restart the task to clear its internal memory
                self.startNewTask()
            }
        }
    }
    
    private func updateUI() {
        DispatchQueue.main.async {
            if self.committedHistory.isEmpty {
                self.transcript = self.currentLiveText
            } else if self.currentLiveText.isEmpty {
                self.transcript = self.committedHistory
            } else {
                self.transcript = self.committedHistory + "\n\n" + self.currentLiveText
            }
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.committedHistory = ""
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
