import Foundation
import AVFoundation
import Speech
import SwiftUI

/// A helper for transcribing speech to text using SFSpeechRecognizer.
class SpeechRecognizer: ObservableObject {
    enum RecognizerError: Error {
        case nilRecognizer
        case notAuthorizedToRecognize
        case notPermittedToRecord
        case recognizerIsUnavailable
    }
    
    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    
    private let recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    private var committedTranscript: String = ""
    private var currentSegment: String = ""
    private var silenceTimer: Timer?
    
    init() {
        recognizer = SFSpeechRecognizer()
        
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
            
            if authStatus == .authorized && recordPermission {
                // Pre-init audio session
                try? AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
                try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
            }
        }
    }
    
    deinit {
        reset()
    }
    
    func transcribe() {
        guard let recognizer = recognizer, recognizer.isAvailable else { return }
        
        audioEngine = AVAudioEngine()
        startNewTask()
        
        let inputNode = audioEngine!.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer: AVAudioPCMBuffer, _) in
            self?.request?.append(buffer)
        }
        
        do {
            audioEngine!.prepare()
            try audioEngine!.start()
            DispatchQueue.main.async { self.isListening = true }
        } catch {
            print("Audio engine error: \(error)")
        }
    }
    
    private func startNewTask() {
        task?.cancel()
        task = nil
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request?.addsPunctuation = true
        }
        
        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.currentSegment = result.bestTranscription.formattedString
                self.updateDisplay()
                self.resetSilenceTimer()
            }
            
            if let error = error {
                let nsError = error as NSError
                // Internal timeout or limit reached: commit and rotate
                if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 203 || nsError.code == 1110 {
                    self.commitCurrentSegment()
                }
            }
        }
    }
    
    private func updateDisplay() {
        DispatchQueue.main.async {
            if self.committedTranscript.isEmpty {
                self.transcript = self.currentSegment
            } else {
                self.transcript = self.committedTranscript + "\n\n" + self.currentSegment
            }
        }
    }
    
    private func resetSilenceTimer() {
        DispatchQueue.main.async {
            self.silenceTimer?.invalidate()
            // Using 2.5s for a snappier gap detection
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
                self?.commitCurrentSegment()
            }
        }
    }
    
    private func commitCurrentSegment() {
        DispatchQueue.main.async {
            if !self.currentSegment.isEmpty {
                if self.committedTranscript.isEmpty {
                    self.committedTranscript = self.currentSegment
                } else {
                    self.committedTranscript += "\n\n" + self.currentSegment
                }
                self.currentSegment = ""
                self.transcript = self.committedTranscript
                
                // Keep the audio flowing, but fresh start the "brain" for the next thought
                self.startNewTask()
            }
        }
    }
    
    func stopTranscribing() {
        reset()
    }
    
    private func reset() {
        DispatchQueue.main.async { self.isListening = false }
        silenceTimer?.invalidate()
        silenceTimer = nil
        task?.cancel()
        task = nil
        request = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }
}
