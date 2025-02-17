import SwiftUI

struct PreferencesView: View {
    @StateObject private var modelManager = ModelManager.shared
    
    var body: some View {
        TabView {
            ModelPreferencesView()
                .tabItem {
                    Label("Models", systemImage: "brain")
                }
        }
        .frame(width: 400, height: 300)
        .padding()
    }
}

struct ModelPreferencesView: View {
    @ObservedObject private var modelManager = ModelManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcription Model")
                .font(.headline)
            
            if modelManager.isDownloadingModel {
                ProgressView("Downloading base model...", value: modelManager.downloadProgress)
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
                
                Button("Download Base Model") {
                    modelManager.downloadDefaultModel()
                }
            }
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    PreferencesView()
} 