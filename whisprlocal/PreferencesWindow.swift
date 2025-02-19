import SwiftUI

struct PreferencesWindow: View {
    @EnvironmentObject private var transcriptionManager: TranscriptionManager
    @State private var isShowingModelPicker = false
    
    private let availableModels = [
        ("Tiny (English)", "ggml-tiny.en.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"),
        ("Tiny (Multilingual)", "ggml-tiny.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"),
        ("Base (English)", "ggml-base.en.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"),
        ("Small (English)", "ggml-small.en.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"),
        ("Base (Multilingual)", "ggml-base.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Model Management")
                .font(.headline)
            
            if transcriptionManager.isDownloading {
                ProgressView(value: transcriptionManager.downloadProgress) {
                    Text("Downloading model...")
                }
            }
            
            List(availableModels, id: \.0) { model in
                HStack {
                    VStack(alignment: .leading) {
                        Text(model.0)
                            .font(.headline)
                        Text(model.1)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Download") {
                        Task {
                            do {
                                guard let url = URL(string: model.2) else { return }
                                try await transcriptionManager.downloadModel(url: url, filename: model.1)
                            } catch {
                                print("Failed to download model: \(error)")
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
} 