import SwiftUI
import AppKit

struct TranscriptionWindow: View {
    @ObservedObject var transcriptionManager: TranscriptionManager
    @State private var isRecording = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Top section: Waveform
            WaveformView(audioLevels: transcriptionManager.audioLevels)
                .frame(height: 100)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            
            // Center section: Transcript
            ScrollViewReader { proxy in
                ScrollView {
                    Text(transcriptionManager.transcribedText)
                        .font(.body)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("transcript")
                }
                .onChange(of: transcriptionManager.transcribedText) { _ in
                    withAnimation {
                        proxy.scrollTo("transcript", anchor: .bottom)
                    }
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // Bottom section: Controls
            HStack(spacing: 20) {
                Button(action: {
                    isRecording.toggle()
                    if isRecording {
                        transcriptionManager.startRecording()
                    } else {
                        transcriptionManager.stopRecording()
                    }
                }) {
                    Label(isRecording ? "Stop Recording" : "Start Recording",
                          systemImage: isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(isRecording ? .red : .accentColor)
                
                if isRecording {
                    Text("Recording...")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
    }
}

#Preview {
    TranscriptionWindow(transcriptionManager: TranscriptionManager.shared)
} 