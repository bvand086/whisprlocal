import Foundation

class ModelManager: NSObject, ObservableObject {
    static let shared = ModelManager()
    
    @Published var isDownloadingModel = false
    @Published var downloadProgress: Double = 0
    @Published var currentModel: URL? = nil
    @Published var lastError: Error? = nil
    
    private var downloadTask: URLSessionDownloadTask? = nil
    
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
        
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        
        guard let url = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin") else {
            throw URLError(.badURL)
        }
        
        downloadTask = session.downloadTask(with: url)
        downloadTask?.resume()
        
        // Create a continuation to wait for completion
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.completionHandler = { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
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
        // Move the downloaded file to a permanent location
        do {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destinationURL = documentsPath.appendingPathComponent("whisper-model.bin")
            
            // Remove existing file if it exists
            try? FileManager.default.removeItem(at: destinationURL)
            
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            DispatchQueue.main.async {
                self.currentModel = destinationURL
                self.isDownloadingModel = false
                self.downloadProgress = 1.0
                self.completionHandler?(nil)
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
