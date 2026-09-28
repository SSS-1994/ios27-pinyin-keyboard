import Foundation

/// 大词库加载器:从扩展 bundle 读取 Lexicon.json(由 scripts/build_lexicon.py 生成)。
/// 格式:{"拼音或拼音串": ["候选1", "候选2", ...]},数组已按词频降序;
/// key 如 "ni"(单字)或 "ni hao"(词),全拼小写、音节间单空格。
///
/// 内存:JSON 约 1.5MB,解析后约 10–15MB,在键盘扩展预算内;
/// 若目标覆盖老机型(iPhone 11/12),可调小脚本里的 MAX_TOTAL_WORDS 重新生成。
enum Lexicon {
    static let table: [String: [String]]? = {
        let bundle = Bundle(for: KeyboardViewController.self)
        guard let url = bundle.url(forResource: "Lexicon", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String]]
        else { return nil }
        return obj
    }()
}
