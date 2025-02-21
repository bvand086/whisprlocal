import Foundation
import CoreML

class ModelManager: NSObject, ObservableObject {
    static let shared = ModelManager()
    
    @Published var isDownloadingModel = false
    @Published var downloadProgress: Double = 0
    @Published var currentModel: URL? = nil {
        didSet {
            if let model = currentModel {
                UserDefaults.standard.set(model.lastPathComponent, forKey: "lastUsedModel")
            }
        }
    }
    @Published var lastError: Error? = nil
    @Published var downloadedModels: [URL] = []
    
    private var downloadTask: URLSessionDownloadTask? = nil
    private var downloadQueue = DispatchQueue(label: "com.whisprlocal.modeldownload")
    
    // Model management
    private let modelsFolderURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsPath = appSupport.appendingPathComponent("Whisprlocal/Models", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: modelsPath, withIntermediateDirectories: true, attributes: nil)
            print("Created models directory at: \(modelsPath)")
        } catch {
            print("Error creating models directory: \(error)")
        }
        return modelsPath
    }()
    
    private override init() {
        super.init()
        print("ModelManager initialized with models folder: \(modelsFolderURL)")
        loadDownloadedModels()
    }
    
    var lastUsedModelName: String? {
        UserDefaults.standard.string(forKey: "lastUsedModel")
    }
    
    func getLastUsedModelURL() -> URL? {
        guard let modelName = lastUsedModelName else { return nil }
        return modelsFolderURL.appendingPathComponent(modelName)
    }
    
    private func loadDownloadedModels() {
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: modelsFolderURL,
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension == "bin" }
            
            Task { @MainActor in
                self.downloadedModels = fileURLs
            }
        } catch {
            print("Error loading downloaded models: \(error)")
        }
    }
    
    func downloadModel(from urlString: String, filename: String) async throws {
        guard !isDownloadingModel else {
            print("Download already in progress")
            return
        }
        
        print("Starting download of model: \(filename) from \(urlString)")
        
        await MainActor.run {
            isDownloadingModel = true
            downloadProgress = 0
            lastError = nil
        }
        
        do {
            // Download GGML model
            try await downloadGGMLModel(from: urlString, filename: filename)
            print("Successfully downloaded GGML model: \(filename)")
            
            // Download and compile Core ML model if it's an English model
            if filename.contains(".en") {
                print("English model detected, downloading Core ML model...")
                try await downloadAndCompileCoreMLModel()
                print("Successfully downloaded and compiled Core ML model")
            }
            
            await MainActor.run {
                isDownloadingModel = false
                downloadProgress = 1.0
                currentModel = self.modelsFolderURL.appendingPathComponent(filename)
                
                // Load the model in TranscriptionManager
                Task {
                    do {
                        try await TranscriptionManager.shared.loadModel(named: filename)
                        print("Successfully loaded model in TranscriptionManager")
                        loadDownloadedModels() // Refresh the list of downloaded models
                    } catch {
                        print("Error loading model in TranscriptionManager: \(error)")
                        self.lastError = error
                    }
                }
            }
        } catch {
            print("Error during model download: \(error)")
            await MainActor.run {
                self.lastError = error
                self.isDownloadingModel = false
                self.downloadProgress = 0
            }
            throw error
        }
    }
    
    private func downloadGGMLModel(from urlString: String, filename: String) async throws {
        guard let url = URL(string: urlString) else {
            print("Invalid URL: \(urlString)")
            throw URLError(.badURL)
        }
        
        let destinationURL = modelsFolderURL.appendingPathComponent(filename)
        print("Downloading GGML model to: \(destinationURL)")
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
            print("Removed existing model file")
        }
        
        let (downloadURL, response) = try await URLSession.shared.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response type")
            throw ModelError.downloadFailed
        }
        
        print("Download response status code: \(httpResponse.statusCode)")
        guard httpResponse.statusCode == 200 else {
            print("Download failed with status code: \(httpResponse.statusCode)")
            throw ModelError.downloadFailed
        }
        
        do {
            try FileManager.default.moveItem(at: downloadURL, to: destinationURL)
            print("Successfully moved downloaded file to destination")
        } catch {
            print("Error moving downloaded file: \(error)")
            throw error
        }
    }
    
    private func downloadAndCompileCoreMLModel() async throws {
        let session = URLSession(configuration: .default)
        
        // Use the correct URL for the compiled model
        let urlString = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-encoder.mlmodelc.zip"
        guard let url = URL(string: urlString) else {
            print("Invalid Core ML model URL")
            throw URLError(.badURL)
        }
        
        let destinationURL = modelsFolderURL.appendingPathComponent("ggml-base.en-encoder.mlmodelc")
        print("Downloading Core ML model to: \(destinationURL)")
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
            print("Removed existing Core ML model")
        }
        
        // Create a temporary directory for the zip file
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let zipURL = tempDir.appendingPathComponent("model.zip")
        
        // Download the zip file
        let (downloadURL, response) = try await session.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("Invalid response type for Core ML model download")
            throw ModelError.downloadFailed
        }
        
        print("Core ML download response status code: \(httpResponse.statusCode)")
        print("Core ML download response headers: \(httpResponse.allHeaderFields)")
        
        if httpResponse.statusCode == 302 || httpResponse.statusCode == 301,
           let redirectURL = httpResponse.allHeaderFields["Location"] as? String,
           let newURL = URL(string: redirectURL) {
            print("Following redirect to: \(redirectURL)")
            let (redirectDownloadURL, redirectResponse) = try await session.download(from: newURL)
            
            guard let redirectHttpResponse = redirectResponse as? HTTPURLResponse,
                  redirectHttpResponse.statusCode == 200 else {
                print("Redirect download failed with status: \(String(describing: (redirectResponse as? HTTPURLResponse)?.statusCode))")
                throw ModelError.downloadFailed
            }
            
            try FileManager.default.moveItem(at: redirectDownloadURL, to: zipURL)
        } else if httpResponse.statusCode == 200 {
            try FileManager.default.moveItem(at: downloadURL, to: zipURL)
        } else {
            print("Unexpected status code: \(httpResponse.statusCode)")
            throw ModelError.downloadFailed
        }
        
        // Unzip the model
        print("Unzipping Core ML model...")
        try await unzipCoreMLModel(from: zipURL, to: destinationURL)
        
        // Clean up
        try? FileManager.default.removeItem(at: tempDir)
        
        // Verify the model exists
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            print("Error: Core ML model not found at destination")
            throw ModelError.downloadFailed
        }
        
        print("Successfully downloaded and extracted Core ML model")
    }
    
    private func unzipCoreMLModel(from zipURL: URL, to destinationURL: URL) async throws {
        // Run unzip command
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", destinationURL.deletingLastPathComponent().path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        print("Running unzip command: unzip -o \(zipURL.path) -d \(destinationURL.deletingLastPathComponent().path)")
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("Unzip failed with output: \(output)")
            throw ModelError.downloadFailed
        }
    }
    
    func deleteModel(_ modelURL: URL) async throws {
        // Don't allow deletion of currently loaded model
        guard modelURL != currentModel else {
            throw ModelError.cannotDeleteActiveModel
        }
        
        do {
            try FileManager.default.removeItem(at: modelURL)
            await MainActor.run {
                // Update the downloadedModels array
                downloadedModels.removeAll { $0 == modelURL }
            }
        } catch {
            print("Error deleting model: \(error)")
            throw error
        }
    }
    
    enum ModelError: LocalizedError {
        case downloadFailed
        case coreMLCompilationFailed
        case cannotDeleteActiveModel
        
        var errorDescription: String? {
            switch self {
            case .downloadFailed:
                return "Failed to download the model file"
            case .coreMLCompilationFailed:
                return "Failed to compile the Core ML model"
            case .cannotDeleteActiveModel:
                return "Cannot delete the currently active model"
            }
        }
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        print("Download cancelled")
        DispatchQueue.main.async {
            self.isDownloadingModel = false
            self.downloadProgress = 0
        }
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // This delegate method is not used in the async/await implementation
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in
            self.downloadProgress = progress
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Download task completed with error: \(error)")
            Task { @MainActor in
                self.lastError = error
                self.isDownloadingModel = false
                self.downloadProgress = 0
            }
        }
    }
} 
