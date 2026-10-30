"""智能体可调用的"工具"：候选词解析、音标查询。

这些函数不依赖 LLM，可单独测试；在 LangGraph 里以工具节点的形式被调用。
"""

from __future__ import annotations

import json
import re
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache

PHONETIC_RE = re.compile(r"(\[[^\[\]]{1,40}\]|/[^/]{1,44}/)")
CJK_RE = re.compile(r"[\u4e00-\u9fa5]")
INDEX_RE = re.compile(r"^[\s\(（]*\d{1,3}\s*[\.、\)）]\s*")
POS_SUFFIX_RE = re.compile(
    r"\s+(n|v|vt|vi|adj|adv|prep|pron|conj|num|art|int|aux|abbr)\.?\s*$",
    re.IGNORECASE,
)
POS_PREFIX_RE = re.compile(
    r"^(n|v|vt|vi|adj|adv|prep|pron|conj|num|art|int|aux|abbr)\.\s*",
    re.IGNORECASE,
)
WORD_RE = re.compile(r"^[A-Za-z][A-Za-z'’\-\. ]{0,48}$")
IPA_RE = re.compile(r"^[A-Za-zæɑɒɔəɜɛɪʊʌθðʃʒŋɡɹɾʔˈˌːˑ'\-\. ]+$")


def clean_phonetic(raw: str) -> str:
    """规范化音标；不合法返回空串（宁可留空，也不放大模型编的音标）。"""
    text = (raw or "").strip()
    if not text or CJK_RE.search(text):
        return ""
    inner = text
    if len(inner) > 2 and inner[0] == "/" and inner[-1] == "/":
        inner = inner[1:-1]
    elif len(inner) > 2 and inner[0] == "[" and inner[-1] == "]":
        inner = inner[1:-1]
    inner = inner.strip()
    if not inner or len(inner) > 44 or not IPA_RE.match(inner):
        return ""
    if not re.search(r"[A-Za-zæɑɒɔəɜɛɪʊʌθðʃʒŋɡ]", inner):
        return ""
    return f"/{inner}/"


def clean_word(raw: str) -> str:
    text = re.sub(r"\s+", " ", (raw or "").replace("\u00a0", " ")).strip()
    if not text:
        return ""
    text = INDEX_RE.sub("", text)
    text = PHONETIC_RE.sub(" ", text).strip()
    text = text.strip("\"'“”‘’·•*[]【】<>《》()（）")
    text = POS_PREFIX_RE.sub("", text).strip()
    text = text.strip(" .,;:!?，、；：！？-–—")
    if not text or not WORD_RE.match(text) or re.search(r"\d", text):
        return ""
    tokens = text.split(" ")
    if len(tokens) > 4:
        return ""
    if not any(len(re.sub(r"[^A-Za-z]", "", t)) >= 2 for t in tokens):
        return ""
    return text


def parse_candidates(text: str, limit: int = 80) -> list[dict]:
    """把 OCR 文本切成候选词。与 App 端本地规则保持一致，保证无 Agent 时结果不跳变。"""
    lines = [ln.strip() for ln in (text or "").splitlines()]
    lines = [ln for ln in lines if ln]

    out: list[dict] = []
    seen: set[str] = set()
    i = 0
    while i < len(lines):
        line = INDEX_RE.sub("", lines[i]).strip()
        i += 1
        if not line or not re.search(r"[A-Za-z]", line):
            continue

        phonetic = ""
        meaning = ""
        m = PHONETIC_RE.search(line)
        if m:
            phonetic = m.group(0)
            word_part = line[: m.start()].strip()
            meaning = line[m.end():].strip()
        else:
            cjk = CJK_RE.search(line)
            if cjk:
                word_part = line[: cjk.start()].strip()
                meaning = line[cjk.start():].strip()
            else:
                word_part = line

        pos = POS_SUFFIX_RE.search(word_part)
        if pos:
            pos_text = pos.group(0).strip()
            word_part = word_part[: pos.start()].strip()
            if meaning and not meaning.lower().startswith("n."):
                meaning = f"{pos_text} {meaning}"

        if not meaning and i < len(lines):
            nxt = lines[i].strip()
            m2 = PHONETIC_RE.search(nxt)
            if m2 and m2.start() == 0:
                phonetic = phonetic or m2.group(0)
                rest = nxt[m2.end():].strip()
                if rest:
                    meaning = rest
            elif CJK_RE.search(nxt):
                meaning = nxt
                i += 1

        word = clean_word(word_part)
        if not word:
            continue

        for candidate in re.split(r"[,，、;；/]", word) if re.search(r"[,，、;；/]", word) else [word]:
            cw = clean_word(candidate)
            key = cw.lower()
            if not cw or key in seen:
                continue
            seen.add(key)
            out.append(
                {
                    "word": cw,
                    "phonetic": clean_phonetic(phonetic),
                    "meaning": re.sub(r"\s+", " ", meaning).strip()[:200],
                    "pos": (POS_PREFIX_RE.match(meaning).group(1).lower() if POS_PREFIX_RE.match(meaning) else ""),
                }
            )
            if len(out) >= limit:
                return out
    return out


@lru_cache(maxsize=512)
def lookup_phonetic(word: str) -> str:
    """免费词典接口查音标。失败一律返回空串，不抛异常。"""
    if " " in word:
        return ""
    url = (
        "https://api.dictionaryapi.dev/api/v2/entries/en/"
        + urllib.parse.quote(word.lower())
    )
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "wordbook-agent/1.0"})
        with urllib.request.urlopen(req, timeout=4) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception:
        return ""
    if not isinstance(data, list):
        return ""
    for entry in data:
        if not isinstance(entry, dict):
            continue
        p = entry.get("phonetic")
        if isinstance(p, str) and clean_phonetic(p):
            return clean_phonetic(p)
        for item in entry.get("phonetics") or []:
            if isinstance(item, dict) and isinstance(item.get("text"), str):
                cleaned = clean_phonetic(item["text"])
                if cleaned:
                    return cleaned
    return ""


def fill_phonetics(words: list[dict], workers: int = 8) -> int:
    """并发补音标，返回补全数量。"""
    todo = [w for w in words if not w.get("phonetic")]
    if not todo:
        return 0
    filled = 0
    with ThreadPoolExecutor(max_workers=workers) as pool:
        for item, phonetic in zip(todo, pool.map(lambda w: lookup_phonetic(w["word"]), todo)):
            if phonetic:
                item["phonetic"] = phonetic
                filled += 1
    return filled
