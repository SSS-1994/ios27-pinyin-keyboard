#!/usr/bin/env python3
"""
将雾凇拼音(rime-ice)开源词库转换为键盘扩展使用的 Lexicon.json。

- 音节合法性校验:直接从 PinyinEngine.swift 提取全拼音节表,保证两端一致
- 输入:.tmp/8105.dict.yaml(单字)、base.dict.yaml、ext.dict.yaml、others.dict.yaml
- 输出:PinyinDemo/Keyboard/Resources/Lexicon.json
  格式:{"拼音或拼音串": ["候选1", "候选2", ...]}(数组已按词频降序)
  key 如 "ni"(单字)或 "ni hao"(词),全拼小写、音节间单空格

用法: python scripts/build_lexicon.py
"""
import json
import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TMP = os.path.join(ROOT, ".tmp")
OUT_DIR = os.path.join(ROOT, "PinyinDemo", "Keyboard", "Resources")
OUT_FILE = os.path.join(OUT_DIR, "Lexicon.json")
SWIFT_ENGINE = os.path.join(ROOT, "PinyinDemo", "Keyboard", "PinyinEngine.swift")

MAX_WORDS_PER_KEY = 30      # 每个拼音串最多保留候选数
MAX_TOTAL_WORDS = 20000     # 全局词库上限。
# 关键:真机键盘扩展 jetsam 上限约 69MB(不分机型,模拟器不受限),
# 6 万词条解析后内存峰值会踩线导致"切到键盘即闪退";
# 2 万高频词解析后约 5-6MB,真机安全。老机型还可进一步调小。
CJK = re.compile(r"^[\u4e00-\u9fff]+$")


def load_syllables_from_swift() -> set:
    """从 PinyinEngine.swift 的 syllables 数组提取全拼音节表。"""
    src = open(SWIFT_ENGINE, encoding="utf-8").read()
    m = re.search(r"static let syllables: Set<String> = \[(.*?)\]", src, re.S)
    if not m:
        sys.exit("无法从 PinyinEngine.swift 提取音节表")
    return set(re.findall(r'"([a-z]+)"', m.group(1)))


def iter_dict(path):
    """逐行产出 rime dict 的 (词, 拼音串, 权重),跳过 YAML 头与注释。"""
    in_data = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.rstrip("\n")
            if not in_data:
                if line.strip() == "...":
                    in_data = True
                continue
            if not line or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) < 2:
                continue
            if len(cols) >= 3:
                word, pinyin, weight = cols[0], cols[1], cols[2]
            else:
                # others.dict.yaml:词\t拼音(无权重);tencent:词\t权重(无拼音,跳过)
                word, pinyin, weight = cols[0], cols[1], "100"
                if not re.fullmatch(r"[a-z ]+", pinyin):
                    continue
            yield word, pinyin, weight


def norm_key(pinyin: str) -> str:
    return " ".join(pinyin.strip().lower().split())


def main():
    syllables = load_syllables_from_swift()
    print(f"从 Swift 提取音节 {len(syllables)} 个")

    chars = defaultdict(list)   # key -> [(word, weight)]
    words = defaultdict(list)

    # 1) 单字表
    n_char = 0
    for word, pinyin, weight in iter_dict(os.path.join(TMP, "8105.dict.yaml")):
        key = norm_key(pinyin)
        if len(word) != 1 or key not in syllables:
            continue
        chars[key].append((word, int(weight or 0)))
        n_char += 1
    print(f"单字表:{n_char} 条")

    # 2) 词库(base + ext + others)
    n_word = 0
    for name in ("base.dict.yaml", "ext.dict.yaml", "others.dict.yaml"):
        path = os.path.join(TMP, name)
        for word, pinyin, weight in iter_dict(path):
            key = norm_key(pinyin)
            if not CJK.match(word) or len(word) < 2:
                continue
            parts = key.split()
            if len(parts) != len(word):          # 拼音数与字数不符,弃
                continue
            if any(p not in syllables for p in parts):
                continue                          # 有音节表外的注音,弃
            words[key].append((word, int(weight or 0)))
            n_word += 1
    print(f"词库原始:{n_word} 条")

    # 3) 截断与排序
    all_word_entries = [(k, w, t) for k, v in words.items() for w, t in v]
    all_word_entries.sort(key=lambda x: -x[2])
    lexicon = {}
    for k, items in chars.items():
        items.sort(key=lambda x: -x[1])
        lexicon[k] = [w for w, _ in items[:MAX_WORDS_PER_KEY]]
    kept = 0
    for k, w, _ in all_word_entries:
        if kept >= MAX_TOTAL_WORDS:
            break
        bucket = lexicon.setdefault(k, [])
        if len(bucket) >= MAX_WORDS_PER_KEY or w in bucket:
            continue
        bucket.append(w)
        kept += 1
    print(f"词库保留:{kept} 条;总 key 数:{len(lexicon)}")

    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT_FILE, "w", encoding="utf-8") as f:
        json.dump(lexicon, f, ensure_ascii=False, separators=(",", ":"))
    size = os.path.getsize(OUT_FILE)
    print(f"输出:{OUT_FILE}({size / 1024 / 1024:.2f} MB)")


if __name__ == "__main__":
    main()
