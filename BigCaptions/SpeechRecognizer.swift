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
    
    // THE SOURCE OF TRUTH: All finished thoughts go here.
    private var committedHistory: [String] = []
    // THE WORKING BUFFER: What we are currently hearing.
    private var currentSegment: String = ""
    
    private var silenceTimer: Timer?
    private var isTaskRefreshing: Bool = false
    
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
        task?.cancel()
        task = nil
        currentSegment = "" // Clear the working buffer for the new task
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        if supportsOnDevice { request?.requiresOnDeviceRecognition = useOnDevice }
        if #available(iOS 16.0, *) { request?.addsPunctuation = true }
        request?.contextualStrings = ["Dobre rano", "BigCaptions"]
        
        guard let request = request, let recognizer = recognizer else { return }
        
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.currentSegment = result.bestTranscription.formattedString
                self.rebuildUI()
                self.resetSilenceTimer()
            }
            
            if let error = error {
                let nsError = error as NSError
                if self.isTaskRefreshing { return }
                
                if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 203 || nsError.code == 1110 {
                    self.lockInAndRestart()
                }
            }
        }
    }
    
    private func resetSilenceTimer() {
        DispatchQueue.main.async {
            self.silenceTimer?.invalidate()
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.lockInAndRestart()
            }
        }
    }
    
    private func lockInAndRestart() {
        DispatchQueue.main.async {
            if self.isTaskRefreshing { return }
            
            if !self.currentSegment.isEmpty {
                // Permanently save the finished thought
                self.committedHistory.append(self.currentSegment)
                self.currentSegment = ""
                self.rebuildUI()
                
                self.isTaskRefreshing = true
                self.startNewTask()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    self.isTaskRefreshing = false
                }
            }
        }
    }
    
    private func rebuildUI() {
        DispatchQueue.main.async {
            // Join all history with double newlines
            let historyText = self.committedHistory.joined(separator: "\n\n")
            
            if historyText.isEmpty {
                self.transcript = self.currentSegment
            } else if self.currentSegment.isEmpty {
                self.transcript = historyText
            } else {
                // Combine history + gap + current thought
                self.transcript = historyText + "\n\n" + self.currentSegment
            }
        }
    }
    
    func clear() {
        DispatchQueue.main.async {
            self.committedHistory = []
            self.currentSegment = ""
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
