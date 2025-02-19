import SwiftUI
import SwiftWhisper

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
    @State private var selectedLanguage: WhisperLanguage = .english
    
    private let availableModels = [
        ("Tiny (English)", "ggml-tiny.en.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"),
        ("Tiny (Multilingual)", "ggml-tiny.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"),
        ("Base (English)", "ggml-base.en.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"),
        ("Small (English)", "ggml-small.en.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"),
        ("Base (Multilingual)", "ggml-base.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            // Language Selection
            VStack(alignment: .leading) {
                Text("Language")
                    .font(.headline)
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(WhisperLanguage.allCases) { language in
                        Text(language.displayName)
                            .tag(language)
                    }
                }
                .onChange(of: selectedLanguage) { newLanguage in
                    Task {
                        do {
                            try await transcriptionManager.setLanguage(newLanguage)
                        } catch {
                            print("Failed to set language: \(error)")
                        }
                    }
                }
            }
            .padding(.bottom)
            
            Divider()
            
            // Model Management
            Text("Model Management")
                .font(.headline)
            
            if transcriptionManager.isDownloading {
                ProgressView(value: transcriptionManager.downloadProgress) {
                    Text("Downloading model...")
                }
            }
            
            // Available Models List
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
                    
                    if modelManager.downloadedModels.contains(where: { $0.lastPathComponent == model.1 }) {
                        if modelManager.currentModel?.lastPathComponent == model.1 {
                            Text("Active")
                                .foregroundColor(.green)
                                .font(.caption)
                        } else {
                            Button("Load") {
                                if let modelURL = modelManager.downloadedModels.first(where: { $0.lastPathComponent == model.1 }) {
                                    loadModel(modelURL)
                                }
                            }
                        }
                    } else {
                        Button("Download") {
                            Task {
                                do {
                                    guard let url = URL(string: model.2) else { return }
                                    try await transcriptionManager.downloadModel(url: url, filename: model.1)
                                } catch {
                                    print("Failed to download model: \(error)")
                                    showError = true
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
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
        } message: {
            Text("Failed to download the model. Please check your internet connection and try again.")
        }
    }
    
    private func loadModel(_ modelURL: URL) {
        guard modelURL != modelManager.currentModel else { return }
        
        loadingModel = modelURL
        Task {
            do {
                let modelName = modelURL.lastPathComponent
                try await transcriptionManager.loadModel(named: modelName)
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
