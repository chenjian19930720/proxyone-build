import SwiftUI

struct SplashView: View {
    var onFinish: () -> Void

    @State private var show = false
    @State private var glow = false
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.bgGradient.ignoresSafeArea()

            // 光晕
            Circle()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.55), Theme.accent2.opacity(0.12), .clear],
                                     center: .center, startRadius: 4, endRadius: 190))
                .frame(width: 380, height: 380)
                .scaleEffect(glow ? 1.5 : 0.5)
                .opacity(glow ? 0 : 0.9)

            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Theme.gradient)
                        .frame(width: 100, height: 100)
                        .shadow(color: Theme.accent.opacity(0.55), radius: 34)
                    Image(systemName: "bolt.horizontal.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundColor(.white)
                }
                .scaleEffect(show ? 1 : 0.78)
                .opacity(show ? 1 : 0)

                VStack(spacing: 7) {
                    Text("待续IP系统")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundColor(.white)
                        .tracking(1)
                    Text("定制版 · 全局网络加速")
                        .font(.system(size: 11.5))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(2)
                }
                .opacity(show ? 1 : 0)
                .offset(y: show ? 0 : 10)

                // 进度条
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08)).frame(width: 120, height: 3)
                    Capsule()
                        .fill(Theme.gradient)
                        .frame(width: 120 * progress, height: 3)
                }
                .padding(.top, 12)
                .opacity(show ? 1 : 0)
            }

            VStack {
                Spacer()
                Text("v1.0 · 陈先生定制")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.22))
                    .padding(.bottom, 34)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.75, dampingFraction: 0.72)) { show = true }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { glow = true }
            withAnimation(.easeInOut(duration: 1.5)) { progress = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.75) { onFinish() }
        }
    }
}
