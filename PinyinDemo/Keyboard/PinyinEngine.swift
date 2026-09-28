import Foundation

/// 迷你拼音引擎 —— 演示「按键 → 音节切分 → 词库候选」的完整链路。
/// 全拼与九宫格(T9)共用一套词库;正式版请替换为雾凇拼音等开源大词库(见 docs/调研报告 §5)。
enum PinyinEngine {

    // MARK: - 全拼音节表(用于切分,覆盖普通话合法音节)

    static let syllables: Set<String> = [
        "a", "ai", "an", "ang", "ao",
        "ba", "bai", "ban", "bang", "bao", "bei", "ben", "beng", "bi", "bian", "biao", "bin", "bing", "bo", "bu",
        "ca", "cai", "can", "cang", "cao", "ce", "cen", "ceng", "cha", "chai", "chan", "chang", "chao", "che",
        "chen", "cheng", "chi", "chong", "chou", "chu", "chua", "chuan", "chuang", "chui", "chun", "chuo",
        "ci", "cong", "cou", "cu", "cuan", "cui", "cun", "cuo",
        "da", "dai", "dan", "dang", "dao", "de", "dei", "den", "deng", "di", "dia", "dian", "diao", "die",
        "ding", "diu", "dong", "dou", "du", "duan", "dui", "dun", "duo",
        "e", "ei", "en", "eng", "er",
        "fa", "fan", "fang", "fei", "fen", "feng", "fo", "fou", "fu",
        "ga", "gai", "gan", "gang", "gao", "ge", "gei", "gen", "geng", "gong", "gou", "gu", "gua", "guai",
        "guan", "guang", "gui", "gun", "guo",
        "ha", "hai", "han", "hang", "hao", "he", "hei", "hen", "heng", "hong", "hou", "hu", "hua", "huai",
        "huan", "huang", "hui", "hun", "huo",
        "ji", "jia", "jian", "jiang", "jiao", "jie", "jin", "jing", "jiong", "jiu", "ju", "juan", "jue", "jun",
        "ka", "kai", "kan", "kang", "kao", "ke", "kei", "ken", "keng", "kong", "kou", "ku", "kua", "kuai",
        "kuan", "kuang", "kui", "kun", "kuo",
        "la", "lai", "lan", "lang", "lao", "le", "lei", "leng", "li", "lia", "lian", "liang", "liao", "lie",
        "lin", "ling", "liu", "lo", "long", "lou", "lu", "luan", "lun", "luo",
        "ma", "mai", "man", "mang", "mao", "me", "mei", "men", "meng", "mi", "mian", "miao", "mie", "min",
        "ming", "miu", "mo", "mou", "mu",
        "na", "nai", "nan", "nang", "nao", "ne", "nei", "nen", "neng", "ni", "nian", "niang", "niao", "nie",
        "nin", "ning", "niu", "nong", "nou", "nu", "nuan", "nuo", "nun",
        "o", "ou",
        "pa", "pai", "pan", "pang", "pao", "pei", "pen", "peng", "pi", "pian", "piao", "pie", "pin", "ping",
        "po", "pou", "pu",
        "qi", "qia", "qian", "qiang", "qiao", "qie", "qin", "qing", "qiong", "qiu", "qu", "quan", "que", "qun",
        "ran", "rang", "rao", "re", "ren", "reng", "ri", "rong", "rou", "ru", "rua", "ruan", "rui", "run", "ruo",
        "sa", "sai", "san", "sang", "sao", "se", "sen", "seng", "sha", "shai", "shan", "shang", "shao", "she",
        "shei", "shen", "sheng", "shi", "shou", "shu", "shua", "shuai", "shuan", "shuang", "shui", "shun", "shuo",
        "si", "song", "sou", "su", "suan", "sui", "sun", "suo",
        "ta", "tai", "tan", "tang", "tao", "te", "teng", "ti", "tian", "tiao", "tie", "ting", "tong", "tou",
        "tu", "tuan", "tui", "tun", "tuo",
        "wa", "wai", "wan", "wang", "wei", "wen", "weng", "wo", "wu",
        "xi", "xia", "xian", "xiang", "xiao", "xie", "xin", "xing", "xiong", "xiu", "xu", "xuan", "xue", "xun",
        "ya", "yan", "yang", "yao", "ye", "yi", "yin", "ying", "yo", "yong", "you", "yu", "yuan", "yue", "yun",
        "za", "zai", "zan", "zang", "zao", "ze", "zei", "zen", "zeng", "zha", "zhai", "zhan", "zhang", "zhao",
        "zhe", "zhen", "zheng", "zhi", "zhong", "zhou", "zhu", "zhua", "zhuai", "zhuan", "zhuang", "zhui",
        "zhun", "zhuo", "zi", "zong", "zou", "zu", "zuan", "zui", "zun", "zuo",
    ]

