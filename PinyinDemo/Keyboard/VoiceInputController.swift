import AVFoundation
import Speech

/// 语音听写:系统 SFSpeechRecognizer,优先完全设备端识别(zh-CN,不出设备、零费用)。
/// 前提:用户已给键盘开启「完全访问」(Full Access),并允许麦克风与语音识别权限。
/// 用法:onPartial 刷新候选栏,onFinal 直接上屏;start() 开始 / finish() 结束并上屏 / cancel() 放弃。
final class VoiceInputController: NSObject {

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onListeningChange: ((Bool) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))

    var isListening: Bool { audioEngine.isRunning }

    // MARK: - 对外控制

    func start() {
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
        guard isListening else { return }
        request?.endAudio()
        teardownAudio()
        onListeningChange?(false)
    }

    /// 放弃当前听写
    func cancel() {
        task?.cancel()
        teardownAudio()
        cleanupSession()
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
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if recognizer?.supportsOnDeviceRecognition == true {
                request.requiresOnDeviceRecognition = true   // 隐私优先:强制离线识别
            }
            self.request = request

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak request] buffer, _ in
                request?.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()

            task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if result.isFinal {
                        if !text.isEmpty { self.onFinal?(text) }
                        self.cleanupSession()
                    } else {
                        self.onPartial?(text)
                    }
                }
                if error != nil {
                    self.onError?("识别中断,请重试")
                    self.cleanupSession()
                }
            }
            onListeningChange?(true)
        } catch {
            onError?("无法启动麦克风:\(error.localizedDescription)")
            cleanupSession()
        }
    }

    /// 停止采集音频(识别任务继续,直到 isFinal 回调)
    private func teardownAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 释放任务并复位状态
    private func cleanupSession() {
        request = nil
        task = nil
        onListeningChange?(false)
    }
}
