import UIKit

/// 自定义键盘主控制器 —— 继承 UIInputViewController。
/// 三种模式:全拼 QWERTY、九宫格 T9、数字符号;组合输入 → 候选 → 上屏的完整链路。
/// 注意:扩展进程里不能使用 UIApplication.shared;内存预算按 ~50MB 设计。
final class KeyboardViewController: UIInputViewController {

    private enum Mode { case qwerty, t9, numbers }

    // MARK: - 状态

    private var mode: Mode = .qwerty
    private var composing = ""        // 正在组合的拼音串(全拼)或数字串(九宫格)
    private var candidates: [String] = []

    // MARK: - UI

    private let candidateLabel = UILabel()
    private let candidateStack = UIStackView()
    private let keyboardStack = UIStackView()
    private let modeButton = UIButton(type: .system)
    private let spaceButton = UIButton(type: .system)
    private let micButton = UIButton(type: .system)
    /// 延迟创建:键盘扩展启动阶段不初始化任何语音框架(闪退加固)
    private lazy var voice = VoiceInputController()

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView?.allowsSelfSizing = true
        view.heightAnchor.constraint(equalToConstant: 264).isActive = true
        bindVoiceCallbacks()
        setupUI()
        buildKeyboard()
        refreshCandidates()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        voice.cancel()
    }

    /// 光标被外部改变(移动/切输入框)时复位组合状态
    override func textDidChange(_ textInput: UITextInput?) {
        composing = ""
        refreshCandidates()
    }

    // MARK: - 布局搭建

    private func setupUI() {
        view.backgroundColor = .secondarySystemBackground

        // 候选栏:拼音/数字串 + 横滚候选 + 语音键
        candidateLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        candidateLabel.textColor = .secondaryLabel
        candidateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        candidateStack.axis = .horizontal
        candidateStack.spacing = 2

        let candidateScroll = UIScrollView()
        candidateScroll.showsHorizontalScrollIndicator = false
        candidateScroll.addSubview(candidateStack)
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            candidateStack.topAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.bottomAnchor),
            candidateStack.leadingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.leadingAnchor, constant: 4),
            candidateStack.trailingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.trailingAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateScroll.frameLayoutGuide.heightAnchor),
        ])

        configureAsKey(micButton, fontSize: 18)
        micButton.setTitle("🎤", for: .normal)
        micButton.addAction(UIAction { [weak self] _ in self?.toggleVoice() }, for: .touchUpInside)
        micButton.widthAnchor.constraint(equalToConstant: 40).isActive = true

        let candidateBar = UIStackView(arrangedSubviews: [candidateLabel, candidateScroll, micButton])
        candidateBar.axis = .horizontal
        candidateBar.spacing = 6
        candidateBar.heightAnchor.constraint(equalToConstant: 36).isActive = true

        // 主键区(3 行,随模式重建)
        keyboardStack.axis = .vertical
        keyboardStack.distribution = .fillEqually
        keyboardStack.spacing = 6

        // 功能行
        let globeButton = key("🌐") { [weak self] in
            guard let self else { return }
            self.composing = ""
            self.voice.cancel()
            self.advanceToNextInputMode()
        }
        configureAsKey(modeButton, fontSize: 16)
        modeButton.addAction(UIAction { [weak self] _ in self?.cycleMode() }, for: .touchUpInside)
        configureAsKey(spaceButton, fontSize: 16)
        spaceButton.addAction(UIAction { [weak self] _ in self?.tapSpace() }, for: .touchUpInside)
        let returnButton = key("换行") { [weak self] in self?.tapReturn() }
        let deleteButton = key("⌫") { [weak self] in self?.tapDelete() }

        let functionRow = UIStackView(arrangedSubviews: [globeButton, modeButton, spaceButton, returnButton, deleteButton])
        functionRow.axis = .horizontal
        functionRow.distribution = .fillEqually
        functionRow.spacing = 6

        // 竖向主栈
        let main = UIStackView(arrangedSubviews: [candidateBar, keyboardStack, functionRow])
        main.axis = .vertical
        main.spacing = 8
        main.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            main.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            main.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            main.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
        ])
    }

    /// 按模式重建主键区
    private func buildKeyboard() {
        keyboardStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        func letterRow(_ titles: [String], payloads: [String]? = nil) -> UIStackView {
            let keys = zip(titles, payloads ?? titles).map { title, payload in
                key(title, fontSize: mode == .t9 ? 16 : 20) { [weak self] in self?.tapChar(payload) }
            }
            let s = UIStackView(arrangedSubviews: keys)
            s.axis = .horizontal
            s.distribution = .fillEqually
            s.spacing = 6
            return s
        }

        switch mode {
        case .qwerty:
            keyboardStack.addArrangedSubview(letterRow("qwertyuiop".map(String.init)))
            keyboardStack.addArrangedSubview(letterRow("asdfghjkl".map(String.init)))
            keyboardStack.addArrangedSubview(letterRow("zxcvbnm".map(String.init)))
        case .t9:
            keyboardStack.addArrangedSubview(letterRow(["1", "2 abc", "3 def"], payloads: ["1", "2", "3"]))
            keyboardStack.addArrangedSubview(letterRow(["4 ghi", "5 jkl", "6 mno"], payloads: ["4", "5", "6"]))
            keyboardStack.addArrangedSubview(letterRow(["7 pqrs", "8 tuv", "9 wxyz"], payloads: ["7", "8", "9"]))
        case .numbers:
            keyboardStack.addArrangedSubview(letterRow(["1", "2", "3", "4", "5"]))
            keyboardStack.addArrangedSubview(letterRow(["6", "7", "8", "9", "0"]))
            keyboardStack.addArrangedSubview(letterRow(["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""]))
        }
    }

    // MARK: - 按键处理

    private func tapChar(_ payload: String) {
        if voice.isListening { voice.cancel() }
        switch mode {
        case .numbers:
            textDocumentProxy.insertText(payload)
        case .qwerty, .t9:
            composing.append(payload)
            refreshCandidates()
        }
    }

    private func tapSpace() {
        if !composing.isEmpty {
            commit(candidates.first ?? composing)
        } else {
            textDocumentProxy.insertText(" ")
        }
    }

    private func tapReturn() {
        if !composing.isEmpty {
            commit(composing)                 // 组合中原样上屏
        } else {
            textDocumentProxy.insertText("\n")
        }
    }

    private func tapDelete() {
        if voice.isListening { voice.cancel() }
        if composing.isEmpty {
            textDocumentProxy.deleteBackward()
        } else {
            composing.removeLast()
            refreshCandidates()
        }
    }

    private func cycleMode() {
        composing = ""
        switch mode {
        case .qwerty: mode = .t9
        case .t9: mode = .numbers
        case .numbers: mode = .qwerty
        }
        buildKeyboard()
        refreshCandidates()
    }

    private func commit(_ text: String) {
        textDocumentProxy.insertText(text)
        composing = ""
        refreshCandidates()
    }

    // MARK: - 候选刷新

    private func refreshCandidates() {
        candidates = composing.isEmpty ? [] : computeCandidates(for: composing)
        rebuildCandidateButtons()
        candidateLabel.text = composing
        spaceButton.setTitle(composing.isEmpty ? "空格" : (candidates.first ?? "上屏"), for: .normal)
        let nextName: String
        switch mode {
        case .qwerty: nextName = "九宫"
        case .t9: nextName = "ABC"
        case .numbers: nextName = "全拼"
        }
        modeButton.setTitle(nextName, for: .normal)
    }

    private func computeCandidates(for input: String) -> [String] {
        mode == .t9 ? PinyinEngine.t9Candidates(input) : PinyinEngine.qwertyCandidates(input)
    }

    private func rebuildCandidateButtons() {
        candidateStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for word in candidates.prefix(8) {
            let b = UIButton(type: .system)
            b.setTitle(word, for: .normal)
            b.tintColor = .label
            b.titleLabel?.font = .systemFont(ofSize: 17)
            b.addAction(UIAction { [weak self] _ in self?.commit(word) }, for: .touchUpInside)
            candidateStack.addArrangedSubview(b)
        }
    }

    // MARK: - 语音输入(SFSpeechRecognizer 设备端识别,详见调研报告 §6.2)

    private func bindVoiceCallbacks() {
        voice.onListeningChange = { [weak self] listening in
            self?.micButton.backgroundColor = listening ? .systemRed : .systemBackground
        }
        voice.onPartial = { [weak self] text in self?.showVoicePartial(text) }
        voice.onFinal = { [weak self] text in self?.commit(text) }
        voice.onError = { [weak self] message in self?.showAlert("语音输入", message) }
    }

    private func toggleVoice() {
        if voice.isListening {
            voice.finish()
            return
        }
        guard hasFullAccess else {
            showAlert("需要「完全访问」",
                      "语音听写需要系统权限:设置 → 通用 → 键盘 → 键盘 → 阿帝拼音 → 开启「允许完全访问」,并在弹窗中允许麦克风与语音识别。")
            return
        }
        composing = ""
        voice.start()
    }

    private func showVoicePartial(_ text: String) {
        candidateLabel.text = "🎤 听写中"
        candidateStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !text.isEmpty else {
            candidateStack.addArrangedSubview(passiveLabel("(请说话…)"))
            return
        }
        let b = UIButton(type: .system)
        b.setTitle("「\(text)」上屏", for: .normal)
        b.tintColor = .label
        b.titleLabel?.font = .systemFont(ofSize: 17)
        b.addAction(UIAction { [weak self] _ in self?.commit(text) }, for: .touchUpInside)
        candidateStack.addArrangedSubview(b)
    }

    private func passiveLabel(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.font = .systemFont(ofSize: 15)
        l.textColor = .secondaryLabel
        return l
    }

    private func showAlert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

    // MARK: - 控件工厂

    private func configureAsKey(_ b: UIButton, fontSize: CGFloat = 20) {
        b.titleLabel?.font = .systemFont(ofSize: fontSize)
        b.tintColor = .label
        b.backgroundColor = .systemBackground
        b.layer.cornerRadius = 6
    }

    private func key(_ title: String, fontSize: CGFloat = 20,
                     handler: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        configureAsKey(b, fontSize: fontSize)
        b.addAction(UIAction { _ in handler() }, for: .touchUpInside)
        return b
    }
}
