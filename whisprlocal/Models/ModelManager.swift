import Foundation
import CoreML

enum ModelError: LocalizedError {
    case downloadFailed
    case unzipFailed
    case mlmodelcNotFound
    case invalidModelPath
    case coreMLLoadFailed
    case cannotDeleteActiveModel
    
    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "Failed to download the model file"
        case .unzipFailed:
            return "Failed to unzip the model file"
        case .mlmodelcNotFound:
            return "Could not find .mlmodelc in the unzipped contents"
        case .invalidModelPath:
            return "The Core ML model path is invalid"
        case .coreMLLoadFailed:
            return "Failed to load the Core ML model"
        case .cannotDeleteActiveModel:
            return "Cannot delete the currently active model"
        }
    }
}

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
            
            // Download and process Core ML model if it's an English model
            if filename.contains(".en") {
                print("English model detected, downloading Core ML model...")
                try await downloadAndProcessCoreMLModel(for: filename)
                print("Successfully downloaded and processed Core ML model")
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
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("Download failed with status: \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
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
    
    private func downloadAndProcessCoreMLModel(for filename: String) async throws {
        let session = URLSession(configuration: .default)
        
        // Extract model size from filename (e.g., "small", "base", "medium", "large")
        let modelSize = extractModelSize(from: filename)
        
        // Use the correct URL for the Core ML model based on size
        let urlString = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(modelSize).en-encoder.mlmodelc.zip"
        guard let url = URL(string: urlString) else {
            print("Invalid Core ML model URL")
            throw URLError(.badURL)
        }
        
        let mlmodelcName = "ggml-\(modelSize).en-encoder.mlmodelc"
        let finalDestinationURL = modelsFolderURL.appendingPathComponent(mlmodelcName)
        
        // Create a unique temporary directory for processing
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            // Clean up temporary directory
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Download and handle redirects
        let zipURL = try await downloadWithRedirects(from: url, to: tempDir.appendingPathComponent("model.zip"))
        
        // Unzip and locate the .mlmodelc
        let mlmodelcURL = try await unzipAndLocateMLModelC(from: zipURL, in: tempDir)
        
        // Remove existing model if present
        if FileManager.default.fileExists(atPath: finalDestinationURL.path) {
            try FileManager.default.removeItem(at: finalDestinationURL)
            print("Removed existing Core ML model at: \(finalDestinationURL.path)")
        }
        
        // Move the .mlmodelc to its final location
        try FileManager.default.moveItem(at: mlmodelcURL, to: finalDestinationURL)
        print("Successfully moved Core ML model to: \(finalDestinationURL.path)")
        
        // Validate the final .mlmodelc
        try validateMLModelC(at: finalDestinationURL)
    }
    
    private func downloadWithRedirects(from url: URL, to destinationURL: URL) async throws -> URL {
        let (downloadURL, response) = try await URLSession.shared.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelError.downloadFailed
        }
        
        switch httpResponse.statusCode {
        case 200:
            try FileManager.default.moveItem(at: downloadURL, to: destinationURL)
            return destinationURL
            
        case 301, 302:
            guard let redirectURL = httpResponse.allHeaderFields["Location"] as? String,
                  let newURL = URL(string: redirectURL) else {
                throw ModelError.downloadFailed
            }
            print("Following redirect to: \(redirectURL)")
            return try await downloadWithRedirects(from: newURL, to: destinationURL)
            
        default:
            print("Unexpected status code: \(httpResponse.statusCode)")
            throw ModelError.downloadFailed
        }
    }
    
    private func unzipAndLocateMLModelC(from zipURL: URL, in tempDir: URL) async throws -> URL {
        let extractionDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractionDir, withIntermediateDirectories: true)
        
        // Use Process to unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", zipURL.path, "-d", extractionDir.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        print("Unzipping Core ML model...")
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
            let output = String(data: data, encoding: .utf8) ?? ""
            print("Unzip failed with output: \(output)")
            throw ModelError.unzipFailed
        }
        
        // Recursively search for .mlmodelc
        guard let mlmodelcURL = try findMLModelC(in: extractionDir) else {
            throw ModelError.mlmodelcNotFound
        }
        
        return mlmodelcURL
    }
    
    private func findMLModelC(in directory: URL) throws -> URL? {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        
        // First, look for .mlmodelc directly in this directory
        if let mlmodelc = contents.first(where: { $0.lastPathComponent.hasSuffix(".mlmodelc") }) {
            return mlmodelc
        }
        
        // Then recursively search subdirectories
        for url in contents where (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            if let found = try findMLModelC(in: url) {
                return found
            }
        }
        
        return nil
    }
    
    private func validateMLModelC(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ModelError.invalidModelPath
        }
        
        // Additional validation could be added here, such as checking for required files
        // within the .mlmodelc directory or attempting to load the model
    }
    
    private func extractModelSize(from filename: String) -> String {
        let sizes = ["tiny", "base", "small", "medium", "large"]
        return sizes.first { filename.contains($0) } ?? "base"
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
