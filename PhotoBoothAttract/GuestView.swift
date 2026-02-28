import SwiftUI

struct GuestView: View {
    var body: some View {
        ZStack {
            Color.green.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Guest TV View")
                    .font(.system(size: 100, weight: .black))
                    .foregroundColor(.white)
                
                Text("Secondary Display")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
}