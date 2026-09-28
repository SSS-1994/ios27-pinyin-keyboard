# iOS 27 输入法 Demo(全拼 + 九宫格 + 语音听写)

一个可直接构建运行的 iOS 自定义键盘输入法演示工程:宿主 App + 键盘扩展,实现
**按键 → 拼音/数字组合 → 音节切分 → 候选词 → 上屏** 的完整链路,含:

| 功能 | 说明 |
|---|---|
| 全拼 QWERTY | 输入 `nihao` → 候选「你好 / 你 / 尼…」 |
| 九宫格 T9 | 输入 `64426` → 自动切分出 `nihao` → 候选「你好…」 |
| **真实词库** | 雾凇拼音(rime-ice)开源词库:8705 单字 + 6 万高频词,按词频排序,共 1.45MB |
| **语音听写** | 系统免费 SFSpeechRecognizer,设备端识别(不出设备),点 🎤 开始/结束上屏 |
| 数字符号 | 数字与常用符号直输 |

> 设计文档与完整技术调研见 [docs/调研报告-iOS27输入法.md](docs/调研报告-iOS27输入法.md)。
> 词库数据来自 [雾凇拼音 rime-ice](https://github.com/iDvel/rime-ice),分发前请以其 LICENSE 为准。

---

## 方式一:GitHub 免费云端构建(推荐,无需 Mac)

GitHub **公共仓库** 的 macOS runner 完全免费,仓库已带工作流
[.github/workflows/build-ios.yml](.github/workflows/build-ios.yml)。

1. 把本目录推送到 GitHub **公共仓库**(push 到 `main`/`master` 自动触发,也可手动 `Run workflow`);
2. 等待 Actions 跑完(约 10–20 分钟),在 run 页面底部 **Artifacts** 下载:
   - `unsigned-ipa`:未签名安装包
   - `simulator-screenshot`:模拟器启动验证截图
3. 用你自己的证书签名安装(见下方「签名安装」)。

## 方式二:Mac 本机构建

前置:Mac + Xcode(含 iOS 模拟器 runtime)、XcodeGen(`brew install xcodegen`)。

```bash
cd 输入法
xcodegen generate          # 生成 PinyinDemo.xcodeproj
open PinyinDemo.xcodeproj
```

在 Xcode 里选一个 iPhone 模拟器(如 iPhone 16 Pro,iOS 27),`Cmd+R` 运行。

## 模拟器里启用并测试键盘(关键步骤)

1. 运行后进入 App,点「打开系统设置」;
2. **设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 第三方键盘 → 阿帝拼音**;
3. 回到 App 点输入框唤起键盘,**连按/长按地球键 🌐** 切到「阿帝拼音」;
4. 试试输入 `nihao`、`zhongguo`,或切「九宫」输入 `64426`;
5. 模拟器快捷键:硬件键盘连接时软键盘可能被隐藏 —— 菜单
   **I/O → Keyboard → 取消勾选 Connect Hardware Keyboard**。

## 真机安装(iPhone 16 及以上,iOS 27)

签名安装任选免费路径(产物为 `unsigned-ipa`):

| 工具 | 说明 |
|---|---|
| Sideloadly / AltStore | 免费 Apple ID 签名,证书 7 天有效,到期重签 |
| 爱思助手 | 用你自己的证书签名安装 |
| Xcode 直连 | 手机连 Mac,直接 `Cmd+R` 到真机(免费账号 7 天) |

安装后同样要在 **设置 → 通用 → 键盘** 里添加并允许;「语音输入」「云候选」等
联网功能需开启键盘的 **允许完全访问**(基础拼音输入不需要)。

## 工程结构

```
project.yml                      # XcodeGen 定义(App + 键盘扩展 + 测试)
.github/workflows/build-ios.yml  # 免费云端构建
docs/调研报告-iOS27输入法.md
scripts/
├── build_lexicon.py             # 词库转换:rime-ice .dict.yaml → Lexicon.json
├── download_artifacts.py         # 增量下载最新 ipa 到 download/(升级后手动跑一次)
├── make_icon.py                  # 重新生成 App 图标
└── lint_swift.py                 # 无编译器时的静态粗查(括号/符号引用)
PinyinDemo/
├── App/                         # 宿主 App(SwiftUI)
│   ├── PinyinDemoApp.swift
│   ├── ContentView.swift
│   └── Assets.xcassets/         # 扁平色块风格图标
├── Keyboard/                    # 键盘扩展(app-extension)
│   ├── KeyboardViewController.swift   # UI + 按键逻辑(全拼/九宫格/数字 + 语音集成)
│   ├── PinyinEngine.swift             # 全拼/T9 切分引擎 + 内置兜底小词库
│   ├── Lexicon.swift                  # 大词库懒加载
│   ├── VoiceInputController.swift     # 语音听写(设备端识别、流式上屏)
│   └── Resources/Lexicon.json         # 6 万词条词库(1.45MB,构建词库见下)
└── Tests/                       # CI 冒烟测试(真实加载键盘控制器,回归启动/引擎)
    └── SmokeTests.swift
```

### 重新生成词库(可选)

```bash
# 需要先下载 rime-ice 词库到 .tmp/(8105/base/ext/others.dict.yaml)
python scripts/build_lexicon.py
# 可在脚本顶部调 MAX_TOTAL_WORDS / MAX_WORDS_PER_KEY 控制体积与内存
```

## 语音听写使用说明

- 候选栏右侧 **🎤** 键:点一下开始听写(变红),再点一下结束并把识别结果上屏;
- 听写过程中识别片段实时显示在候选栏,点候选可提前上屏;
- 首次使用需要:①设置里开启键盘的 **允许完全访问**;②允许 **麦克风** 与 **语音识别** 权限(有弹窗引导);
- 识别走系统 **设备端模型**(zh-CN),音频不上传;模拟器可用 Mac 麦克风实测,真机 iPhone 16 效果最佳。

## 常见问题

- **一切到键盘就闪退(宿主 App 跟着被杀)**:真机键盘扩展有 **~69MB jetsam 内存硬上限(不分机型,模拟器不受限)** —— v1.1.0.6 起词库已瘦身至 2 万高频词(0.5MB 文件 / ~5MB 解析内存)并延迟加载,请使用最新包;以后加大词库时请同步控制 `build_lexicon.py` 的 `MAX_TOTAL_WORDS`;
- **键盘白屏后闪回系统键盘**:同上,内存超限被 jetsam 杀掉 —— 扩展是独立进程,注意控制资源(参考调研报告 §3)。
- **键盘四周有灰边**:iOS 26/27 Liquid Glass 容器圆角导致,键盘背景请跟随系统色,不要自绘大圆角。
- **扩展没出现在键盘列表**:确认扩展已随 App 嵌入(PlugIns),bundle id 为宿主 App 的子前缀(工程已配置好)。
- **修改代码后键盘没更新**:杀掉宿主 App 重新聚焦输入框,或重启模拟器。

## 版本号管理

- 版本号统一定义在 [project.yml](project.yml) 的 `MARKETING_VERSION`(如 `1.1.0`)与 `CURRENT_PROJECT_VERSION`(构建号),App 与键盘扩展共用;
- 发新版改这两处再提交,CI 自动打包出 **带版本号的 ipa**:`PinyinKeyboard-v1.1.0.2-unsigned.ipa`;
- 构建产物与版本可在 Actions 运行页的「校验键盘扩展 Info.plist」步骤日志中核对。

## 下一步(v1.0 方向)

1. 用户词与自造词:App Group 存储长句记忆、调频;
2. 体验打磨:按键气泡、模糊音(zh/z、in/ing)、整句输入(可引入 librime);
3. 语音升级:SpeechAnalyzer(iOS 26+ 新 API)、语音免 Fully Access 的降级策略;
4. (可选)上架:付费开发者账号 + 隐私声明 + 审核合规;不上架则自签长期自用。
