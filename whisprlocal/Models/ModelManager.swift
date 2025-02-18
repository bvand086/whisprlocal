import Foundation
import CoreML

class ModelManager: NSObject, ObservableObject {
    static let shared = ModelManager()
    
    @Published var isDownloadingModel = false
    @Published var downloadProgress: Double = 0
    @Published var currentModel: URL? = nil
    @Published var lastError: Error? = nil
    
    private var downloadTask: URLSessionDownloadTask? = nil
    private var downloadQueue = DispatchQueue(label: "com.whisprlocal.modeldownload")
    
    // Model management
    private let modelsFolderURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsPath = appSupport.appendingPathComponent("Whisprlocal/Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: modelsPath, withIntermediateDirectories: true)
        return modelsPath
    }()
    
    private override init() {
        super.init()
    } // Ensure singleton pattern
    
    func downloadDefaultModel() async throws {
        guard !isDownloadingModel else { return }
        
        DispatchQueue.main.async {
            self.isDownloadingModel = true
            self.downloadProgress = 0
            self.lastError = nil
        }
        
        // Download both GGML and Core ML models
        try await downloadGGMLModel()
        try await downloadCoreMLModel()
        
        DispatchQueue.main.async {
            self.isDownloadingModel = false
            self.downloadProgress = 1.0
            
            // Load the model in TranscriptionManager
            Task {
                do {
                    try await TranscriptionManager.shared.loadModel(named: "ggml-base.en.bin")
                } catch {
                    self.lastError = error
                }
            }
        }
    }
    
    private func downloadGGMLModel() async throws {
        let session = URLSession(configuration: .default)
        
        guard let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin") else {
            throw URLError(.badURL)
        }
        
        let destinationURL = modelsFolderURL.appendingPathComponent("ggml-base.en.bin")
        try? FileManager.default.removeItem(at: destinationURL)
        
        let (downloadURL, response) = try await session.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelError.downloadFailed
        }
        
        try FileManager.default.moveItem(at: downloadURL, to: destinationURL)
    }
    
    private func downloadCoreMLModel() async throws {
        let session = URLSession(configuration: .default)
        
        guard let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en-encoder.mlmodel") else {
            throw URLError(.badURL)
        }
        
        let destinationURL = modelsFolderURL.appendingPathComponent("ggml-base.en-encoder.mlmodel")
        try? FileManager.default.removeItem(at: destinationURL)
        
        let (downloadURL, response) = try await session.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ModelError.downloadFailed
        }
        
        try FileManager.default.moveItem(at: downloadURL, to: destinationURL)
        
        // Compile the Core ML model
        let compiledURL = modelsFolderURL.appendingPathComponent("ggml-base.en-encoder.mlmodelc")
        try? FileManager.default.removeItem(at: compiledURL)
        
        do {
            try await compileMLModel(at: destinationURL, to: compiledURL)
        } catch {
            throw ModelError.coreMLCompilationFailed
        }
    }
    
    private func compileMLModel(at sourceURL: URL, to destinationURL: URL) async throws {
        print("Starting model compilation...")
        print("Source URL: \(sourceURL)")
        print("Destination URL: \(destinationURL)")
        
        // Check if source exists
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("Error: Source model file not found")
            throw ModelError.coreMLCompilationFailed
        }
        print("Source file exists: true")
        
        // Create parent directory if needed
        let parentDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        
        print("Compiling model...")
        // The compilation process will create the .mlmodelc bundle
        let compiledModel = try await MLModel.compileModel(at: sourceURL)
        
        print("Compiled model URL: \(compiledModel)")
        print("Compiled model exists: \(FileManager.default.fileExists(atPath: compiledModel.path))")
        
        // Move the compiled model to the final destination if needed
        if compiledModel.path != destinationURL.path {
            print("Moving compiled model to final destination...")
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: compiledModel, to: destinationURL)
        }
        
        // Verify the final model exists
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            print("Error: Final compiled model not found at destination")
            throw ModelError.coreMLCompilationFailed
        }
        
        print("Model compilation completed successfully")
        
        // List contents of the compiled model bundle
        if let items = try? FileManager.default.contentsOfDirectory(at: destinationURL, includingPropertiesForKeys: nil) {
            print("Compiled model bundle contents:")
            items.forEach { print("- \($0)") }
        }
    }
    
    enum ModelError: LocalizedError {
        case downloadFailed
        case coreMLCompilationFailed
        
        var errorDescription: String? {
            switch self {
            case .downloadFailed:
                return "Failed to download the model file"
            case .coreMLCompilationFailed:
                return "Failed to compile the Core ML model"
            }
        }
    }
    
    func cancelDownload() {
        downloadTask?.cancel()
        DispatchQueue.main.async {
            self.isDownloadingModel = false
            self.downloadProgress = 0
        }
    }
    
    private var completionHandler: ((Error?) -> Void)?
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Move the downloaded file to the models directory
        do {
            let destinationURL = modelsFolderURL.appendingPathComponent("ggml-base.en.bin")
            
            // Remove existing file if it exists
            try? FileManager.default.removeItem(at: destinationURL)
            
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            DispatchQueue.main.async {
                self.currentModel = destinationURL
                self.isDownloadingModel = false
                self.downloadProgress = 1.0
                self.completionHandler?(nil)
                
                // Load the model in TranscriptionManager
                Task {
                    do {
                        try await TranscriptionManager.shared.loadModel(named: "ggml-base.en.bin")
                    } catch {
                        self.lastError = error
                        self.completionHandler?(error)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.lastError = error
                self.isDownloadingModel = false
                self.downloadProgress = 0
                self.completionHandler?(error)
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async {
            self.downloadProgress = progress
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.lastError = error
                self.isDownloadingModel = false
                self.downloadProgress = 0
                self.completionHandler?(error)
            }
        }
    }
} 
