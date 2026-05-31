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
        
        var message: String {
            switch self {
            case .nilRecognizer: return "Can't initialize speech recognizer"
            case .notAuthorizedToRecognize: return "Not authorized to recognize speech"
            case .notPermittedToRecord: return "Not permitted to record audio"
            case .recognizerIsUnavailable: return "Recognizer is unavailable"
            }
        }
    }
    
    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    
    private let recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    private var silenceTimer: Timer?
    private var committedTranscript: String = ""
    private var currentSegment: String = ""
    
    init() {
        recognizer = SFSpeechRecognizer()
        
        Task {
            do {
                guard recognizer != nil else {
                    throw RecognizerError.nilRecognizer
                }
                let authorizationStatus = await withCheckedContinuation { continuation in
                    SFSpeechRecognizer.requestAuthorization { status in
                        continuation.resume(returning: status)
                    }
                }
                guard authorizationStatus == .authorized else {
                    throw RecognizerError.notAuthorizedToRecognize
                }
                let recordPermission = await withCheckedContinuation { continuation in
                    AVAudioSession.sharedInstance().requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
                guard recordPermission else {
                    throw RecognizerError.notPermittedToRecord
                }
            } catch {
                speakError(error)
            }
        }
    }
    
    deinit {
        reset()
    }
    
    func transcribe() {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            speakError(RecognizerError.recognizerIsUnavailable)
            return
        }
        
        do {
            audioEngine = AVAudioEngine()
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            startNewRecognitionTask()
            
            let inputNode = audioEngine!.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
                self?.request?.append(buffer)
            }
            
            audioEngine!.prepare()
            try audioEngine!.start()
            
            DispatchQueue.main.async {
                self.isListening = true
            }
        } catch {
            speakError(error)
        }
    }
    
    private func startNewRecognitionTask() {
        task?.cancel()
        task = nil
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request?.addsPunctuation = true
        }
        
        guard let request = request, let recognizer = recognizer else { return }
        
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.currentSegment = result.bestTranscription.formattedString
                self.updateDisplayTranscript()
                self.restartSilenceTimer()
            }
            
            if let error = error {
                // If it's a real error (like engine timeout), try to recover by committing what we have
                let nsError = error as NSError
                if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 203 || nsError.code == 1110 {
                    self.commitSegment()
                }
            }
        }
    }
    
    private func updateDisplayTranscript() {
        DispatchQueue.main.async {
            if self.committedTranscript.isEmpty {
                self.transcript = self.currentSegment
            } else {
                self.transcript = self.committedTranscript + "\n\n" + self.currentSegment
            }
        }
    }
    
    private func restartSilenceTimer() {
        DispatchQueue.main.async {
            self.silenceTimer?.invalidate()
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.commitSegment()
            }
        }
    }
    
    private func commitSegment() {
        DispatchQueue.main.async {
            if !self.currentSegment.isEmpty {
                if self.committedTranscript.isEmpty {
                    self.committedTranscript = self.currentSegment
                } else {
                    self.committedTranscript += "\n\n" + self.currentSegment
                }
                self.currentSegment = ""
                self.transcript = self.committedTranscript
                
                // Restart task to clear buffer and handle the gap
                self.startNewRecognitionTask()
            }
        }
    }
    
    func stopTranscribing() {
        reset()
    }
    
    private func reset() {
        DispatchQueue.main.async {
            self.isListening = false
        }
        silenceTimer?.invalidate()
        silenceTimer = nil
        task?.cancel()
        task = nil
        request = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }
    
    private func speakError(_ error: Error) {
        var errorMessage = ""
        if let error = error as? RecognizerError {
            errorMessage = error.message
        } else {
            errorMessage = error.localizedDescription
        }
        DispatchQueue.main.async {
            self.transcript = "<< Error: \(errorMessage) >>"
        }
    }
}
