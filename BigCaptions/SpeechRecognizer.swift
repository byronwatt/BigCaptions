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
    
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?
    private var silenceTimer: Timer?
    private var finalTranscript: String = ""
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
        Task {
            do {
                try await startTranscribing()
            } catch {
                speakError(error)
            }
        }
    }
    
    func stopTranscribing() {
        reset()
    }
    
    private func startTranscribing() async throws {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw RecognizerError.recognizerIsUnavailable
        }
        
        reset()
        
        audioEngine = AVAudioEngine()
        request = SFSpeechAudioBufferRecognitionRequest()
        guard let audioEngine = audioEngine, let request = request else { return }
        
        request.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
            request.append(buffer)
        }
        
        audioEngine.prepare()
        try audioEngine.start()
        
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.currentSegment = result.bestTranscription.formattedString
                self.updateTranscript()
                self.restartSilenceTimer()
            }
            
            if error != nil {
                self.reset()
            }
        }
    }
    
    private func updateTranscript() {
        DispatchQueue.main.async {
            if self.finalTranscript.isEmpty {
                self.transcript = self.currentSegment
            } else {
                self.transcript = self.finalTranscript + "\n\n" + self.currentSegment
            }
        }
    }
    
    private func restartSilenceTimer() {
        DispatchQueue.main.async {
            self.silenceTimer?.invalidate()
            self.silenceTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if !self.currentSegment.isEmpty {
                    // Commit current segment to final transcript
                    if self.finalTranscript.isEmpty {
                        self.finalTranscript = self.currentSegment
                    } else {
                        self.finalTranscript += "\n\n" + self.currentSegment
                    }
                    self.currentSegment = ""
                    
                    // Restart the transcription task to clear the internal buffer
                    // This forces the speech engine to start a new segment.
                    self.stopTranscribing()
                    self.transcribe()
                }
            }
        }
    }
    
    private func reset() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        task?.cancel()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        task = nil
        request = nil
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