    // MARK: - 词库:音节 → 候选字(按词频降序)

    static let charTable: [String: [String]] = [
        "a": ["啊", "阿"], "ai": ["爱", "哀", "挨"], "an": ["安", "按"], "ang": ["昂"],
        "ba": ["把", "八", "吧", "爸"], "bai": ["白", "百"], "ban": ["半", "办", "班", "板"],
        "bang": ["帮", "棒", "榜"], "bao": ["报", "包", "保"], "bei": ["北", "被", "备", "倍", "杯"],
        "ben": ["本"], "bi": ["比", "笔", "必", "毕"], "bian": ["边", "变", "便", "遍", "辩"],
        "biao": ["表", "标"], "bing": ["并", "病", "冰"], "bu": ["不", "布", "步", "部"],
        "cai": ["才", "菜", "材"], "can": ["参", "餐"], "ceng": ["层"], "cha": ["茶", "查", "差"],
        "chan": ["产"], "chang": ["常", "长", "场", "厂", "唱"], "chao": ["超", "朝"], "che": ["车"],
        "cheng": ["成", "城", "程", "称", "承", "诚"], "chi": ["吃", "池", "迟", "尺"], "chu": ["出", "初", "处"],
        "chuan": ["船", "传"], "ci": ["次", "词", "此"], "cong": ["从"], "cuo": ["错"],
        "da": ["大", "打", "达", "答"], "dai": ["代", "带", "待", "带"], "dan": ["但", "单", "蛋"],
        "dang": ["当", "党"], "dao": ["到", "道", "岛", "刀", "倒"], "de": ["的", "得", "地", "德"],
        "deng": ["等", "灯"], "di": ["地", "第", "低", "底"], "dian": ["电", "点", "店", "垫", "典"],
        "diao": ["调"], "dong": ["东", "动", "冬", "懂"], "dou": ["都", "斗"], "du": ["读", "度", "独", "都"],
        "duan": ["短", "断"], "dui": ["对", "队", "堆", "兑"], "duo": ["多", "朵"],
        "e": ["额", "俄"], "er": ["二", "而", "儿", "耳", "尔"],
        "fa": ["发", "法"], "fan": ["饭", "反", "犯", "翻", "范"], "fang": ["方", "放", "房", "防"],
        "fei": ["非", "飞", "费", "肥", "废"], "fen": ["分", "份", "粉", "奋"], "feng": ["风", "封", "丰"],
        "fu": ["服", "夫", "付", "复", "福"],
        "gai": ["该", "改"], "gan": ["干", "敢", "感", "赶", "甘"], "gang": ["刚", "钢", "港"],
        "gao": ["高", "告"], "ge": ["个", "各", "格", "歌", "哥"], "gei": ["给"],
        "gen": ["跟", "根"], "gong": ["公", "工", "共", "功", "宫", "供", "攻"], "gu": ["古", "故", "顾"],
        "gua": ["瓜", "挂", "刮"], "guan": ["关", "管", "馆", "观"], "guang": ["光", "广"],
        "gui": ["贵", "规", "归"], "guo": ["国", "果", "过", "锅", "郭"],
        "hai": ["海", "还", "害", "孩"], "han": ["汉", "含", "寒"], "hao": ["好", "号", "浩", "豪", "毫"],
        "he": ["和", "何", "合", "河", "贺"], "hei": ["黑"], "hen": ["很", "狠", "恨"],
        "heng": ["横", "衡"], "hong": ["红", "洪"], "hou": ["后", "候", "猴", "厚"], "hu": ["湖", "户", "互"],
        "hua": ["话", "花", "化", "华", "画"], "huai": ["坏", "怀"], "huan": ["还", "环", "换", "欢", "幻"],
        "hui": ["会", "回", "汇", "慧", "毁"], "huo": ["活", "火", "货", "或"],
        "ji": ["机", "级", "极", "几", "计", "记", "际", "济", "技"], "jia": ["家", "加", "价", "佳", "假", "甲"],
        "jian": ["见", "间", "件", "建", "简", "减", "检", "键"], "jiang": ["将", "江", "讲", "奖", "降"],
        "jiao": ["叫", "教", "交", "角", "脚"], "jie": ["接", "界", "届", "姐", "结", "解", "街", "节", "杰"],
        "jin": ["进", "近", "金", "今", "仅", "紧"], "jing": ["经", "京", "精", "静", "境", "镜"],
        "jiu": ["就", "九", "久", "旧", "酒", "救"], "ju": ["句", "局", "举", "具"], "jue": ["觉", "决", "绝"],
        "jun": ["军", "均"],
        "ka": ["卡", "咖"], "kai": ["开", "凯", "慨"], "kan": ["看", "刊", "砍", "堪"], "ke": ["可", "科", "刻", "客", "克", "课"],
        "kong": ["空", "恐", "控"], "kou": ["口"], "ku": ["苦", "库"], "kuai": ["快", "块"],
        "la": ["拉", "啦"], "lai": ["来", "莱", "赖"], "lao": ["老", "劳", "牢"], "le": ["了", "乐", "勒"],
        "lei": ["类", "累", "泪"], "li": ["里", "力", "利", "理", "离", "例"], "lian": ["连", "联", "脸", "练"],
        "liang": ["两", "亮", "凉", "量"], "liao": ["料", "聊"], "lin": ["林", "淋", "邻"], "ling": ["零", "另", "领", "龄", "令"],
        "liu": ["六", "流", "刘", "留"], "long": ["龙", "隆", "笼"], "lu": ["路", "露", "卢"], "lv": ["绿", "旅", "律"],
        "ma": ["马", "吗", "妈", "码", "嘛"], "mai": ["买", "卖", "迈"], "man": ["满", "慢", "忙"],
        "mao": ["猫", "毛", "冒"], "mei": ["没", "每", "美", "妹", "梅"], "men": ["们", "门", "闷"],
        "mi": ["米", "密", "迷", "蜜", "秘"], "mian": ["面", "棉", "免", "勉"], "ming": ["名", "明", "命", "鸣", "铭"],
        "mo": ["模", "莫", "末", "磨"], "mu": ["木", "母", "目", "幕"],
        "na": ["那", "拿", "哪"], "nai": ["奶", "耐"], "nan": ["南", "男", "难"], "nao": ["脑", "闹"],
        "ne": ["呢"], "nei": ["内"], "neng": ["能"], "ni": ["你", "尼", "拟", "逆"],
        "nian": ["年", "念"], "nin": ["您"], "ning": ["宁"], "niu": ["牛"], "nong": ["农", "浓"],
        "pai": ["拍", "排", "牌"], "pan": ["盘", "判"], "pang": ["旁", "胖", "庞"], "pao": ["跑", "炮", "泡"],
        "pei": ["配", "陪", "培"], "peng": ["朋", "碰", "捧", "鹏", "棚"], "pi": ["皮", "批", "屁"],
        "pian": ["片", "篇", "骗"], "piao": ["票", "漂", "飘"], "ping": ["平", "评", "瓶", "苹"],
        "po": ["破", "坡"], "pu": ["普", "铺", "朴"],
        "qi": ["七", "其", "气", "汽", "期", "齐", "奇"], "qian": ["前", "千", "钱", "浅", "签", "牵"],
        "qiang": ["强", "墙", "枪"], "qiao": ["桥", "巧"], "qie": ["切", "且"], "qin": ["亲", "琴", "勤"],
        "qing": ["请", "情", "清", "青", "轻", "庆"], "qiu": ["求", "球", "秋"], "qu": ["去", "取", "曲", "趣", "屈"],
        "quan": ["全", "权", "圈"], "que": ["却", "缺", "确"], "qun": ["群", "裙"],
        "ran": ["然", "燃"], "rang": ["让", "壤"], "re": ["热"], "ren": ["人", "仁", "任", "认"],
        "rong": ["容", "融", "荣"], "rou": ["肉"], "ru": ["如", "入"], "ruo": ["若", "弱"],
        "sa": ["撒"], "san": ["三", "散", "伞"], "se": ["色", "涩"], "sha": ["沙", "傻", "杀"],
        "shan": ["山", "善", "衫"], "shang": ["上", "商", "伤", "尚"], "shao": ["少", "烧", "勺"],
        "she": ["社", "设", "蛇", "舍"], "shen": ["深", "身", "神", "审", "什"], "sheng": ["生", "声", "胜", "升", "剩"],
        "shi": ["是", "时", "市", "事", "师", "使", "世"], "shou": ["手", "受", "首", "收", "守"],
        "shu": ["书", "数", "树", "术", "述"], "shua": ["刷"], "shuai": ["帅", "摔"], "shui": ["水", "睡", "谁"],
        "shuo": ["说", "硕"], "si": ["四", "是", "斯", "思", "似", "私", "丝"], "su": ["速", "素", "宿"],
        "suan": ["算", "酸"], "sui": ["岁", "随", "虽", "碎"], "sun": ["孙"], "suo": ["所", "锁"],
        "ta": ["他", "她", "它", "塔"], "tai": ["太", "台", "态", "泰"], "tan": ["谈", "坛", "探"],
        "tang": ["糖", "堂", "汤"], "tao": ["套", "桃", "淘"], "te": ["特"], "ti": ["题", "体", "提", "替"],
        "tian": ["天", "田", "甜", "填", "添"], "tiao": ["条", "跳"], "tie": ["铁", "贴"], "ting": ["听", "停", "厅"],
        "tong": ["同", "通", "桶", "痛", "统"], "tou": ["头", "投", "透"], "tu": ["图", "土", "突", "途"],
        "tui": ["推", "退", "腿"], "tuo": ["脱", "拖", "妥"],
        "wa": ["娃", "瓦", "挖"], "wai": ["外"], "wan": ["完", "万", "晚", "碗", "湾", "玩"],
        "wang": ["王", "往", "网", "忘", "望"], "wei": ["为", "位", "未", "委", "维", "围", "伟", "味"],
        "wen": ["问", "文", "闻", "稳", "温"], "wo": ["我", "握", "卧"], "wu": ["五", "无", "物", "武", "务", "雾", "误"],
        "xi": ["西", "系", "息", "席", "习", "喜", "洗", "细"], "xia": ["下", "夏", "吓", "峡", "侠"],
        "xian": ["先", "现", "线", "显", "县", "限"], "xiang": ["想", "向", "相", "象", "香", "乡", "响"],
        "xiao": ["小", "笑", "校", "消", "效"], "xie": ["些", "写", "谢", "协", "鞋", "斜"],
        "xin": ["心", "新", "信", "欣", "辛"], "xing": ["行", "性", "姓", "星", "形", "醒"],
        "xiong": ["熊", "雄"], "xiu": ["修", "休", "秀"], "xu": ["须", "需", "许", "序"],
        "xuan": ["选", "宣", "旋"], "xue": ["学", "雪", "血", "靴", "穴"], "xun": ["训", "寻", "询"],
        "ya": ["呀", "压", "雅", "牙"], "yan": ["眼", "演", "烟", "严", "研", "盐"], "yang": ["样", "阳", "洋", "扬"],
        "yao": ["要", "药", "遥", "摇", "咬", "腰"], "ye": ["也", "夜", "叶", "业", "页"],
        "yi": ["一", "以", "已", "意", "议", "易", "亿"], "yin": ["音", "因", "引", "银", "阴"],
        "ying": ["影", "应", "迎", "英", "赢", "营"], "yong": ["用", "永", "勇", "涌"],
        "you": ["有", "又", "由", "右", "游", "友", "油"], "yu": ["于", "与", "雨", "语", "育", "鱼"],
        "yuan": ["元", "员", "原", "远", "院", "源", "愿"], "yue": ["月", "越", "约", "乐", "阅", "跃"],
        "yun": ["云", "运", "允", "韵"],
        "za": ["杂"], "zai": ["在", "再", "载"], "zao": ["早", "造", "糟"], "ze": ["则", "择", "责"],
        "zen": ["怎"], "zeng": ["增", "曾"], "zha": ["扎", "炸"], "zhan": ["站", "战", "展", "占"],
        "zhang": ["张", "章", "涨", "掌", "账"], "zhao": ["找", "照", "着", "赵"], "zhe": ["这", "着", "哲"],
        "zhen": ["真", "镇", "阵", "针"], "zheng": ["正", "证", "整", "争", "政"], "zhi": ["只", "知", "支", "制", "至", "志", "致", "治", "智", "直", "指", "纸", "值"],
        "zhong": ["中", "钟", "重", "种", "众"], "zhou": ["州", "洲", "周", "舟"], "zhu": ["住", "主", "注", "猪", "筑", "祝", "竹"],
        "zhuan": ["专", "转", "赚"], "zhuang": ["装", "状", "壮"], "zhui": ["追"], "zhun": ["准"],
        "zi": ["字", "自", "子", "紫"], "zong": ["总", "宗", "综"], "zou": ["走", "奏"],
        "zu": ["组", "族", "足", "租"], "zui": ["最", "嘴", "罪"], "zuo": ["做", "作", "坐", "左", "昨", "座"],
    ]

