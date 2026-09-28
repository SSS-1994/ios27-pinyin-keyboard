import AVFoundation
import Speech

/// 语音听写:系统 SFSpeechRecognizer,优先完全设备端识别(zh-CN,不出设备、零费用)。
/// 前提:用户已给键盘开启「完全访问」(Full Access),并允许麦克风与语音识别权限。
/// 用法:onPartial 刷新候选栏,onFinal 直接上屏;start() 开始 / finish() 结束并上屏 / cancel() 放弃。
/// 注意:所有重量级资源(AVAudioEngine/SFSpeechRecognizer)全部延迟创建,
/// 保证键盘扩展进程启动阶段不触碰语音框架(闪退加固)。
final class VoiceInputController: NSObject {

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onListeningChange: ((Bool) -> Void)?

    private lazy var audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private lazy var recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private var tapInstalled = false

    private(set) var listening = false
    var isListening: Bool { listening }

    /// 识别回调可能来自后台线程:UI 更新与 textDocumentProxy 操作必须回到主线程
    private func emit(_ fire: @escaping () -> Void) {
        if Thread.isMainThread {
            fire()
        } else {
            DispatchQueue.main.async(execute: fire)
        }
    }

    deinit {
        // 只有真正开启过会话才需要清理(避免强制创建 lazy 资源)
        if request != nil || task != nil {
            teardownAudio()
            request = nil
            task = nil
        }
    }

    // MARK: - 对外控制

    func start() {
        guard !listening else { return }
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micGranted = AVAudioSession.sharedInstance().recordPermission == .granted
        if speechStatus == .authorized && micGranted {
            beginSession()
            return
        }
        requestPermissions { [weak self] ok in
            if ok {
                self?.beginSession()
            } else {
                self?.onError?("需要麦克风与语音识别权限:请开启键盘的「允许完全访问」后在弹窗中允许。")
            }
        }
    }

    /// 结束录音,等待最终识别结果上屏
    func finish() {
        guard listening else { return }
        request?.endAudio()
        teardownAudio()
        setListening(false)
    }

    /// 放弃当前听写(主线程调用)
    func cancel() {
        task?.cancel()
        if request != nil || task != nil || tapInstalled { teardownAudio() }
        request = nil
        task = nil
        setListening(false)
    }

    // MARK: - 内部实现

    private func requestPermissions(_ completion: @escaping (Bool) -> Void) {
        let group = DispatchGroup()
        var micOK = false
        var speechOK = false
        group.enter()
        AVAudioSession.sharedInstance().requestRecordPermission { ok in
            micOK = ok
            group.leave()
        }
        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            speechOK = status == .authorized
            group.leave()
        }
        group.notify(queue: .main) { completion(micOK && speechOK) }
    }

    private func beginSession() {
        // 隐私优先:仅设备端识别。设备无 zh-CN 离线模型时明确报错,而不是让用户干等
        guard let recognizer, recognizer.supportsOnDeviceRecognition == true else {
            onError?("当前设备不支持中文离线语音识别,已取消。")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = true   // 强制完全离线,音频不出设备
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            tapInstalled = true
            audioEngine.prepare()
            try audioEngine.start()

            // 识别结果回调在后台线程:一律 emit 回主线程后再碰 UI / textDocumentProxy
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if result.isFinal {
                        self.emit { [weak self] in
                            guard let self else { return }
                            if !text.isEmpty { self.onFinal?(text) }
                            self.cancel()             // 主线程收尾清理
                        }
                    } else {
                        self.emit { [weak self] in self?.onPartial?(text) }
                    }
                }
                if error != nil {
                    self.emit { [weak self] in
                        guard let self else { return }
                        self.onError?("识别中断,请重试")
                        self.cancel()
                    }
                }
            }
            setListening(true)
        } catch {
            onError?("无法启动麦克风:\(error.localizedDescription)")
            cancel()
        }
    }

    private func setListening(_ value: Bool) {
        listening = value
        onListeningChange?(value)
    }

    /// 停止采集音频(识别任务继续,直到 isFinal 回调);可安全重复调用
    private func teardownAudio() {
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        audioEngine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
