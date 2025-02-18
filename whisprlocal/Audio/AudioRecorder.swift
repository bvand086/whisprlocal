import Foundation
import AVFoundation
import SwiftUI

/// A singleton class to manage audio recording using AVAudioEngine.
class AudioRecorder: NSObject, ObservableObject {
    static let shared = AudioRecorder()
    
    private let audioEngine = AVAudioEngine()
    
    @Published var isRecording: Bool = false
    @Published var lastError: Error? = nil
    
    private override init() {
        super.init()
        // No need for audio session setup on macOS
    }
    
    /// Starts audio capture
    func startRecording() {
        // If we're already recording, do nothing
        guard !isRecording else { return }
        
        do {
            try startEngine()
            isRecording = true
        } catch {
            lastError = error
            print("Failed to start recording: \(error)")
        }
    }
    
    /// Stops audio capture and resets the engine.
    func stopRecording() {
        guard isRecording else { return }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRecording = false
    }
    
    /// Sets up tap on the inputNode and starts the audio engine.
    private func startEngine() throws {
        let inputNode = audioEngine.inputNode
        
        // Configure format for 16kHz mono audio (optimal for Whisper)
        let desiredFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        print("Input format: \(recordingFormat.description)")
        print("Desired format: \(desiredFormat.description)")
        
        // Create converter if needed
        let converter = AVAudioConverter(from: recordingFormat, to: desiredFormat)
        
        // Install a tap to capture audio buffers
        // Using a larger buffer size (2 seconds of audio) for better speech recognition
        let bufferSize = AVAudioFrameCount(desiredFormat.sampleRate * 2.0) // 2 seconds of audio
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // If formats match, send buffer directly
            if recordingFormat == desiredFormat {
                Task {
                    await TranscriptionManager.shared.processAudioBuffer(buffer)
                }
                return
            }
            
            // Convert to desired format
            guard let converter = converter else {
                print("Failed to create audio converter")
                return
            }
            
            let convertedBuffer = AVAudioPCMBuffer(pcmFormat: desiredFormat,
                                                  frameCapacity: AVAudioFrameCount(desiredFormat.sampleRate * Double(buffer.frameLength) / recordingFormat.sampleRate))!
            
            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)
            
            if let error = error {
                self.lastError = error
                print("Audio conversion error: \(error)")
                return
            }
            
            Task {
                await TranscriptionManager.shared.processAudioBuffer(convertedBuffer)
            }
        }
        
        audioEngine.prepare()
        try audioEngine.start()
    }
} 