    // MARK: - 整词表(全拼 → 词)

    static let phraseTable: [String: String] = [
        "nihao": "你好", "shijie": "世界", "women": "我们", "tamen": "他们",
        "zhongguo": "中国", "beijing": "北京", "shanghai": "上海",
        "xuesheng": "学生", "laoshi": "老师", "tongxue": "同学", "gongzuo": "工作",
        "xihuan": "喜欢", "jintian": "今天", "mingtian": "明天", "zuotian": "昨天",
        "xianzai": "现在", "shijian": "时间", "dianshi": "电视", "diannao": "电脑",
        "shouji": "手机", "pingguo": "苹果", "xigua": "西瓜", "mifan": "米饭",
        "kafei": "咖啡", "yinyue": "音乐", "dianying": "电影", "youxi": "游戏",
        "pengyou": "朋友", "jiayou": "加油", "zhidao": "知道", "kexue": "科学",
        "jingji": "经济", "weilai": "未来",
    ]

    // MARK: - T9 映射

    private static let digitOf: [Character: Character] = [
        "a": "2", "b": "2", "c": "2", "d": "3", "e": "3", "f": "3",
        "g": "4", "h": "4", "i": "4", "j": "5", "k": "5", "l": "5",
        "m": "6", "n": "6", "o": "6", "p": "7", "q": "7", "r": "7", "s": "7",
        "t": "8", "u": "8", "v": "8", "w": "9", "x": "9", "y": "9", "z": "9",
    ]

