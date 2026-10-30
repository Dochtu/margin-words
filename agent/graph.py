"""LangGraph 编排：把"用户的一句话要求"变成"只保留该留的单词，并补齐音标释义"。

图结构：
    START → parse → understand ─┬─(要求看图片且已授权) → vision ─┐
                                ├─(要求看图片但未授权) → ask_image ┤
                                └─(其余) ────────────────────────→ filter
    filter → enrich（补音标/释义） → postfilter（要音标/要释义/限量） → review → END

设计要点：先按"能确定的条件"筛（词性、专名、点名留下/去掉、已掌握词表、长度），
再补齐音标释义，最后才判断"是否带音标/释义"——否则 OCR 原文没有音标时会被整批判掉，
用户看到的结果就是"根本没按我说的筛"。
"""

from __future__ import annotations

import json
import os
import re
from typing import Any, TypedDict

from langgraph.graph import END, START, StateGraph

from schemas import Intent
from tools import clean_phonetic, clean_word, fill_phonetics, parse_candidates


def _load_env() -> None:
    """极简 .env 读取（避免额外依赖 python-dotenv）。已存在的环境变量优先。"""
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
    if not os.path.exists(path):
        return
    with open(path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


_load_env()

MODEL = os.getenv("AGENT_MODEL", "gpt-4o-mini")
BASE_URL = os.getenv("AGENT_BASE_URL", "https://api.openai.com/v1")
API_KEY = os.getenv("AGENT_API_KEY", "")
VISION_MODEL = os.getenv("AGENT_VISION_MODEL", "") or MODEL
MOCK = os.getenv("AGENT_MOCK", "0") == "1"
MAX_MEANING_FILL = 20
MAX_CANDIDATES = 120

# "只保留我不认识的"这类要求：有已掌握词表时按词表确定性剔除，不靠模型猜
KNOWN_HINTS = re.compile(r"不认识|不熟悉|生词|没学过|未学过|未掌握|不会的|陌生")
# 圈选/划线：即使模型没把 mode 判成 marks，也强制走视觉节点
MARKS_HINTS = re.compile(r"圈|画圈|圈出|圈选|划线|画线|标注|打勾|勾出|勾选")
PROPER_MEANING_HINTS = re.compile(r"人名|地名|姓氏|城市|国家|专有名词")
POS_PREFIX_RE = re.compile(
    r"^(n|v|vt|vi|adj|adv|prep|pron|conj|num|art|int|aux|abbr)\.?\s*",
    re.IGNORECASE,
)
POS_ALIASES = {
    "noun": "n",
    "verb": "v",
    "adjective": "adj",
    "adverb": "adv",
    "preposition": "prep",
    "pronoun": "pron",
    "conjunction": "conj",
    "number": "num",
}


class AgentState(TypedDict, total=False):
    ocr_text: str
    instruction: str
    image_base64: str | None
    allow_vision: bool
    max_words: int
    known_words: list[str]
    candidates: list[dict]
    intent: dict
    kept: list[dict]
    notes: list[str]
    needs_image: bool


# --------------------------------------------------------------------- LLM


class MockLLM:
    """离线替身：用关键词规则模拟"模型理解意图"，让整张图可以无 Key 跑通。"""

    def invoke(self, messages: list[tuple[str, str]]) -> Any:
        user = messages[-1][1]
        instruction = user.split("【用户要求】", 1)[-1].split("【候选词】", 1)[0].strip()
        words_block = user.split("【候选词】", 1)[-1]

        keep_words: list[str] = []
        drop_words: list[str] = []
        keep_pos: list[str] = []
        mode = "none"
        require_meaning = False
        require_phonetic = False
        exclude_proper = False

        if re.search(r"圈|画线|划线|标注|勾", instruction):
            mode = "marks"
        if re.search(r"名词", instruction):
            keep_pos = ["n"]
        elif re.search(r"动词", instruction):
            keep_pos = ["v"]
        elif re.search(r"形容词", instruction):
            keep_pos = ["adj"]
        if re.search(r"带(中文)?释义|有释义|有翻译", instruction):
            require_meaning = True
        if re.search(r"带音标|有音标", instruction):
            require_phonetic = True
        if re.search(r"人名|地名|专有名词", instruction):
            exclude_proper = True
        dropped = re.search(r"去掉\s*([A-Za-z][A-Za-z ,，、]*)", instruction)
        if dropped:
            drop_words = [
                w.strip() for w in re.split(r"[,，、\s]+", dropped.group(1)) if w.strip()
            ]
        m = re.search(r"前\s*(\d+)\s*个", instruction)
        if m:
            keep_words = [
                ln.split("\t")[0] for ln in words_block.strip().splitlines() if ln.strip()
            ][: int(m.group(1))]

        payload = {
            "mode": mode,
            "keep_pos": keep_pos,
            "drop_pos": [],
            "require_meaning": require_meaning,
            "require_phonetic": require_phonetic,
            "min_length": 0,
            "max_length": 0,
            "exclude_proper_noun": exclude_proper,
            "keyword_in_meaning": "",
            "limit": 0,
            "keep_words": keep_words,
            "drop_words": drop_words,
            "rationale": "（离线模拟）按关键词理解用户要求",
        }
        return type("Msg", (), {"content": json.dumps(payload, ensure_ascii=False)})()


def _llm():
    if MOCK or not API_KEY:
        return MockLLM()
    from langchain_openai import ChatOpenAI

    # DeepSeek V4.1-Flash 默认开启 thinking：这里只要结构化 JSON，
    # 关闭后可显著降低延迟与"推理占用 token 导致 content 为空"的概率。
    extra_body = (
        {"thinking": {"type": "disabled"}}
        if "deepseek" in BASE_URL.lower()
        else None
    )
    return ChatOpenAI(
        model=MODEL,
        base_url=BASE_URL,
        api_key=API_KEY,
        temperature=0,
        timeout=40,
        max_retries=1,
        extra_body=extra_body,
    )


def _extract_json(text: str) -> dict:
    text = re.sub(r"```[a-zA-Z]*", "", text or "").replace("```", "").strip()
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end <= start:
        return {}
    try:
        return json.loads(text[start: end + 1])
    except Exception:
        return {}


INTENT_SYSTEM = """你是"错题单词本"里的筛选助手。用户从试卷/课本拍照得到一批候选单词，
会用一句中文说明他想留哪些。请把这句话理解成结构化条件，只输出 JSON，不要解释。

字段：
- mode: "none"(不筛选) | "semantic"(按语义挑词) | "marks"(要识别图片上的圈/划线)
- keep_words: 需要保留的单词原样列表（只能从候选词里挑，不能新增）
- drop_words: 用户点名要去掉的单词（同样只能来自候选词）
- keep_pos / drop_pos: 词性，如 "n","v","adj","adv"
- require_meaning: 用户明确要求"带释义/有翻译"时才为 true
- require_phonetic: 用户明确要求"带音标"时才为 true
- min_length / max_length: 单词长度限制，0 表示不限
- exclude_proper_noun: 只有用户明确说"去掉人名/地名/专有名词"时才为 true
- keyword_in_meaning: 释义里必须包含的中文词
- limit: 最多保留几个，0 表示不限
- rationale: 一句话说明你怎么理解的（会展示给用户）

必须遵守：
1. 多个条件要"同时满足"（AND），不要只取第一个条件。
2. 不要添加用户没提到的条件。用户没说带释义/带音标，就把 require_meaning / require_phonetic 留空。
3. "画圈的 / 我勾的 / 打勾的" → mode="marks"，keep_words 留空。
4. "只保留我不认识的 / 生词 / 没学过的" → mode="semantic"，keep_words 留空即可
   （服务端会用用户的已掌握词表处理；没有词表时你才按难度挑 keep_words）。
5. "只要名词 / 动词 / 形容词" → 用 keep_pos，不要逐个挑词。
6. "只保留和环保有关的 / 重点词 / 高频词" → 用 keep_words 逐个人工挑选。
7. 条件依赖候选词里根本没有的信息（第几单元、第几页、第几课）时：
   mode="none"、keep_words 留空，并在 rationale 里写明"候选词没有单元/页码信息，无法按该条件筛选"。
8. 用户没提任何要求 → 所有字段保持默认。
"""


# ------------------------------------------------------------------ 工具函数


def normalize_pos(value: str) -> str:
    text = (value or "").strip().lower().rstrip(".")
    if not text:
        return ""
    return POS_ALIASES.get(text, text)


def infer_pos(candidate: dict) -> str:
    """词性：优先用 OCR 原文，其次释义前缀，最后用保守的后缀规则。推不出返回空串。"""
    pos = normalize_pos(candidate.get("pos") or "")
    if pos:
        return pos

    m = POS_PREFIX_RE.match((candidate.get("meaning") or "").strip())
    if m:
        return normalize_pos(m.group(1))

    word = (candidate.get("word") or "").lower()
    if len(word) < 4:
        return ""
    if word.endswith(("tion", "sion", "ment", "ness", "ity", "ance", "ence", "ship", "ism")):
        return "n"
    if word.endswith("ly") and len(word) > 4:
        return "adv"
    if word.endswith(("ous", "ful", "able", "ible", "ive", "less", "ary")):
        return "adj"
    return ""


def is_proper_noun(candidate: dict) -> bool:
    """保守判断人名/地名：首字母大写且非全大写缩写，或释义里写明是人名地名。"""
    if PROPER_MEANING_HINTS.search(candidate.get("meaning") or ""):
        return True
    word = (candidate.get("word") or "").strip()
    if len(word) < 2 or word.isupper():
        return False
    return word[0].isupper() and word[1:].islower()


# ------------------------------------------------------------------- 节点


def parse_node(state: AgentState) -> dict:
    text = state.get("ocr_text", "")
    candidates = parse_candidates(text, limit=MAX_CANDIDATES)
    notes = list(state.get("notes") or [])
    if not candidates:
        notes.append("这段文字里没有解析出英文单词")
    return {"candidates": candidates, "notes": notes}


def understand_node(state: AgentState) -> dict:
    instruction = (state.get("instruction") or "").strip()
    candidates = state.get("candidates") or []
    if not instruction:
        return {"intent": Intent().model_dump()}

    listing = "\n".join(
        f"{c['word']}\t{c.get('pos','')}\t{c.get('meaning','')[:40]}"
        for c in candidates[:MAX_CANDIDATES]
    )
    user = f"【用户要求】{instruction}\n【候选词】\n{listing}"

    try:
        msg = _llm().invoke([("system", INTENT_SYSTEM), ("user", user)])
        data = _extract_json(getattr(msg, "content", "") or "")
        intent = Intent(**{k: v for k, v in data.items() if k in Intent.model_fields})
    except Exception as exc:  # 模型不可用时不阻断主流程
        intent = Intent()
        note = f"意图理解失败，按不筛选处理（{type(exc).__name__}）"
        return {"intent": intent.model_dump(), "notes": (state.get("notes") or []) + [note]}

    has_condition = bool(
        intent.mode != "none"
        or intent.keep_words
        or intent.drop_words
        or intent.keep_pos
        or intent.drop_pos
        or intent.require_meaning
        or intent.require_phonetic
        or intent.min_length
        or intent.max_length
        or intent.keyword_in_meaning
        or intent.limit
        or intent.exclude_proper_noun
    )
    if instruction and not has_condition:
        reason = intent.rationale or "没有从要求里识别出可执行的筛选条件，已保留全部单词"
        return {
            "intent": intent.model_dump(),
            "notes": (state.get("notes") or []) + [reason],
        }
    return {"intent": intent.model_dump()}


def route_after_understand(state: AgentState) -> str:
    intent = Intent(**(state.get("intent") or {}))
    wants_marks = intent.mode == "marks" or bool(
        MARKS_HINTS.search(state.get("instruction") or "")
    )
    if wants_marks:
        if state.get("image_base64") and state.get("allow_vision"):
            return "vision"
        return "ask_image"
    return "filter"


def vision_node(state: AgentState) -> dict:
    """可选能力：把图片交给视觉模型，找出被圈/被划线的单词。

    只有用户显式允许上传图片时才会走到这里。
    """
    image = state.get("image_base64") or ""
    candidates = state.get("candidates") or []
    listing = "\n".join(c["word"] for c in candidates)
    try:
        from langchain_core.messages import HumanMessage

        model = _llm()
        msg = model.invoke(
            [
                HumanMessage(
                    content=[
                        {
                            "type": "text",
                            "text": (
                                "这张图片是英语试卷/课本的照片。请只找出被**手写圈出、划线或打勾**的英文单词，"
                                "按 JSON 返回：{\"keep_words\": [\"word1\", \"word2\"], \"rationale\": \"...\"}。"
                                "没有圈/划线/打勾就返回空数组，绝对不要返回全部单词。"
                                "可参考的候选词（只能从中挑）：\n" + listing
                            ),
                        },
                        {
                            "type": "image_url",
                            "image_url": {"url": f"data:image/jpeg;base64,{image}"},
                        },
                    ]
                )
            ]
        )
        data = _extract_json(getattr(msg, "content", "") or "")
        raw_words = [clean_word(str(w)) for w in (data.get("keep_words") or [])]
        words: list[str] = []
        seen_words: set[str] = set()
        for word in raw_words:
            if not word or word.lower() in seen_words:
                continue
            seen_words.add(word.lower())
            words.append(word)
        intent = Intent(**(state.get("intent") or {}))
        intent.mode = "marks"
        intent.keep_words = words
        note = (
            f"视觉识别到 {len(words)} 个标注单词"
            if words
            else "没有识别到被圈/划线的单词"
        )
        return {
            "intent": intent.model_dump(),
            "notes": (state.get("notes") or []) + [note],
        }
    except Exception as exc:
        intent = Intent(**(state.get("intent") or {}))
        intent.mode = "marks"
        intent.keep_words = []
        return {
            "intent": intent.model_dump(),
            "notes": (state.get("notes") or [])
            + [f"视觉识别失败（{type(exc).__name__}），未保留单词"],
        }


def ask_image_node(state: AgentState) -> dict:
    return {
        "needs_image": True,
        "notes": (state.get("notes") or [])
        + ["要按「圈选/划线」筛选，需要把这张照片发给视觉模型；当前未开启，已保留全部单词"],
    }


def filter_node(state: AgentState) -> dict:
    """按"能确定的条件"筛选：点名保留/剔除、已掌握词表、专有名词、词性、长度。"""
    intent = Intent(**(state.get("intent") or {}))
    candidates = state.get("candidates") or []
    instruction = state.get("instruction") or ""
    known = {w.strip().lower() for w in (state.get("known_words") or []) if w.strip()}
    notes = list(state.get("notes") or [])
    limit = state.get("max_words") or 80

    kept = list(candidates)

    # ① 圈选/划线：视觉模型给出的词就是白名单；没识别到就返回空，不能退回全部
    if intent.mode == "marks":
        wanted = {w.strip().lower() for w in intent.keep_words if w.strip()}
        if not wanted:
            notes.append("没有识别到被圈/划线的单词")
            return {"kept": [], "notes": notes}
        kept = [c for c in kept if c["word"].lower() in wanted]
        if not kept:
            notes.append("视觉模型识别到的词不在候选列表里")
            return {"kept": [], "notes": notes}
        notes.append(f"按圈选保留 {len(kept)} 个")

    # ①b 用户点名要留的（模型挑出来的语义子集）
    elif intent.keep_words:
        wanted = {w.strip().lower() for w in intent.keep_words if w.strip()}
        picked = [c for c in kept if c["word"].lower() in wanted]
        if picked:
            kept = picked
        else:
            notes.append("你点名的单词不在候选里，已按其他条件筛选")

    # ② 用户点名要去掉的
    if intent.drop_words:
        dropped = {w.strip().lower() for w in intent.drop_words if w.strip()}
        kept = [c for c in kept if c["word"].lower() not in dropped]

    # ③ "不认识/生词"：有已掌握词表就确定性剔除，不靠模型猜
    if KNOWN_HINTS.search(instruction):
        if known:
            before = len(kept)
            kept = [c for c in kept if c["word"].lower() not in known]
            notes.append(f"按已掌握词表排除 {before - len(kept)} 个，保留生词 {len(kept)} 个")
        elif intent.keep_words:
            notes.append("还没有已掌握单词记录，本次按常见难度估算生词")

    # ④ 专有名词（仅当用户明确要求）
    if intent.exclude_proper_noun:
        before = len(kept)
        kept = [c for c in kept if not is_proper_noun(c)]
        if before != len(kept):
            notes.append(f"已去掉 {before - len(kept)} 个人名/地名")

    # ⑤ 词性：先推断，推不出的按"未知"处理
    if intent.keep_pos or intent.drop_pos:
        keep_pos = {normalize_pos(p) for p in intent.keep_pos if normalize_pos(p)}
        drop_pos = {normalize_pos(p) for p in intent.drop_pos if normalize_pos(p)}
        survivors: list[dict] = []
        unknown_pos: list[dict] = []
        for c in kept:
            pos = infer_pos(c)
            if not pos:
                unknown_pos.append(c)
                continue
            if keep_pos and pos not in keep_pos:
                continue
            if drop_pos and pos in drop_pos:
                continue
            survivors.append(c)
        kept = survivors
        # 全部判为"词性未知"时放宽一次，避免用户看到一个空结果
        if not kept and unknown_pos:
            kept = unknown_pos
            notes.append(f"有 {len(unknown_pos)} 个词判断不出词性，已先保留")
        elif unknown_pos:
            notes.append(f"另有 {len(unknown_pos)} 个词判断不出词性，已排除")

    # ⑥ 长度与释义关键词
    if intent.min_length:
        kept = [c for c in kept if len(c["word"]) >= intent.min_length]
    if intent.max_length:
        kept = [c for c in kept if len(c["word"]) <= intent.max_length]
    if intent.keyword_in_meaning:
        keyword = intent.keyword_in_meaning
        kept = [c for c in kept if keyword in (c.get("meaning") or "")]

    return {"kept": kept[:limit], "notes": notes}


def enrich_node(state: AgentState) -> dict:
    kept = [dict(c) for c in (state.get("kept") or [])]
    if not kept:
        return {"kept": []}

    for c in kept:
        c["phonetic"] = clean_phonetic(c.get("phonetic", ""))
    fill_phonetics(kept)

    missing = [c for c in kept if not c.get("meaning")][:MAX_MEANING_FILL]
    notes = list(state.get("notes") or [])
    if missing:
        try:
            words = "、".join(c["word"] for c in missing)
            msg = _llm().invoke(
                [
                    (
                        "system",
                        "给下列英文单词各写一句不超过 20 字的中文释义。"
                        "只输出 JSON：{\"items\":[{\"word\":\"...\",\"meaning\":\"n. 苹果\"}]}，不要解释。",
                    ),
                    ("user", words),
                ]
            )
            data = _extract_json(getattr(msg, "content") or "")
            mapping = {
                str(i.get("word", "")).lower(): str(i.get("meaning", ""))
                for i in (data.get("items") or [])
                if isinstance(i, dict)
            }
            for c in missing:
                if mapping.get(c["word"].lower()):
                    c["meaning"] = mapping[c["word"].lower()][:200]
        except Exception:
            notes.append("部分单词缺少释义，且补全失败，可在确认页手动补充")
    return {"kept": kept, "notes": notes}


def postfilter_node(state: AgentState) -> dict:
    """补齐音标/释义之后再判断"是否带音标/释义"，以及"最多几个"。"""
    intent = Intent(**(state.get("intent") or {}))
    kept = list(state.get("kept") or [])
    notes = list(state.get("notes") or [])

    if intent.require_meaning:
        before = len(kept)
        kept = [c for c in kept if (c.get("meaning") or "").strip()]
        if before != len(kept):
            notes.append(f"按「要有释义」去掉 {before - len(kept)} 个")

    if intent.require_phonetic:
        before = len(kept)
        kept = [c for c in kept if (c.get("phonetic") or "").strip()]
        if before != len(kept):
            notes.append(f"按「要有音标」去掉 {before - len(kept)} 个")

    if intent.limit and intent.limit < len(kept):
        kept = kept[: intent.limit]

    return {"kept": kept, "notes": notes}


def review_node(state: AgentState) -> dict:
    kept = state.get("kept") or []
    candidates = state.get("candidates") or []
    notes = list(state.get("notes") or [])
    limit = state.get("max_words") or 80
    if not kept and candidates:
        if Intent(**(state.get("intent") or {})).mode == "marks":
            notes.append("没有识别到被圈/划线的单词，请换一张更清晰的照片或手动勾选")
            return {"kept": [], "notes": notes}
        fallback = candidates[:limit]
        notes.append("按你的条件没剩下单词，已显示全部，请手动勾选")
        return {"kept": fallback, "notes": notes}
    if kept:
        notes.append(f"共 {len(candidates)} 个候选，保留 {len(kept)} 个")
    return {"kept": kept, "notes": notes}


# ------------------------------------------------------------------- 构图


def build_graph():
    graph = StateGraph(AgentState)
    graph.add_node("parse", parse_node)
    graph.add_node("understand", understand_node)
    graph.add_node("ask_image", ask_image_node)
    graph.add_node("vision", vision_node)
    graph.add_node("filter", filter_node)
    graph.add_node("enrich", enrich_node)
    graph.add_node("postfilter", postfilter_node)
    graph.add_node("review", review_node)

    graph.add_edge(START, "parse")
    graph.add_edge("parse", "understand")
    graph.add_conditional_edges(
        "understand",
        route_after_understand,
        {"vision": "vision", "ask_image": "ask_image", "filter": "filter"},
    )
    graph.add_edge("vision", "filter")
    graph.add_edge("ask_image", "filter")
    graph.add_edge("filter", "enrich")
    graph.add_edge("enrich", "postfilter")
    graph.add_edge("postfilter", "review")
    graph.add_edge("review", END)
    return graph.compile()


GRAPH = build_graph()


def run_agent(
    ocr_text: str,
    instruction: str = "",
    image_base64: str | None = None,
    allow_vision: bool = False,
    max_words: int = 80,
    known_words: list[str] | None = None,
) -> dict:
    return GRAPH.invoke(
        {
            "ocr_text": ocr_text,
            "instruction": instruction,
            "image_base64": image_base64,
            "allow_vision": allow_vision,
            "max_words": max_words,
            "known_words": known_words or [],
            "notes": [],
            "needs_image": False,
        }
    )


# --------------------------------------------------------- 对话模式用的两个入口

VISION_READ_PROMPT = (
    "这是一张英语课本或试卷的照片。请读出其中所有英文单词，并给出每个词的音标、"
    "中文释义和词性（n / v / adj / adv 等）。"
    "图上没有音标或释义就留空，不要编造；词性按你对该词的判断填写，不确定就留空。"
    '只输出 JSON：{"words":[{"word":"apple","phonetic":"/ˈæpl/","meaning":"n. 苹果","pos":"n"}]}，'
    "不要额外解释。"
)


def _vision_read(image_base64: str) -> list[dict]:
    """让视觉模型直接把照片读成候选词列表（deepseek-flash 原生支持读图）。"""
    from langchain_core.messages import HumanMessage

    msg = _llm().invoke(
        [
            HumanMessage(
                content=[
                    {"type": "text", "text": VISION_READ_PROMPT},
                    {
                        "type": "image_url",
                        "image_url": {"url": f"data:image/jpeg;base64,{image_base64}"},
                    },
                ]
            )
        ]
    )
    data = _extract_json(getattr(msg, "content", "") or "")

    out: list[dict] = []
    seen: set[str] = set()
    for item in data.get("words") or []:
        if not isinstance(item, dict):
            continue
        word = clean_word(str(item.get("word", "")))
        key = word.lower()
        if not word or key in seen:
            continue
        seen.add(key)
        meaning = str(item.get("meaning", "")).strip()[:200]
        # 优先用模型直接给出的词性；没有就退回释义前缀（如 "n. 苹果"）。
        pos = normalize_pos(str(item.get("pos", "")))
        if not pos:
            m = POS_PREFIX_RE.match(meaning)
            pos = normalize_pos(m.group(1)) if m else ""
        out.append(
            {
                "word": word,
                "phonetic": clean_phonetic(str(item.get("phonetic", ""))),
                "meaning": meaning,
                "pos": pos,
            }
        )
    return out


def build_extract_graph():
    """只做"已有候选词 → 筛选 → 补全 → 后置过滤"，供对话模式下多轮复用。"""
    graph = StateGraph(AgentState)
    graph.add_node("understand", understand_node)
    graph.add_node("ask_image", ask_image_node)
    graph.add_node("vision", vision_node)
    graph.add_node("filter", filter_node)
    graph.add_node("enrich", enrich_node)
    graph.add_node("postfilter", postfilter_node)
    graph.add_node("review", review_node)

    graph.add_edge(START, "understand")
    graph.add_conditional_edges(
        "understand",
        route_after_understand,
        {"vision": "vision", "ask_image": "ask_image", "filter": "filter"},
    )
    graph.add_edge("vision", "filter")
    graph.add_edge("ask_image", "filter")
    graph.add_edge("filter", "enrich")
    graph.add_edge("enrich", "postfilter")
    graph.add_edge("postfilter", "review")
    graph.add_edge("review", END)
    return graph.compile()


EXTRACT_GRAPH = build_extract_graph()


def refine_candidates(
    candidates: list[dict],
    instruction: str = "",
    known_words: list[str] | None = None,
    max_words: int = 80,
    image_base64: str | None = None,
    allow_vision: bool = False,
) -> dict:
    """对已有候选词重新按新要求筛一遍（多轮对话里"换成只要名词"就是走这里）。"""
    return EXTRACT_GRAPH.invoke(
        {
            "ocr_text": "",
            "instruction": instruction or "",
            "image_base64": image_base64,
            "allow_vision": allow_vision,
            "candidates": candidates,
            "known_words": known_words or [],
            "max_words": max_words,
            "notes": [],
        }
    )


def extract_from_image(
    image_base64: str,
    instruction: str = "",
    known_words: list[str] | None = None,
    max_words: int = 80,
) -> dict:
    """照片 → 候选词 → 按用户要求筛选。读不出词时返回空候选。"""
    candidates = _vision_read(image_base64)
    state = refine_candidates(
        candidates,
        instruction,
        known_words,
        max_words,
        image_base64=image_base64,
        allow_vision=True,
    )
    if not candidates:
        state["notes"] = list(state.get("notes") or []) + ["照片里没有读到英文单词"]
    return state
