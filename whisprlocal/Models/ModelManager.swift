import Foundation
import SwiftWhisper

class ModelManager: ObservableObject {
    @Published var currentModel: Whisper?
    @Published var isDownloadingModel = false
    @Published var downloadProgress: Double = 0
    
    static let shared = ModelManager()
    static let defaultModelUrl = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"
    
    private let modelDirectory: URL
    
    init() {
        // Get the Application Support directory
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        modelDirectory = appSupport.appendingPathComponent("WhisprLocal/Models", isDirectory: true)
        
        // Create models directory if it doesn't exist
        try? FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        
        // Load existing model or download default
        loadExistingModel()
    }
    
    private func loadExistingModel() {
        let baseModelPath = modelDirectory.appendingPathComponent("ggml-base.bin")
        
        if FileManager.default.fileExists(atPath: baseModelPath.path) {
            do {
                currentModel = try Whisper(fromFileURL: baseModelPath)
            } catch {
                print("Error loading model: \(error)")
                downloadDefaultModel()
            }
        } else {
            downloadDefaultModel()
        }
    }
    
    func downloadDefaultModel() {
        guard !isDownloadingModel else { return }
        
        isDownloadingModel = true
        let destination = modelDirectory.appendingPathComponent("ggml-base.bin")
        
        let task = URLSession.shared.downloadTask(with: URL(string: Self.defaultModelUrl)!) { [weak self] tempUrl, response, error in
            DispatchQueue.main.async {
                self?.isDownloadingModel = false
                
                if let error = error {
                    print("Download error: \(error)")
                    return
                }
                
                guard let tempUrl = tempUrl else { return }
                
                do {
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempUrl, to: destination)
                    self?.loadExistingModel()
                } catch {
                    print("Error saving model: \(error)")
                }
            }
        }
        
        task.resume()
    }
} 