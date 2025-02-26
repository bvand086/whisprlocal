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
        .frame(width: 500, height: 400)  // Increased size
        .padding()
        .task {
            // Try to load the last used model on launch
            if let lastUsedModelURL = modelManager.getLastUsedModelURL() {
                do {
                    try await transcriptionManager.loadModel(named: lastUsedModelURL.lastPathComponent)
                    modelManager.currentModel = lastUsedModelURL
                } catch {
                    print("Failed to load last used model: \(error)")
                    // If last used model fails, we'll let the user choose a model manually
                }
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
    @State private var showModelInfo = false
    @State private var showLargeModelWarning = false
    @State private var pendingLargeModelURL: URL? = nil
    @State private var showDeleteConfirmation = false
    @State private var modelToDelete: URL? = nil
    @State private var expandedSections: Set<String> = ["Downloaded"] // Downloaded section is expanded by default
    
    // Memory thresholds
    private let largeModelThreshold: Double = 1000 // MB
    
    private func getModelSize(_ modelName: String) -> Double {
        if modelName.contains("large") {
            return modelName.contains("q5") ? 1100 : 2300  // Approximate sizes in MB
        } else if modelName.contains("medium") {
            return modelName.contains("q5") ? 514 : 1500
        } else if modelName.contains("small") {
            return modelName.contains("q5") ? 181 : 466
        } else if modelName.contains("base") {
            return modelName.contains("q5") ? 57 : 142
        } else if modelName.contains("tiny") {
            return modelName.contains("q5") ? 31 : 75
        }
        return 0
    }
    
    private func formatSize(_ size: Double) -> String {
        if size >= 1000 {
            return String(format: "%.1f GB", size / 1000)
        }
        return String(format: "%.0f MB", size)
    }
    
    private let availableModels = [
        // Tiny Models
        ("Tiny (Multilingual) - 75 MB", "ggml-tiny.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin"),
        ("Tiny (English) - 75 MB", "ggml-tiny.en.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin"),
        ("Tiny Q5.1 - 31 MB", "ggml-tiny-q5_1.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin"),
        ("Tiny Q8.0 - 42 MB", "ggml-tiny-q8_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q8_0.bin"),
        ("Tiny English Q5.1 - 31 MB", "ggml-tiny.en-q5_1.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en-q5_1.bin"),
        ("Tiny English Q8.0 - 42 MB", "ggml-tiny.en-q8_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en-q8_0.bin"),
        
        // Base Models
        ("Base (Multilingual) - 142 MB", "ggml-base.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"),
        ("Base (English) - 142 MB", "ggml-base.en.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"),
        ("Base Q5.1 - 57 MB", "ggml-base-q5_1.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q5_1.bin"),
        ("Base Q8.0 - 78 MB", "ggml-base-q8_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base-q8_0.bin"),
        ("Base English Q5.1 - 57 MB", "ggml-base.en-q5_1.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-q5_1.bin"),
        ("Base English Q8.0 - 78 MB", "ggml-base.en-q8_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-q8_0.bin"),
        
        // Small Models
        ("Small (Multilingual) - 466 MB", "ggml-small.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin"),
        ("Small (English) - 466 MB", "ggml-small.en.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"),
        ("Small Q5.1 - 181 MB", "ggml-small-q5_1.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin"),
        ("Small Q8.0 - 252 MB", "ggml-small-q8_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q8_0.bin"),
        ("Small English Q5.1 - 181 MB", "ggml-small.en-q5_1.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q5_1.bin"),
        ("Small English Q8.0 - 252 MB", "ggml-small.en-q8_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-q8_0.bin"),
        ("Small English TDRZ - 465 MB", "ggml-small.en-tdrz.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en-tdrz.bin"),
        
        // Medium Models
        ("Medium (Multilingual) - 1.5 GB", "ggml-medium.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin"),
        ("Medium (English) - 1.5 GB", "ggml-medium.en.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin"),
        ("Medium Q5.0 - 514 MB", "ggml-medium-q5_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q5_0.bin"),
        ("Medium Q8.0 - 785 MB", "ggml-medium-q8_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium-q8_0.bin"),
        ("Medium English Q5.0 - 514 MB", "ggml-medium.en-q5_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en-q5_0.bin"),
        ("Medium English Q8.0 - 785 MB", "ggml-medium.en-q8_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en-q8_0.bin"),
        
        // Large Models
        ("Large v1 - 2.9 GB", "ggml-large-v1.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v1.bin"),
        ("Large v2 - 2.9 GB", "ggml-large-v2.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v2.bin"),
        ("Large v2 Q5.0 - 1.1 GB", "ggml-large-v2-q5_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v2-q5_0.bin"),
        ("Large v2 Q8.0 - 1.5 GB", "ggml-large-v2-q8_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v2-q8_0.bin"),
        ("Large v3 - 2.9 GB", "ggml-large-v3.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin"),
        ("Large v3 Q5.0 - 1.1 GB", "ggml-large-v3-q5_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-q5_0.bin"),
        ("Large v3 Turbo - 1.5 GB", "ggml-large-v3-turbo.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"),
        ("Large v3 Turbo Q5.0 - 547 MB", "ggml-large-v3-turbo-q5_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"),
        ("Large v3 Turbo Q8.0 - 834 MB", "ggml-large-v3-turbo-q8_0.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q8_0.bin")
    ]
    
    var sortedModels: [(String, String, String)] {
        let downloadedModels = modelManager.downloadedModels
        return availableModels.sorted { model1, model2 in
            let isDownloaded1 = downloadedModels.contains { $0.lastPathComponent == model1.1 }
            let isDownloaded2 = downloadedModels.contains { $0.lastPathComponent == model2.1 }
            
            if isDownloaded1 == isDownloaded2 {
                return model1.0 < model2.0
            }
            return isDownloaded1 && !isDownloaded2
        }
    }
    
    private var downloadedModels: [(String, String, String)] {
        sortedModels.filter { model in
            modelManager.downloadedModels.contains { $0.lastPathComponent == model.1 }
        }
    }
    
    private var availableModelsNotDownloaded: [(String, String, String)] {
        sortedModels.filter { model in
            !modelManager.downloadedModels.contains { $0.lastPathComponent == model.1 }
        }
    }
    
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
                    Task { @MainActor in
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
            HStack {
                Text("Model Management")
                    .font(.headline)
                
                Button {
                    showModelInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
                .help("View available models on Hugging Face")
                .sheet(isPresented: $showModelInfo) {
                    VStack(spacing: 16) {
                        Text("Whisper Models")
                            .font(.title)
                        
                        Text("All models are available from the Hugging Face repository. Visit the repository for more information about model sizes and capabilities.")
                            .multilineTextAlignment(.center)
                            .padding()
                        
                        Link("View Models on Hugging Face",
                             destination: URL(string: "https://huggingface.co/ggerganov/whisper.cpp")!)
                            .buttonStyle(.borderedProminent)
                        
                        Button("Close") {
                            showModelInfo.toggle()
                        }
                        .padding()
                    }
                    .frame(width: 400, height: 250)
                    .padding()
                }
            }
            
            // Current Model Status
            if let loadingModel = loadingModel {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading model: \(loadingModel.lastPathComponent)...")
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            } else if let currentModel = modelManager.currentModel {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Current Model: \(currentModel.lastPathComponent)")
                            .font(.subheadline)
                    }
                    Text("Memory: ~\(formatSize(getModelSize(currentModel.lastPathComponent)))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            
            if modelManager.isDownloadingModel {
                ProgressView(value: modelManager.downloadProgress) {
                    Text("Downloading model...")
                }
                .padding(.vertical, 4)
            }
            
            // Available Models List
            ScrollView {
                LazyVStack(spacing: 8) {
                    // Downloaded Models Section
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedSections.contains("Downloaded") },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedSections.insert("Downloaded")
                                } else {
                                    expandedSections.remove("Downloaded")
                                }
                            }
                        )
                    ) {
                        if downloadedModels.isEmpty {
                            Text("No models downloaded")
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(downloadedModels, id: \.0) { model in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(model.0)
                                            .font(.headline)
                                        Text(model.1)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    if modelManager.currentModel?.lastPathComponent == model.1 {
                                        Text("Active")
                                            .foregroundColor(.green)
                                            .font(.caption)
                                    } else {
                                        HStack(spacing: 8) {
                                            Button("Load") {
                                                if let modelURL = modelManager.downloadedModels.first(where: { $0.lastPathComponent == model.1 }) {
                                                    loadModel(modelURL)
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            
                                            Button(role: .destructive) {
                                                modelToDelete = modelManager.downloadedModels.first(where: { $0.lastPathComponent == model.1 })
                                                showDeleteConfirmation = true
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    } label: {
                        HStack {
                            Text("Downloaded Models")
                                .font(.headline)
                            Text("(\(downloadedModels.count))")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    // Available Models Section
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedSections.contains("Available") },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedSections.insert("Available")
                                } else {
                                    expandedSections.remove("Available")
                                }
                            }
                        )
                    ) {
                        ForEach(availableModelsNotDownloaded, id: \.0) { model in
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
                                    if let url = URL(string: model.2) {
                                        downloadModel(url: url, filename: model.1)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                    } label: {
                        HStack {
                            Text("Available Models")
                                .font(.headline)
                            Text("(\(availableModelsNotDownloaded.count))")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)
            
            if let error = modelManager.lastError {
                Text(error.localizedDescription)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .alert("Large Model Warning", isPresented: $showLargeModelWarning) {
            Button("Cancel", role: .cancel) {
                pendingLargeModelURL = nil
            }
            Button("Load Anyway") {
                if let modelURL = pendingLargeModelURL {
                    performModelLoad(modelURL)
                }
                pendingLargeModelURL = nil
            }
        } message: {
            Text("This model requires significant memory (\(formatSize(getModelSize(pendingLargeModelURL?.lastPathComponent ?? "")))). Loading it may impact system performance or cause crashes. Are you sure you want to proceed?")
        }
        .alert("Delete Model", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                modelToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let modelURL = modelToDelete {
                    Task {
                        do {
                            try await modelManager.deleteModel(modelURL)
                        } catch {
                            print("Failed to delete model: \(error)")
                            modelManager.lastError = error
                        }
                        modelToDelete = nil
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete this model? This action cannot be undone.")
        }
        .alert("Download Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Failed to download the model. Please check your internet connection and try again.")
        }
    }
    
    private func loadModel(_ modelURL: URL) {
        guard modelURL != modelManager.currentModel else { return }
        
        let modelSize = getModelSize(modelURL.lastPathComponent)
        if modelSize >= largeModelThreshold {
            pendingLargeModelURL = modelURL
            showLargeModelWarning = true
            return
        }
        
        performModelLoad(modelURL)
    }
    
    private func performModelLoad(_ modelURL: URL) {
        Task { @MainActor in
            loadingModel = modelURL
            do {
                // First unload current model if exists
                if modelManager.currentModel != nil {
                    do {
                        try await transcriptionManager.unloadCurrentModel()
                        // Add extra delay after unloading large models
                        if getModelSize(modelManager.currentModel?.lastPathComponent ?? "") >= largeModelThreshold {
                            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                        }
                    } catch {
                        print("Warning: Failed to unload current model: \(error)")
                        // Continue anyway and try to load the new model
                    }
                }
                
                let modelName = modelURL.lastPathComponent
                print("Starting to load model: \(modelName)")
                
                // Run the model loading in a new task to avoid blocking the UI
                try await Task.detached(priority: .userInitiated) {
                    try await transcriptionManager.loadModel(named: modelName)
                }.value
                
                await MainActor.run {
                    modelManager.currentModel = modelURL
                    modelManager.lastError = nil
                    print("Successfully loaded model: \(modelName)")
                }
            } catch {
                print("Failed to load model: \(error)")
                await MainActor.run {
                    modelManager.lastError = error
                    modelManager.currentModel = nil
                }
            }
            loadingModel = nil
        }
    }
    
    private func downloadModel(url: URL, filename: String) {
        Task { @MainActor in
            do {
                try await modelManager.downloadModel(from: url.absoluteString, filename: filename)
            } catch {
                print("Failed to download model: \(error)")
                showError = true
            }
        }
    }
}

#Preview {
    PreferencesView()
} 
