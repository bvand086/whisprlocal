import SwiftUI

struct DownloadButton: View {
    @StateObject private var modelManager = ModelManager.shared
    let model: Model
    var onLoad: ((Model) -> Void)?
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.name)
                    .font(.headline)
                Text(model.info)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if FileManager.default.fileExists(atPath: model.fileURL.path()) {
                Button("Load") {
                    onLoad?(model)
                }
                .buttonStyle(.bordered)
            } else {
                if modelManager.isDownloadingModel {
                    ProgressView(value: modelManager.downloadProgress) {
                        Text("Downloading...")
                            .font(.caption)
                    }
                    .frame(width: 100)
                } else {
                    Button("Download") {
                        Task {
                            do {
                                try await modelManager.downloadModel(from: model.url, filename: model.filename)
                            } catch {
                                print("Failed to download model: \(error)")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

extension DownloadButton {
    struct Model: Identifiable {
        let name: String
        let info: String
        let url: String
        let filename: String
        
        var id: String { name }
        
        var fileURL: URL {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let modelsPath = appSupport.appendingPathComponent("Whisprlocal/Models", isDirectory: true)
            return modelsPath.appendingPathComponent(filename)
        }
    }
} 