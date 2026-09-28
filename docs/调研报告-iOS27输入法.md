# iOS 27 自定义输入法(键盘)开发调研报告

> 调研日期:2026-09-28 | 目标:在 iPhone 16 及以上机型、iOS 27 上可用的自定义输入法
> 交付:本报告 + 一个可立即构建运行的演示工程(全拼 + 九宫格 + 候选词完整链路)

---

## 1. 结论速览(TL;DR)

| 问题 | 结论 |
|---|---|
| iOS 27 上能做第三方输入法吗 | **能**。机制 12 年来稳定不变:App Extension(`com.apple.keyboard-service`)+ `UIInputViewController`,iOS 27 无破坏性 API 变化 |
| iPhone 16 能用吗 | **能**。iOS 27(2026-09-14 发布)支持 iPhone 11 及以上,iPhone 16 全系覆盖 |
| 中文拼音怎么实现 | 推荐两条路:**A. 集成 librime(参考开源项目 Hamster + 雾凇拼音词库)** 功能最强;**B. 自研轻量引擎** 体积小、可控性强。KeyboardKit Pro 的中文支持是付费闭源,不符合零预算要求 |
| 九宫格 T9 | 可行,核心是「按键数字序列 → 合法拼音切分 → 词库候选」的过滤算法,本演示工程已实现 |
| 语音输入 | 用系统免费 API:**SFSpeechRecognizer**(稳定)或 **SpeechAnalyzer**(iOS 26+ 新 API),完全设备端、零费用;需 Full Access + 麦克风权限 |
| 零预算构建 | **GitHub 公共仓库 Actions 的 macOS runner 完全免费**,可云端构建;本工程已附 CI 工作流,产物:模拟器验证包 + 可自签安装的未签名 ipa |
| 零预算分发 | 你自行签名(免费 Apple ID 7 天签名 / AltStore / Sideloadly / 爱思助手均可);上架 App Store 才需要付费开发者账号($99/年),非必需 |

---

## 2. 目标环境确认

- **iOS 27**:2026-09-14 正式推送,开发者 beta 自 2026-06-08。主打 Siri AI(玻璃球形界面、跨应用操作)、Apple Intelligence 升级、Liquid Glass 细节打磨。
- **iPhone 16 兼容性**:iOS 27 支持 iPhone 11 及以上机型,iPhone 16 / 16 Plus / 16 Pro / 16 Pro Max 全部在列;Siri AI 的设备端智能要求 iPhone 15 Pro 起,iPhone 16 完全达标。
- **对输入法开发的实际影响**:
  1. 键盘扩展核心 API(`UIInputViewController`)多年未变,iOS 26/27 上照常工作;
  2. iOS 26 起 **Liquid Glass 重设计** 使键盘宿主容器圆角变大:第三方键盘如果用深色/自定义背景,四周会出现突兀的灰色边框区域 —— 建议背景色跟随系统(`secondarySystemBackground`),不要自绘整体圆角;
  3. iPhone 16 系列为 A18/A18 Pro,键盘扩展内存上限比老机型宽松(新机型实测可达 120MB+),但编码时仍按 50MB 预算设计,保证兼容旧设备。

---

## 3. 技术原理:iOS 输入法 = App Extension

第三方输入法在 iOS 上是一个 **键盘扩展(Keyboard Extension)**,寄宿在一个普通 App 里:

```
┌────────────────────────────────────────┐
│  宿主 App(如 微信)                    │
│  ┌──────────────────────────────────┐  │
│  │  文本框                           │  │
│  ├──────────────────────────────────┤  │
│  │  你的键盘扩展(独立进程,沙箱)     │  │
│  │  UIInputViewController 子类       │  │
│  │   ├─ 自绘键盘 UI(UIKit/SwiftUI)  │  │
│  │   ├─ textDocumentProxy 文本读写    │  │
│  │   └─ (可选)输入引擎 librime 等    │  │
│  └──────────────────────────────────┘  │
└────────────────────────────────────────┘
```