    /// 音节 → 数字串,如 "ni" → "64"
    static func digits(for syllable: String) -> String {
        String(syllable.compactMap { digitOf[$0] })
    }

    /// 数字串 → 合法音节列表(一次构建,按键时只查表)
    static let syllablesByDigits: [String: [String]] = {
        var map: [String: [String]] = [:]
        for s in syllables {
            map[digits(for: s), default: []].append(s)
        }
        return map
    }()

    /// 整词的数字串索引,如 "5446" → "你好"
    static let phraseByDigits: [String: String] = {
        var map: [String: String] = [:]
        for (pinyin, phrase) in phraseTable {
            let d = digits(for: pinyin)
            if map[d] == nil { map[d] = phrase }
        }
        return map
    }()

    // MARK: - 候选生成

    /// 全拼候选:大词库优先,内置小表兜底。
    /// 输入 "ni" → ["你","尼",…];输入 "nihao" → ["你好","你",…]
    static func qwertyCandidates(_ raw: String) -> [String] {
        let input = raw.lowercased()
        guard !input.isEmpty else { return [] }
        var out: [String] = []

        // 1) 大词库整串查询(单字或整词,词频序)
        if let hits = Lexicon.table?[input] {
            out.append(contentsOf: hits.prefix(8))
        }
        // 2) 内置整词兜底
        if let phrase = phraseTable[input], !out.contains(phrase) { out.append(phrase) }

        // 3) 音节切分:多切分方案的词表查询 + 单字组合兜底
        for split in splits(of: input) {
            let key = split.joined(separator: " ")
            if let hits = Lexicon.table?[key] {
                for h in hits.prefix(4) where !out.contains(h) { out.append(h) }
            }
            if let phrase = phraseTable[split.joined()], !out.contains(phrase) {
                out.append(phrase)
            }
            let options = split.map { syllableOptions($0) }
            if options.allSatisfy({ !$0.isEmpty }) {
                for combo in cartesian(options, limit: 8) where !out.contains(combo) {
                    out.append(combo)
                }
            }
            if out.count >= 10 { break }
        }
        if !out.contains(input) { out.append(input) }   // 兜底:原样上屏选项
        return out
    }

