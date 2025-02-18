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
    @ObservedObject private var modelManager = ModelManager.shared
    @State private var showError = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Model")
                .font(.headline)
            
            if modelManager.isDownloadingModel {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView("Downloading base model...", value: modelManager.downloadProgress)
                    Button("Cancel") {
                        modelManager.cancelDownload()
                    }
                    .controlSize(.small)
                }
            } else if modelManager.currentModel != nil {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Base model loaded")
                }
            } else {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)
                    Text("No model loaded")
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Button("Download Base Model") {
                        Task {
                            do {
                                try await modelManager.downloadDefaultModel()
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
            
            Spacer()
        }
        .padding()
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
            Button("Retry") {
                Task {
                    try? await modelManager.downloadDefaultModel()
                }
            }
        } message: {
            Text("Failed to download the model. Please check your internet connection and try again.")
        }
    }
}

#Preview {
    PreferencesView()
} 