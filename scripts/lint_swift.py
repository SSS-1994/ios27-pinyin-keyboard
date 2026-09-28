#!/usr/bin/env python3
"""Swift 代码静态粗查:括号平衡 + 关键符号引用(无 Mac 编译器时的替代检查)。"""
import glob
import re
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ok = True

for f in glob.glob(os.path.join(ROOT, "PinyinDemo", "**", "*.swift"), recursive=True):
    src = open(f, encoding="utf-8").read()
    s = re.sub(r'"(?:[^"\\]|\\.)*"', '""', src)
    s = re.sub(r"//[^\n]*", "", s)
    balanced = True
    for a, b in [("{", "}"), ("(", ")"), ("[", "]")]:
        if s.count(a) != s.count(b):
            print(f"{os.path.basename(f)}: 括号不平衡 {a}{s.count(a)} vs {b}{s.count(b)}")
            balanced = False
            ok = False
    defs = set(re.findall(r"(?:func|let|var)\s+(\w+)", src))
    print(f"{os.path.basename(f)}: {'OK' if balanced else 'FAIL'} (符号 {len(defs)} 个)")

print("---")
kv = open(os.path.join(ROOT, "PinyinDemo/Keyboard/KeyboardViewController.swift"), encoding="utf-8").read()
vi = open(os.path.join(ROOT, "PinyinDemo/Keyboard/VoiceInputController.swift"), encoding="utf-8").read()
pe = open(os.path.join(ROOT, "PinyinDemo/Keyboard/PinyinEngine.swift"), encoding="utf-8").read()

missing = [n for n in ["toggleVoice", "bindVoiceCallbacks", "showVoicePartial", "passiveLabel",
                       "showAlert", "configureAsKey", "tapSpace", "tapReturn", "tapDelete",
                       "cycleMode", "commit", "refreshCandidates", "buildKeyboard", "setupUI"]
           if n not in kv]
print("KeyboardViewController 缺失:", missing or "无")

missing2 = [n for n in ["func start", "func finish", "func cancel", "var isListening"] if n not in vi]
print("VoiceInputController 缺失:", missing2 or "无")

missing3 = [n for n in ["syllableOptions", "Lexicon.table", "t9Candidates", "qwertyCandidates"] if n not in pe]
print("PinyinEngine 缺失:", missing3 or "无")

passed = ok and not (missing or missing2 or missing3)
print("整体:", "PASS" if passed else "FAIL")
raise SystemExit(0 if passed else 1)
