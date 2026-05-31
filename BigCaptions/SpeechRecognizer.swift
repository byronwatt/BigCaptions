import Foundation
import AVFoundation
import Speech
import SwiftUI

/// A helper for transcribing speech to text using SFSpeechRecognizer.
class SpeechRecognizer: ObservableObject {
    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    
    private let recognizer: SFSpeechRecognizer?
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    
    private var committedTranscript: String = ""
    private var lastSegmentEndTime: TimeInterval = 0
    private var taskStartTime: Date = Date()
    
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
        taskStartTime = Date()
        
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            request?.addsPunctuation = true
        }
        
        task = recognizer?.recognitionTask(with: request!) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                self.processResult(result)
            }
            
            if let error = error {
                let nsError = error as NSError
                // Internal timeout or limit reached: commit what we have and refresh ONLY if necessary
                if nsError.domain == "kAFAssistantErrorDomain" || nsError.code == 203 || nsError.code == 1110 {
                    self.commitAndRestart()
                }
            }
        }
    }
    
    private func processResult(_ result: SFSpeechRecognitionResult) {
        let segments = result.bestTranscription.segments
        var currentFormattedText = ""
        var localLastEnd: TimeInterval = 0
        
        for (index, segment) in segments.enumerated() {
            // Check for gap within this specific recognition task
            if index > 0 && (segment.timestamp - localLastEnd) > 3.0 {
                currentFormattedText += "\n\n"
            }
            
            currentFormattedText += segment.substring
            
            if index < segments.count - 1 {
                currentFormattedText += " "
            }
            
            localLastEnd = segment.timestamp + segment.duration
        }
        
        DispatchQueue.main.async {
            // Update global end time relative to the task start
            self.lastSegmentEndTime = localLastEnd
            
            if self.committedTranscript.isEmpty {
                self.transcript = currentFormattedText
            } else {
                // Determine if there was a gap between the OLD committed text and the START of this new text
                // segment.timestamp is relative to the start of this task.
                let gapSinceLastTask = segments.first.map { $0.timestamp } ?? 0
                let totalGap = (Date().timeIntervalSince(self.taskStartTime)) // Approximation
                
                // If this is the start of a task and it's been a while, or if the first word has a big delay
                if gapSinceLastTask > 3.0 {
                   self.transcript = self.committedTranscript + "\n\n" + currentFormattedText
                } else {
                   self.transcript = self.committedTranscript + " " + currentFormattedText
                }
            }
        }
    }
    
    private func commitAndRestart() {
        DispatchQueue.main.async {
            // Lock in everything we've heard so far
            self.committedTranscript = self.transcript
            self.startNewTask()
        }
    }
    
    func stopTranscribing() {
        reset()
    }
    
    private func reset() {
        DispatchQueue.main.async { self.isListening = false }
        task?.cancel()
        task = nil
        request = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
    }
}
