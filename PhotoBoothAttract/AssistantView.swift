import SwiftUI

struct AssistantView: View {
    var body: some View {
        ZStack {
            Color.blue.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Assistant View")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Primary Display")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
}