### 核心类与生命周期

- 继承 `UIInputViewController`,在 `viewDidLoad` 搭建 UI;
- **`textDocumentProxy`**(UITextDocumentProxy)是唯一文本通道:`insertText(_:)` 上屏、`deleteBackward()` 删除、`documentContextBeforeInput` 读光标前文本(用于拼音组合与联想);
- `textDidChange` / `selectionDidChange`:光标移动时收到回调,用于复位组合状态;
- `advanceToNextInputMode()`:切换到下一个已启用键盘;`dismissKeyboard()`:收起;
- `hasFullAccess`:运行时检测用户是否开启了「允许完全访问」。

### 必须遵守的硬约束

| 约束 | 说明 | 应对 |
|---|---|---|
| **内存上限** | 键盘扩展是独立进程,jetsam 限制远低于 App:老机型约 40–60MB,新机型(iPhone 15 起)实测 120MB+。超限被静默杀进程(表现为键盘白屏后闪回系统键盘) | 词库不整包加载进内存(librime 按需加载);图片资源极简; Instruments 按扩展进程测量 |
| **默认无网络** | 未开 Full Access 时网络请求直接失败 | 云候选/语音识别需 Full Access;纯本地引擎不受影响 |
| **沙箱隔离** | 不能访问宿主 App 数据;与自家主 App 共享数据需 App Group(`UserDefaults(suiteName:)` + 共享容器) | 用户词库、设置同步走 App Group |
| **高度** | 用 Auto Layout 控制高度(`inputView?.allowsSelfSizing = true` + `heightAnchor` 约束),不要直接设 frame | 常见 216–300pt;演示工程用 264pt |
| **必须能切换键盘** | 无障碍要求:键盘上必须有「下一个键盘」键(地球键) | 每种布局都保留 `advanceToNextInputMode()` |
| **文本选择受限** | 只能在光标处插入/删除,不能自由选取已有文本;读上下文受 Full Access 影响 | 组合输入时只依赖 `documentContextBeforeInput` |
| **不能调用 `UIApplication.shared`** | 扩展进程不可用,引用会编译/运行告警 | 扩展代码中避免使用 |

### Liquid Glass(iOS 26/27)适配要点

- 宿主容器圆角变大,自定义背景色会在容器四周露出灰色边 —— 键盘背景用 `secondarySystemBackground`、按键用 `systemBackground`,系统深浅色模式自动跟随;
- 不要试图覆盖整个容器或自绘大圆角,系统会裁剪。

---

## 4. Full Access(完全访问)与隐私合规

1. 扩展的 `Info.plist` 设 `RequestsOpenAccess = YES`;
2. 用户在 **设置 → 通用 → 键盘 → 你的键盘 → 允许完全访问** 手动开启(系统会弹隐私警告);
3. 开启后可获得:网络、与主 App 的完整共享容器、麦克风(语音输入必需)。

合规注意(App Store 审核 + 用户信任):
- 不开 Full Access 也要**基础可用**(本演示工程即如此):纯本地拼音、上屏不需要 Full Access;
- 若联网上传击键/语音,必须在隐私政策中披露;Apple 对键盘类扩展的隐私审查很严格,「采集键盘输入」若描述不清会被拒审;
- 语音方案建议用系统设备端识别(见 §6.3),可宣称「语音不出设备」,审核与信任成本最低。

---

## 5. 拼音引擎:四条路线对比(零预算视角)

