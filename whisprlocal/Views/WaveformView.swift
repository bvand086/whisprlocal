import SwiftUI

struct WaveformView: View {
    let audioLevels: [Float]
    private let numberOfSamples = 50
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 1/30)) { _ in
            Canvas { context, size in
                // Drawing constants
                let width = size.width
                let height = size.height
                let barWidth = width / CGFloat(numberOfSamples)
                let barSpacing = barWidth * 0.2
                
                // Draw each bar
                for (index, level) in audioLevels.suffix(numberOfSamples).enumerated() {
                    let normalizedLevel = CGFloat(min(max(level, 0), 1))
                    let barHeight = height * normalizedLevel
                    let x = CGFloat(index) * (barWidth)
                    let y = (height - barHeight) / 2
                    
                    let barRect = CGRect(x: x + barSpacing/2,
                                       y: y,
                                       width: barWidth - barSpacing,
                                       height: barHeight)
                    
                    let path = Path(roundedRect: barRect,
                                  cornerRadius: 2)
                    
                    context.fill(path,
                               with: .linearGradient(Gradient(colors: [.accentColor.opacity(0.6),
                                                                      .accentColor]),
                                                   startPoint: CGPoint(x: 0, y: 0),
                                                   endPoint: CGPoint(x: 0, y: height)))
                }
            }
        }
    }
}

#Preview {
    WaveformView(audioLevels: [Float](repeating: 0.5, count: 50))
        .frame(height: 100)
        .padding()
} 