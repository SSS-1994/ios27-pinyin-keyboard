import UIKit
import XCTest

/// 键盘扩展冒烟测试:在模拟器进程里真实实例化键盘控制器并跑完 viewDidLoad,
/// 自动捕获启动期崩溃(如布局、初始化问题);同时回归拼音引擎与词库。
final class SmokeTests: XCTestCase {

    /// 键盘控制器完整加载不崩溃(切换键盘闪退的第一道防线)
    func testKeyboardViewDidLoadDoesNotCrash() {
        let vc = KeyboardViewController()
        vc.loadViewIfNeeded()
        XCTAssertNotNil(vc.view)
        XCTAssertGreaterThan(vc.view.subviews.count, 0)
    }

    /// 连续创建多个实例(模拟反复切换键盘)
    func testRepeatedInstantiation() {
        for _ in 0..<5 {
            let vc = KeyboardViewController()
            vc.loadViewIfNeeded()
        }
    }

    func testQwertyCandidates() {
        XCTAssertTrue(PinyinEngine.qwertyCandidates("nihao").contains("你好"))
        XCTAssertTrue(PinyinEngine.qwertyCandidates("shi").contains("是"))
        XCTAssertFalse(PinyinEngine.qwertyCandidates("zhongguo").isEmpty)
    }

    func testT9Candidates() {
        XCTAssertTrue(PinyinEngine.t9Candidates("64426").contains("你好"))
        XCTAssertFalse(PinyinEngine.t9Candidates("64").isEmpty)
        XCTAssertFalse(PinyinEngine.t9Candidates("9482").isEmpty)
    }

    func testLexiconLoaded() {
        let table = Lexicon.table
        XCTAssertNotNil(table, "Lexicon.json 未加载,请检查 test target 资源")
        XCTAssertEqual(table?["ni hao"]?.first, "你好")
        XCTAssertGreaterThan(table?.count ?? 0, 10000, "词库条目异常偏少")
    }
}
