import Foundation

/// 大词库加载器:从扩展 bundle 读取 Lexicon.json(由 scripts/build_lexicon.py 生成)。
/// 格式:{"拼音或拼音串": ["候选1", "候选2", ...]},数组已按词频降序;
/// key 如 "ni"(单字)或 "ni hao"(词),全拼小写、音节间单空格。
///
/// 内存:真机键盘扩展有 ~69MB 的 jetsam 硬上限(不分机型,模拟器不受限),
/// 词库已控制在 2 万高频词(约 0.5MB 文件 / 5MB 解析后),加载失败自动回退内置小词库。
enum Lexicon {
    static let table: [String: [String]]? = {
        let bundle = Bundle(for: KeyboardViewController.self)
        guard let url = bundle.url(forResource: "Lexicon", withExtension: "json"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        // autoreleasepool 限定解析峰值:解析完成立即释放原始 buffer 与临时对象
        let parsed: [String: [String]]? = autoreleasepool {
            (try? JSONSerialization.jsonObject(with: data)) as? [String: [String]]
        }
        return parsed
    }()
}
