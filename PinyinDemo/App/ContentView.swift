import SwiftUI

/// 宿主 App:仅用于承载键盘扩展 —— 提供添加键盘的引导和一个测试输入框。
struct ContentView: View {
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("第一步:添加键盘") {
                    Text("打开 设置 → 通用 → 键盘 → 键盘 → 添加新键盘,在「第三方键盘」里选择「阿帝拼音」。")
                        .font(.footnote)
                    Link(destination: URL(string: UIApplication.openSettingsURLString)!) {
                        Label("打开系统设置", systemImage: "gear")
                    }
                }
                Section("第二步:开始输入") {
                    TextField("点这里唤起键盘", text: $text, axis: .vertical)
                        .lineLimit(1...4)
                    Text(text.isEmpty ? "已输入:(空)" : "已输入:\(text)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("用法") {
                    Label("全拼:字母组合 → 点候选或空格上屏", systemImage: "textformat")
                    Label("九宫格:数字键 → 自动切分拼音出候选", systemImage: "circle.grid.3x3")
                    Label("换行键:组合中原样上屏拼音", systemImage: "arrow.turn.down.left")
                    Label("语音键:设备端听写,开启「完全访问」后可用", systemImage: "mic")
                }
            }
            .navigationTitle("输入法 Demo")
        }
    }
}

#Preview {
    ContentView()
}