    /// 九宫格候选:数字串 → 合法音节切分 → 词表/字组合。
    /// 输入 "64" → ["你","尼",…];输入 "64426" → ["你好",…]
    static func t9Candidates(_ digitsInput: String) -> [String] {
        let input = digitsInput.filter { $0.isNumber }
        guard !input.isEmpty else { return [] }
        var out: [String] = []

        if let phrase = phraseByDigits[input] { out.append(phrase) }

        for split in t9Splits(of: input) {
            let key = split.joined(separator: " ")
            if let hits = Lexicon.table?[key] {
                for h in hits.prefix(4) where !out.contains(h) { out.append(h) }
            }
            if let phrase = phraseTable[split.joined()], !out.contains(phrase) {
                out.append(phrase)
            }
            let options = split.map { syllableOptions($0) }
            if options.allSatisfy({ !$0.isEmpty }) {
                for combo in cartesian(options, limit: 8) where !out.contains(combo) {
                    out.append(combo)
                }
            }
            if out.count >= 10 { break }
        }
        if out.isEmpty { out = [input] }                // 兜底:无匹配时回显数字
        return out
    }

    /// 某音节的候选字:大词库优先(前 3),否则内置小表
    private static func syllableOptions(_ syllable: String) -> [String] {
        if let chars = Lexicon.table?[syllable], !chars.isEmpty {
            return Array(chars.prefix(3))
        }
        return charTable[syllable] ?? []
    }

