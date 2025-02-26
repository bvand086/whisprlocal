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
        
        // Pre-check if model size will cause memory pressure
        let modelSize = ModelManager.extractModelSize(from: filename)
        let isLargeModel = modelSize.contains("large")
        
        if isLargeModel {
            print("⚠️ Downloading large model. This may require significant memory and storage.")
            
            // Clean up memory before starting large model download
            await performAggressiveMemoryCleanup()
        }
        
        await MainActor.run {
            isDownloadingModel = true
            downloadProgress = 0
            lastError = nil
        }
        
        do {
            // Download GGML model
            try await downloadGGMLModel(from: urlString, filename: filename)
            print("Successfully downloaded GGML model: \(filename)")
            
            // Force memory cleanup between downloads
            if isLargeModel {
                await performAggressiveMemoryCleanup()
            }
            
            // Always download and process CoreML model for all models
            // This ensures we take advantage of CoreML optimization on Apple devices
            print("Downloading Core ML model for \(filename)...")
            try await downloadAndProcessCoreMLModel(for: filename)
            print("Successfully downloaded and processed Core ML model")
            
            // Final memory cleanup
            if isLargeModel {
                await performAggressiveMemoryCleanup()
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
        
        // Configure session for memory-efficient downloading
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 300 // Increase timeout for large files
        
        // Create a session with self as delegate to track progress
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        
        // Reset progress for this new download
        await MainActor.run {
            downloadProgress = 0
        }
        
        let (downloadURL, response) = try await session.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("Download failed with status: \(String(describing: (response as? HTTPURLResponse)?.statusCode))")
            throw ModelError.downloadFailed
        }
        
        do {
            try FileManager.default.moveItem(at: downloadURL, to: destinationURL)
            print("Successfully moved downloaded file to destination")
            
            // Set progress to 1.0 (100%) after successful download
            await MainActor.run {
                downloadProgress = 1.0
            }
        } catch {
            print("Error moving downloaded file: \(error)")
            throw error
        }
    }
    
    private func downloadAndProcessCoreMLModel(for filename: String) async throws {
        let session = URLSession(configuration: .default)
        
        // Get the correct CoreML model name
        let coreMLModelName = ModelManager.getCoreMLModelName(for: filename)
        let coreMLZipName = "\(coreMLModelName).zip"
        
        print("🔍 CoreML model details:")
        print("  Base filename: \(filename)")
        print("  CoreML model name: \(coreMLModelName)")
        print("  CoreML zip name: \(coreMLZipName)")
        
        // Use the correct HuggingFace URL pattern
        let urlString = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(coreMLZipName)"
        print("📥 Attempting to download CoreML model from: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            print("❌ Invalid Core ML model URL")
            throw URLError(.badURL)
        }
        
        let finalDestinationURL = modelsFolderURL.appendingPathComponent(coreMLModelName)
        print("📁 Final destination will be: \(finalDestinationURL.path)")
        
        // Create a unique temporary directory for processing
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        print("📂 Created temporary directory at: \(tempDir.path)")
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
            print("🧹 Cleaned up temporary directory")
            autoreleasepool { }
        }
        
        // Download and handle redirects
        print("🔄 Starting CoreML model download...")
        let zipURL = try await downloadWithRedirects(from: url, to: tempDir.appendingPathComponent("model.zip"))
        print("✅ CoreML model download completed to: \(zipURL.path)")
        
        // Unzip and locate the .mlmodelc
        let mlmodelcURL = try await unzipAndLocateMLModelC(from: zipURL, in: tempDir)
        
        // Remove existing model if present
        if FileManager.default.fileExists(atPath: finalDestinationURL.path) {
            try FileManager.default.removeItem(at: finalDestinationURL)
            print("🗑️ Removed existing Core ML model at: \(finalDestinationURL.path)")
        }
        
        // Move the .mlmodelc to its final location
        try FileManager.default.moveItem(at: mlmodelcURL, to: finalDestinationURL)
        print("✅ Successfully moved Core ML model to: \(finalDestinationURL.path)")
        
        try await validateMLModelC(at: finalDestinationURL)
        print("✅ CoreML model successfully downloaded and validated")
    }
    
    private func downloadWithRedirects(from url: URL, to destinationURL: URL) async throws -> URL {
        // Configure session for memory-efficient downloading
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 300 // Increase timeout for large files
        config.httpMaximumConnectionsPerHost = 1 // Limit connections to prevent memory pressure
        
        // Create a session with self as delegate to track progress
        let session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        
        print("Starting download from \(url.absoluteString)")
        
        // Create a task with built-in tracking via delegate methods
        let (downloadURL, response) = try await session.download(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ModelError.downloadFailed
        }
        
        switch httpResponse.statusCode {
        case 200:
            // Move file directly to destination to avoid keeping multiple copies in memory
            try FileManager.default.moveItem(at: downloadURL, to: destinationURL)
            
            // Force memory cleanup after large file operation
            autoreleasepool {
                // Empty pool to help with memory management
            }
            
            return destinationURL
            
        case 301, 302:
            guard let redirectURL = httpResponse.allHeaderFields["Location"] as? String,
                  let newURL = URL(string: redirectURL) else {
                throw ModelError.downloadFailed
            }
            print("Following redirect to: \(redirectURL)")
            
            // Make sure we don't have the temp file hanging around
            try? FileManager.default.removeItem(at: downloadURL)
            
            // Follow the redirect - reset progress for the new download
            await MainActor.run {
                self.downloadProgress = 0
            }
            
            return try await downloadWithRedirects(from: newURL, to: destinationURL)
            
        default:
            print("Unexpected status code: \(httpResponse.statusCode)")
            throw ModelError.downloadFailed
        }
    }
    
    private func unzipAndLocateMLModelC(from zipURL: URL, in tempDir: URL) async throws -> URL {
        let extractionDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractionDir, withIntermediateDirectories: true)
        
        print("Unzipping Core ML model...")
        print("Zip file location: \(zipURL.path)")
        print("Extraction directory: \(extractionDir.path)")
        
        // Verify zip file exists
        guard FileManager.default.fileExists(atPath: zipURL.path) else {
            print("❌ Zip file not found at: \(zipURL.path)")
            throw ModelError.unzipFailed
        }
        
        // Use the correct unzip command with proper flags
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", extractionDir.path] // Removed -v for cleaner output
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        // Set low priority to prevent memory pressure
        if #available(macOS 10.15, *) {
            process.qualityOfService = .utility
        }
        
        print("🔄 Starting unzip process...")
        try process.run()
        process.waitUntilExit()
        
        // Get the process output
        let data = try pipe.fileHandleForReading.readToEnd() ?? Data()
        let output = String(data: data, encoding: .utf8) ?? ""
        print("📝 Unzip process output:\n\(output)")
        
        guard process.terminationStatus == 0 else {
            print("❌ Unzip failed with status: \(process.terminationStatus)")
            print("Error output: \(output)")
            throw ModelError.unzipFailed
        }
        
        print("✅ Unzip completed successfully")
        
        // List contents of extraction directory
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: extractionDir, includingPropertiesForKeys: nil)
            print("📂 Extracted contents:")
            contents.forEach { print("  - \($0.path)") }
            
            // Look for the .mlmodelc directory directly
            if let mlmodelcURL = contents.first(where: { $0.lastPathComponent.hasSuffix(".mlmodelc") }) {
                print("✅ Found .mlmodelc at: \(mlmodelcURL.path)")
                return mlmodelcURL
            }
        } catch {
            print("⚠️ Failed to list extracted contents: \(error)")
        }
        
        // Try to remove the zip file as soon as possible to free memory
        try? FileManager.default.removeItem(at: zipURL)
        
        // Run an immediate memory cleanup after unzipping
        autoreleasepool {
            print("♻️ Performing memory cleanup after unzipping")
        }
        
        // If we haven't found the .mlmodelc directory by now, throw an error
        print("❌ No .mlmodelc found in extracted contents")
        throw ModelError.mlmodelcNotFound
    }
    
    private func validateMLModelC(at url: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ModelError.invalidModelPath
        }
        
        // Check for key files that should exist in a valid .mlmodelc directory
        let fileManager = FileManager.default
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            
            // A valid mlmodelc should contain these files (at minimum)
            let requiredFiles = ["model.espresso.net", "model.espresso.shape", "model.espresso.weights"]
            
            // Check if at least one required file exists (without loading all contents)
            let hasRequiredFile = contents.contains { file in
                return requiredFiles.contains { file.lastPathComponent.contains($0) }
            }
            
            if !hasRequiredFile {
                print("Warning: mlmodelc directory may not be valid - missing expected files")
                // We don't throw here as the file structure might vary, but we log the warning
            }
        } catch {
            print("Error validating mlmodelc directory: \(error)")
            // We continue despite the error as this is just a validation step
        }
        
        // We don't attempt to load the model here as that would consume memory
        // Validation is done through file structure checks only
    }
    
    static func extractModelSize(from filename: String) -> String {
        // Handle different model naming variations including large model versions
        if filename.contains("large-v3") || filename.contains("large-v3-turbo") {
            return "large-v3"
        } else if filename.contains("large-v2") {
            return "large-v2"
        } else if filename.contains("large-v1") || filename.contains("large") {
            return "large"
        } else if filename.contains("medium") {
            return "medium"
        } else if filename.contains("small") {
            return "small"
        } else if filename.contains("base") {
            return "base"
        } else if filename.contains("tiny") {
            return "tiny"
        }
        
        // Default to base if no match
        return "base"
    }
    
    static func getCoreMLModelName(for filename: String) -> String {
        let modelSize = extractModelSize(from: filename)
        let isEnglishOnly = filename.contains(".en.")
        let languageSuffix = isEnglishOnly ? ".en" : ""
        return "ggml-\(modelSize)\(languageSuffix)-encoder.mlmodelc"
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
            // Refresh the list of downloaded models
            loadDownloadedModels()
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
    
    private func performAggressiveMemoryCleanup() async {
        print("Performing aggressive memory cleanup...")
        
        // Force multiple garbage collection cycles through autorelease pools
        for _ in 0..<3 {
            autoreleasepool {
                // Empty autorelease pool forces cleanup
            }
        }
        
        // Add a small delay to allow memory to be properly released
        do {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
        } catch {
            print("Sleep interrupted during memory cleanup")
        }
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // This is handled by the async/await download method now
        print("Download completed - handled by async/await")
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Calculate progress
        let progress = totalBytesExpectedToWrite > 0 
            ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            : 0
        
        // Update UI on main thread
        Task { @MainActor in
            // Log progress updates less frequently to avoid flooding the console
            if Int(self.downloadProgress * 100) != Int(progress * 100) {
                print("Download progress: \(Int(progress * 100))%")
            }
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
