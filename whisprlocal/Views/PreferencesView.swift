import SwiftUI

struct PreferencesView: View {
    @StateObject private var modelManager = ModelManager.shared
    @EnvironmentObject private var transcriptionManager: TranscriptionManager
    
    var body: some View {
        TabView {
            ModelPreferencesView()
                .tabItem {
                    Label("Models", systemImage: "brain")
                }
        }
        .frame(width: 400, height: 300)
        .padding()
        .task {
            // Try to load the model on launch
            do {
                try await transcriptionManager.loadModel(named: "ggml-base.en.bin")
            } catch {
                print("Failed to load model: \(error)")
            }
        }
    }
}

struct ModelPreferencesView: View {
    @StateObject private var modelManager = ModelManager.shared
    @EnvironmentObject private var transcriptionManager: TranscriptionManager
    @State private var showError = false
    @State private var loadingModel: URL? = nil
    
    private let defaultModel = DownloadButton.Model(
        name: "Base Model",
        info: "(English, optimized)",
        url: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
        filename: "ggml-base.en.bin"
    )
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Models")
                .font(.headline)
            
            if modelManager.isDownloadingModel {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView("Downloading base model...", value: modelManager.downloadProgress)
                    Button("Cancel") {
                        modelManager.cancelDownload()
                    }
                    .controlSize(.small)
                }
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(modelManager.downloadedModels, id: \.lastPathComponent) { modelURL in
                        Button {
                            loadModel(modelURL)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(modelURL == modelManager.currentModel ? Color.green : Color.gray)
                                    .frame(width: 8, height: 8)
                                
                                Text(modelURL.lastPathComponent)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                if modelURL == loadingModel {
                                    ProgressView()
                                        .controlSize(.small)
                                } else if modelURL == modelManager.currentModel {
                                    Text("Active")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 120)
            
            if modelManager.downloadedModels.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("No models downloaded")
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Button("Download Base Model") {
                        Task {
                            do {
                                try await modelManager.downloadModel(
                                    from: defaultModel.url,
                                    filename: defaultModel.filename
                                )
                            } catch {
                                showError = true
                            }
                        }
                    }
                    
                    if modelManager.lastError != nil {
                        Text("Download failed. Please check your internet connection.")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            
            if let error = modelManager.lastError {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            
            Spacer()
        }
        .padding()
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
            Button("Retry") {
                Task {
                    try? await modelManager.downloadModel(
                        from: defaultModel.url,
                        filename: defaultModel.filename
                    )
                }
            }
        } message: {
            Text("Failed to download the model. Please check your internet connection and try again.")
        }
    }
    
    private func loadModel(_ modelURL: URL) {
        guard modelURL != modelManager.currentModel else { return }
        
        loadingModel = modelURL
        Task {
            do {
                try await transcriptionManager.loadModel(named: modelURL.lastPathComponent)
                await MainActor.run {
                    modelManager.currentModel = modelURL
                }
            } catch {
                print("Failed to load model: \(error)")
                await MainActor.run {
                    modelManager.lastError = error
                }
            }
            await MainActor.run {
                loadingModel = nil
            }
        }
    }
}

#Preview {
    PreferencesView()
} 