    // MARK: - 切分

    /// 全拼切分:返回所有把字符串切成合法音节的方式(限 6 种防组合爆炸)
    private static func splits(of s: String, limit: Int = 6) -> [[String]] {
        let chars = Array(s)
        var results: [[String]] = []
        func rec(_ idx: Int, _ acc: [String]) {
            if results.count >= limit { return }
            if idx == chars.count { results.append(acc); return }
            for len in 1...6 where idx + len <= chars.count {
                let piece = String(chars[idx..<(idx + len)])
                if syllables.contains(piece) { rec(idx + len, acc + [piece]) }
            }
        }
        rec(0, [])
        return results
    }

    /// T9 切分:数字串 → 所有能按数字对上的音节序列(限 6 种)
    private static func t9Splits(of digitsInput: String, limit: Int = 6) -> [[String]] {
        let ds = Array(digitsInput)
        var results: [[String]] = []
        func rec(_ idx: Int, _ acc: [String]) {
            if results.count >= limit { return }
            if idx == ds.count { results.append(acc); return }
            for len in 1...6 where idx + len <= ds.count {
                let piece = String(ds[idx..<(idx + len)])
                for syl in syllablesByDigits[piece] ?? [] {
                    rec(idx + len, acc + [syl])
                }
            }
        }
        rec(0, [])
        return results
    }

    /// 音节候选组合(每个音节取前 3 字做笛卡尔积,最多 limit 个)
    private static func cartesian(_ options: [[String]], limit: Int) -> [String] {
        var result: [String] = []
        func rec(_ i: Int, _ acc: String) {
            if result.count >= limit { return }
            if i == options.count { result.append(acc); return }
            for o in options[i].prefix(3) { rec(i + 1, acc + o) }
        }
        rec(0, "")
        return result
    }
}
