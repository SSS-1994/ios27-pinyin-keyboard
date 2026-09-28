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
    private var voiceBound = false

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        inputView?.allowsSelfSizing = true
        // 272pt:候选栏 44(触控达标)+ 3 行主键 + 功能行;iPhone 17 全系可用
        view.heightAnchor.constraint(equalToConstant: 272).isActive = true
        setupUI()
        buildKeyboard()
        refreshCandidates()
        // 词库预热延迟 1.5s:启动初期对内存最敏感(真机 jetsam ~69MB),
        // 先让键盘完全稳定显示,再在后台加载词库(瘦身后峰值约 5MB)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { _ = Lexicon.table }
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

        // 候选栏:拼音/数字串(点击可原样上屏)+ 横滚候选 + 语音键
        candidateLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        candidateLabel.textColor = .secondaryLabel
        candidateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        candidateLabel.isUserInteractionEnabled = true
        candidateLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(tapCandidateLabel)))

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
        micButton.widthAnchor.constraint(equalToConstant: 48).isActive = true

        let candidateBar = UIStackView(arrangedSubviews: [candidateLabel, candidateScroll, micButton])
        candidateBar.axis = .horizontal
        candidateBar.spacing = 6
        // 44pt:满足 HIG 最小触控高度
        candidateBar.heightAnchor.constraint(equalToConstant: 44).isActive = true

        // 主键区(3 行,随模式重建)
        keyboardStack.axis = .vertical
        keyboardStack.distribution = .fillEqually
        keyboardStack.spacing = 6

        // 功能行
        let globeButton = key("🌐") { [weak self] in
            guard let self else { return }
            self.composing = ""
            self.stopVoiceIfNeeded()
            self.advanceToNextInputMode()
        }
        configureAsKey(modeButton, fontSize: 16)
        modeButton.addAction(UIAction { [weak self] _ in self?.cycleMode() }, for: .touchUpInside)
        configureAsKey(spaceButton, fontSize: 16)
        spaceButton.addAction(UIAction { [weak self] _ in self?.tapSpace() }, for: .touchUpInside)
        let returnButton = key("换行") { [weak self] in self?.tapReturn() }
        let deleteButton = key("⌫") { [weak self] in self?.tapDelete() }
        // 长按连删:按住 0.4s 后以 0.08s 间隔连删;单击仍只删一个
        deleteButton.addTarget(self, action: #selector(startRepeatDelete), for: .touchDown)
        deleteButton.addTarget(self, action: #selector(stopRepeatDelete),
                               for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let functionRow = UIStackView(arrangedSubviews: [globeButton, modeButton, spaceButton, returnButton, deleteButton])
        functionRow.axis = .horizontal
        functionRow.distribution = .fill
        functionRow.spacing = 6
        // 次要键固定宽,空格吃掉剩余空间(最高频键给最大触控面积)
        globeButton.widthAnchor.constraint(equalToConstant: 44).isActive = true
        modeButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        returnButton.widthAnchor.constraint(equalToConstant: 56).isActive = true
        deleteButton.widthAnchor.constraint(equalToConstant: 44).isActive = true

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
        stopVoiceIfNeeded()
        switch mode {
        case .numbers:
            textDocumentProxy.insertText(payload)
        case .qwerty, .t9:
            // 长度上限防呆:拼音串最长 6 音节,24 字符足够;杜绝极端长度拖慢切分
            if composing.count < 24 {
                composing.append(payload)
            }
            refreshCandidates()
        }
    }

    private func tapSpace() {
        stopVoiceIfNeeded()
        if !composing.isEmpty {
            commit(candidates.first ?? composing)
        } else {
            textDocumentProxy.insertText(" ")
        }
    }

    private func tapReturn() {
        stopVoiceIfNeeded()
        if !composing.isEmpty {
            commit(composing)                 // 组合中原样上屏
        } else {
            textDocumentProxy.insertText("\n")
        }
    }

    private func tapDelete() {
        if suppressNextDelete {
            suppressNextDelete = false      // 长按连删结束的那次抬起,不再多删一个
            return
        }
        stopVoiceIfNeeded()
        if composing.isEmpty {
            textDocumentProxy.deleteBackward()
        } else {
            composing.removeLast()
            refreshCandidates()
        }
    }

    // MARK: - 长按连删

    private var deleteTimer: Timer?
    private var suppressNextDelete = false

    @objc private func startRepeatDelete() {
        deleteTimer?.invalidate()
        deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatDeleteTick()
            self.suppressNextDelete = true   // 松手时的 touchUpInside 不再多删
            self.deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                self?.repeatDeleteTick()
            }
        }
    }

    private func repeatDeleteTick() {
        if voice.isListening { voice.cancel() }
        if composing.isEmpty {
            textDocumentProxy.deleteBackward()
        } else {
            composing.removeLast()
            refreshCandidates()
        }
    }

    @objc private func stopRepeatDelete() {
        deleteTimer?.invalidate()
        deleteTimer = nil
    }

    // MARK: - 点击拼音串原样上屏

    @objc private func tapCandidateLabel() {
        guard !composing.isEmpty else { return }
        stopVoiceIfNeeded()
        commit(composing)
    }

    private func cycleMode() {
        stopVoiceIfNeeded()
        composing = ""
        switch mode {
        case .qwerty: mode = .t9
        case .t9: mode = .numbers
        case .numbers: mode = .qwerty
        }
        buildKeyboard()
        refreshCandidates()
    }

    /// 录音中按下任何输入类按键:先结束听写,避免语音状态与键盘状态错乱
    private func stopVoiceIfNeeded() {
        if voice.isListening { voice.cancel() }
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
        case .t9: nextName = "123"      // 点击后进入数字模式(与 cycleMode 顺序一致)
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

    /// 首次点击 🎤 时才绑定回调与创建语音控制器(键盘启动阶段零语音痕迹)
    private func bindVoiceIfNeeded() {
        guard !voiceBound else { return }
        voiceBound = true
        voice.onListeningChange = { [weak self] listening in
            self?.micButton.backgroundColor = listening ? .systemRed : .systemBackground
        }
        voice.onPartial = { [weak self] text in self?.showVoicePartial(text) }
        voice.onFinal = { [weak self] text in self?.commit(text) }
        voice.onError = { [weak self] message in self?.showAlert("语音输入", message) }
    }

    private func toggleVoice() {
        bindVoiceIfNeeded()
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
