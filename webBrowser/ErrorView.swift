import SwiftUI

struct WebErrorView: View {
    let message: String
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            
            Text("加载失败")
                .font(.title)
                .fontWeight(.bold)
            
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
            
            Button(action: retryAction) {
                Text("重试")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
        .padding()
    }
} 