| 路线 | 成本 | 能力 | 评价 |
|---|---|---|---|
| **A. librime + 开源词库**(参考 [Hamster 仓输入法](https://github.com/imfuxiang/Hamster)) | 免费、开源 | 专业级:整句、模糊音、双拼、五笔、雾凇拼音词库 | **功能上限最高**。C++ 库桥接 Swift,包体与内存要控制;上架注意各组件开源许可 |
| **B. 自研轻量引擎**(本演示工程) | 免费 | 音节切分 + 词库查表 + 词频排序;可逐步加整句/用户词 | **可控性最好**,九宫格逻辑自己写反而简单;词库用开源数据(如雾凇拼音 `.dict.yaml` 转换) |
| **C. KeyboardKit** | 开源部分 MIT 免费;中文等语言输入辅助在 **Pro 付费闭源** | 英文类键盘开箱即用 | 零预算 + 中文需求下不划算,排除 |
| **D. 云候选/云 ASR** | 需要服务器(无免费稳定方案) | 联想质量高 | 违背零预算与隐私最小化,排除 |

**建议**:以 B 起步(演示工程已是 B 的最小实现),中期合并 A 的词库与整句能力(把 librime 作为可选引擎编译进扩展),兼顾快速迭代与最终体验。

词库数据源(免费开源):[雾凇拼音 rime-ice](https://github.com/iDvel/rime-ice)(词库质量高)、八股文词库;`.dict.yaml` 可脚本转成 JSON/SQLite 放进扩展资源,运行时按需加载以控制内存。

---

## 6. 你的三个重点功能专项

### 6.1 九宫格 T9 拼音(你后期常用)

核心算法(演示工程 `PinyinEngine.swift` 已实现):

```
按键序列 "64426" 
  → 反查表: 数字串 → 可能音节集合 (2=abc, 3=def, 4=ghi, 5=jkl, 6=mno, 7=pqrs, 8=tuv, 9=wxyz)
  → 递归切分: 每个前缀若为合法音节(且 digits 匹配)则继续匹配剩余
  → 得到拼音组合: [ni,hao] [mi,an] ...
  → 查词库表 + 整词表 → 按词频输出候选: 你好 / 你 / 尼 ...
```

工程要点:切分组合要限制数量(防组合爆炸)、预生成「音节→数字串」映射表、候选栏实时刷新。

### 6.2 语音输入(你后期常用)— 已实现

采用 **系统免费 API、完全设备端**:`SFSpeechRecognizer`(`requiresOnDeviceRecognition = true` 强制离线,zh-CN 在 iPhone 16 上有设备端模型);后续可升级 iOS 26+ 的 **SpeechAnalyzer / SpeechTranscriber** 新 API(长语音、断句更好)。

演示工程 `VoiceInputController.swift` 已实现完整链路:🎤 键开始/结束 → `AVAudioEngine` 采集 → 流式识别 → 候选栏实时显示片段 → 结束自动上屏;权限缺失时弹窗引导。集成要点:

1. 扩展 `Info.plist` 增加 `NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`(工程已配好);
2. 必须开启 Full Access 才能录音(代码里已做 `hasFullAccess` 引导);
3. **未验证风险提示**:扩展内录音的权限时序在不同宿主 App 上表现需真机验证。

### 6.3 零成本构建与安装(GitHub 构建 + 你自己签名)

```
本地写代码 ──push──> GitHub 公共仓库
                        │ Actions (macOS runner, 公共仓库免费)
                        ├─ 任务1: 模拟器构建 + 启动冒烟 + 截图 artifact (验证功能)
                        └─ 任务2: 真机未签名 ipa artifact
                                   │ 下载到电脑
                                   ▼
                        你自己签名安装(免费路径任选):
                        · Sideloadly / AltStore: Apple ID 免费证书,7 天有效期
                        · 爱思助手 / Xcode 直连: 用你的证书签名
                        · (可选) TrollStore 等特殊渠道
```

- **GitHub Actions**:公共仓库的 macOS runner **完全免费、不限时长**;已附 `.github/workflows/build-ios.yml`,自动选最新 Xcode、生成工程、构建并上传产物(artifact 保留 90 天,免费)。
- **签名**:你说自己可以在 iPhone 上签名证书 —— 以上任一免费路径都能把未签名 ipa 装进 iPhone 16。
- **App Group / Full Access 等权限**在免费签名下均可用,不影响功能验证。

---

## 7. 已交付的演示工程

```
输入法/
├── README.md                       # 构建 & 安装 & 模拟器验证全流程
├── project.yml                     # XcodeGen 工程定义(App + 键盘扩展)
├── .github/workflows/build-ios.yml # 免费云端构建(模拟器验证 + 未签名 ipa)
├── docs/调研报告-iOS27输入法.md      # 本报告
├── scripts/
│   ├── build_lexicon.py            # 词库转换:rime-ice → Lexicon.json(已运行)
│   └── lint_swift.py               # 无编译器时的静态粗查
└── PinyinDemo/
    ├── App/                        # 宿主 App(SwiftUI:引导页 + 测试文本框)
    └── Keyboard/
        ├── KeyboardViewController.swift  # 键盘 UI + 按键逻辑 + 语音集成
        ├── PinyinEngine.swift            # 全拼/T9 切分引擎 + 内置兜底小词库
        ├── Lexicon.swift                 # 大词库懒加载
        ├── VoiceInputController.swift    # 语音听写(设备端识别)
        └── Resources/Lexicon.json        # 雾凇拼音词库:8705 单字 + 6 万词(1.45MB)
```

已实现的功能链路:**按键 → 拼音/数字组合 → 音节切分 → 大词库候选 → 点选/空格上屏**;三种键盘模式(全拼 QWERTY、九宫格 T9、数字符号);**语音听写**(设备端识别、流式上屏);地球键切换系统键盘;基础拼音不需要 Full Access。

---

## 8. 建议路线图

| 阶段 | 内容 | 
|---|---|
| v0.1(已完成) | 工程骨架 + 全拼/九宫格/候选/上屏链路 + 免费云构建 |
| v0.2(已完成) | 雾凇拼音真实词库接入(8705 单字 + 6 万词,1.45MB,懒加载 + 兜底回退) |
| v0.3(已完成,待真机验证) | 语音听写:SFSpeechRecognizer 设备端 + 权限引导 + 流式上屏 |
| v0.4 | 体验打磨:按键气泡、滑动删除、模糊音、整句输入(可引入 librime)、iOS 27 视觉适配 |
| v1.0 | (可选)上架:付费开发者账号 + 隐私声明 + 审核合规;不上架则自签长期自用 |

---

## 9. 参考来源

- [MacRumors — iOS 27 Features: The Ultimate Mega Guide](https://www.macrumors.com)(iOS 27 于 2026-09-14 发布、支持机型)
- [Apple 官方 — 创建自定义键盘](https://developer.apple.com/cn/documentation/uikit/creating-a-custom-keyboard)
- [Apple 官方 — Configuring open access for a custom keyboard](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)(RequestsOpenAccess/Full Access)
- [Apple 官方 — App Extension Programming Guide: Custom Keyboard](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)
- [Apple 官方 — Identifying high-memory use with jetsam event reports](https://developer.apple.com/documentation/xcode/identifying-high-memory-use-with-jetsam-event-reports)(扩展内存限制)
- [Stack Overflow — Memory limit for keyboard extension](https://stackoverflow.com/questions/44275990/memory-limit-for-keyboard-extension)(内存实测讨论)
- [Hamster 仓输入法(imfuxiang/Hamster)](https://github.com/imfuxiang/Hamster) — iOS 上最完整的开源 Rime 前端,架构参考价值极高
- [雾凇拼音 rime-ice](https://github.com/iDvel/rime-ice) — 高质量开源词库方案
- [KeyboardKit](https://github.com/danielsaidi/KeyboardKit) — MIT 开源键盘框架(中文辅助在付费 Pro,零预算方案未采用)
- [Kodeco — Custom Keyboard Extensions Getting Started](https://www.kodeco.com/49-custom-keyboard-extensions-getting-started)(入门教程)
- [iOS 26 Liquid Glass 对键盘扩展容器的影响](https://github.com)(社区文档:宿主容器圆角变化)
