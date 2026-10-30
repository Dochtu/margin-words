"""对话式智能体：一次会话内理解上下文，用工具把单词写进用户的单词本。

和 `graph.run_agent` 的区别：
- 不再"一次请求一个固定格式的结果"，而是保留多轮对话（上下文由手机端每轮带回，
  服务端不落任何会话状态，天然支持"单次会话记忆"且重启不丢）；
- 工具化：模型决定"要不要导入"，真正的写库动作由手机端执行（`ChatAction`）。
"""

from __future__ import annotations

import json
import os
import re

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage, ToolMessage

from graph import API_KEY, MOCK, extract_from_image, refine_candidates, run_agent
from schemas import ChatAction, ChatRequest, ChatResponse, WordItem
from tools import clean_word

MAX_HISTORY = 10
MAX_TOOL_ROUNDS = 3

# 一次性恢复入口：从 App 缓存照片里提取出来的词表，写回手机单词本。
# 只在对话里输入这个暗号时触发，避免日常对话误触。
RECOVERY_TRIGGER = "restore_recovered_words"
RECOVERY_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "recovered_words.json"
)

CHAT_SYSTEM = """你是「错题单词本」App 里的对话助手。用户会把课本/试卷的照片发给你，
并用一两句话说明想要哪些单词。你的任务：看懂要求 → 挑出该留的单词 → 把它们导入用户的单词本。

工作方式：
1. 照片已经由你读成候选词了，结果在系统消息里；不要再让用户重发照片。
2. 需要写入单词本时调用 import_words 工具（只能填候选词里存在的单词）。
3. 回复要短：一两条中文，说清"导入了几个、去掉了什么"。不要罗列全部单词，不要讲你的推理过程。
4. 收到照片且用户没说"先别导入/只是看看"时，直接导入，不要反问。
5. 用户提出新条件（只要名词、去掉某个词、只留生词、前 10 个……）时，
   系统已按新条件重新筛过，候选结果在系统消息里，你确认并导入即可。
6. 候选词为空时，直接说没读到英文单词，不要调用工具。
7. 回复要针对用户这一轮的具体要求，不要套用固定模板；能说出实际保留/去掉了哪些词。
"""

TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "import_words",
            "description": "把单词写入用户的单词本（手机端执行）。只能使用候选词里已有的单词。",
            "parameters": {
                "type": "object",
                "properties": {
                    "words": {
                        "type": "array",
                        "items": {"type": "string"},
                        "description": "要写入的单词原样列表",
                    },
                    "reason": {
                        "type": "string",
                        "description": "一句话说明为什么导入这些词",
                    },
                },
                "required": ["words"],
            },
        },
    }
]

_IMPORT_HINTS = re.compile(r"导入|保存|记到|记下|加到|收录|存进|入库|放进|存到")
_SKIP_HINTS = re.compile(r"先别|不要导入|别导入|只是看看|先看看|看看就行|不用导入")
_FILTER_HINTS = re.compile(
    r"名词|动词|形容词|副词|生词|不认识|没学过|圈|划线|标注|音标|释义|"
    r"前\s*\d+\s*个|去掉|保留|专有名词|人名|地名"
)

# 手机端把图片消息写成这个占位符；它不是用户的筛选要求。
PHOTO_PLACEHOLDERS = {
    "",
    "[发送了一张照片]",
    "发送了一张照片",
    "[图片]",
    "[照片]",
}

CHAT_FALLBACK_SYSTEM = """你是「错题单词本」App 里的对话助手。用户会发课本/试卷照片，
并说明想保留哪些单词。现在这条消息还没有照片或候选词。
请根据用户这句话自然回答，不要每次都用同一句模板：
- 如果他在描述筛选要求（只要名词、只留生词、画圈的、前 10 个……），确认你理解的要求，并请他发一张照片；
- 如果他在问你能做什么，简短说明；
- 如果是打招呼，回应并引导他发照片。
不要编造图片内容。最多两句话。"""


def _last_instruction(req: ChatRequest) -> str:
    """最近一条真正的文字要求；跳过“发送了一张照片”这类占位消息。"""
    for msg in reversed(req.messages):
        if msg.role != "user":
            continue
        text = (msg.content or "").strip()
        if text and text not in PHOTO_PLACEHOLDERS:
            return text
    return ""


def _shorten(text: str, limit: int = 24) -> str:
    text = text.strip()
    return text if len(text) <= limit else f"{text[:limit]}…"


def _condition_text(instruction: str) -> str:
    text = instruction.strip()
    if text and _FILTER_HINTS.search(text):
        return f"按「{_shorten(text)}」"
    return "按你的要求"


def _fallback_text_reply(instruction: str) -> str:
    text = instruction.strip()
    if text and _FILTER_HINTS.search(text):
        return f"收到，你要求「{_shorten(text)}」。发一张课本或试卷的照片，我读出来按这个要求筛。"
    if text:
        return "收到。发一张课本或试卷的照片，我读出单词后再按你说的要求筛。"
    return "发一张课本或试卷的照片，我读出单词后再按你说的要求筛。"


def _chat_reply(req: ChatRequest, instruction: str) -> str:
    """没有照片/候选词时的自然回复，避免每次都返回同一句死文案。"""
    if not MOCK and API_KEY:
        try:
            from graph import _llm

            messages: list = [SystemMessage(CHAT_FALLBACK_SYSTEM)]
            for msg in req.messages[-MAX_HISTORY:]:
                content = (msg.content or "").strip()
                if not content:
                    continue
                if msg.role == "user":
                    messages.append(HumanMessage(content))
                else:
                    messages.append(AIMessage(content))
            ai = _llm().invoke(messages)
            text = (getattr(ai, "content", "") or "").strip()
            if text:
                return text
        except Exception:
            pass
    return _fallback_text_reply(instruction)


def _recovery_words() -> list[WordItem]:
    """读取一次性恢复词表（从 App 缓存照片里提取的）。"""
    try:
        with open(RECOVERY_FILE, encoding="utf-8") as handle:
            rows = json.load(handle)
    except Exception:
        return []

    out: list[WordItem] = []
    seen: set[str] = set()
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            continue
        word = str(row.get("word") or "").strip()
        key = word.lower()
        if not word or key in seen:
            continue
        seen.add(key)
        out.append(
            WordItem(
                word=word,
                phonetic=str(row.get("phonetic") or ""),
                meaning=str(row.get("meaning") or ""),
                reason="从缓存照片恢复",
            )
        )
    return out


def _items(rows: list[dict]) -> list[WordItem]:
    return [
        WordItem(
            word=row.get("word", ""),
            phonetic=row.get("phonetic", ""),
            meaning=row.get("meaning", ""),
        )
        for row in rows
        if row.get("word")
    ]


def _context_block(candidates: list[dict], kept: list[dict], known: int) -> str:
    lines = [f"【当前候选词：{len(candidates)} 个】"]
    for row in candidates[:80]:
        pos = row.get("pos") or ""
        meaning = (row.get("meaning") or "")[:30]
        lines.append(f"{row['word']}\t{pos}\t{meaning}")
    kept_words = "、".join(row["word"] for row in kept[:60])
    lines.append("")
    lines.append(f"【本轮按用户要求筛出：{len(kept)} 个】{kept_words}")
    if known:
        lines.append(f"【用户已掌握单词 {known} 个】用户说“我不认识的”时，这些词已被排除。")
    return "\n".join(lines)


def _resolve_words(raw: object, kept: list[dict], candidates: list[dict]) -> list[dict]:
    """把模型给的单词名对齐到真实候选行：先在本轮结果里找，再退回全量候选。"""
    names = [clean_word(str(w)).lower() for w in (raw if isinstance(raw, list) else [])]
    names = [n for n in names if n]
    if not names:
        return list(kept)
    wanted = set(names)
    picked = [c for c in kept if c["word"].lower() in wanted]
    if picked:
        return picked
    pool = [c for c in candidates if c["word"].lower() in wanted]
    return pool or list(kept)


def _wants_import(last_user: str, has_image: bool) -> bool:
    if _SKIP_HINTS.search(last_user):
        return False
    return has_image or bool(_IMPORT_HINTS.search(last_user))


def _collect_state(
    req: ChatRequest, instruction: str
) -> tuple[list[dict], list[dict], list[str], dict]:
    """得到候选词、本轮筛选结果、提示和意图：优先读新照片，其次重筛上一轮候选。"""
    notes: list[str] = []

    if req.image_base64:
        try:
            state = extract_from_image(
                req.image_base64, instruction, req.known_words, req.max_words
            )
            return (
                list(state.get("candidates") or []),
                list(state.get("kept") or []),
                notes + list(state.get("notes") or []),
                dict(state.get("intent") or {}),
            )
        except Exception as exc:  # 读图失败：退回 OCR 文本（如果有）
            notes.append(f"读图失败（{type(exc).__name__}）")

    if req.candidates:
        rows = [c.model_dump() for c in req.candidates]
        state = refine_candidates(rows, instruction, req.known_words, req.max_words)
        return (
            rows,
            list(state.get("kept") or []),
            notes + list(state.get("notes") or []),
            dict(state.get("intent") or {}),
        )

    if req.ocr_text:
        state = run_agent(
            req.ocr_text,
            instruction=instruction,
            known_words=req.known_words,
            max_words=req.max_words,
        )
        return (
            list(state.get("candidates") or []),
            list(state.get("kept") or []),
            notes + list(state.get("notes") or []),
            dict(state.get("intent") or {}),
        )

    return [], [], notes, {}


def _chat_with_tools(
    req: ChatRequest,
    candidates: list[dict],
    kept: list[dict],
    known: int,
) -> tuple[str, list[ChatAction]]:
    """让模型决定说什么、要不要调工具。任何异常都退回"只给总结、不猜"。"""
    if MOCK:
        return "", []

    try:
        model = _llm_with_tools()
        messages: list = [
            SystemMessage(CHAT_SYSTEM + "\n\n" + _context_block(candidates, kept, known))
        ]
        for msg in req.messages[-MAX_HISTORY:]:
            if msg.role == "user":
                messages.append(HumanMessage(msg.content or "[发送了一张照片]"))
            else:
                messages.append(AIMessage(msg.content))

        actions: list[ChatAction] = []
        reply = ""
        for _ in range(MAX_TOOL_ROUNDS):
            ai = model.invoke(messages)
            calls = getattr(ai, "tool_calls", None) or []
            if not calls:
                reply = (getattr(ai, "content", "") or "").strip()
                break
            messages.append(ai)
            for call in calls:
                args = call.get("args") or {}
                if call.get("name") != "import_words":
                    messages.append(
                        ToolMessage(content='{"ok": false}', tool_call_id=call.get("id") or "")
                    )
                    continue
                picked = _resolve_words(args.get("words"), kept, candidates)
                if picked:
                    actions.append(
                        ChatAction(
                            words=_items(picked),
                            reason=str(args.get("reason") or ""),
                        )
                    )
                messages.append(
                    ToolMessage(
                        content=json.dumps(
                            {"ok": bool(picked), "count": len(picked)}, ensure_ascii=False
                        ),
                        tool_call_id=call.get("id") or "",
                    )
                )
        return reply, actions
    except Exception:
        return "", []


def _llm_with_tools():
    from graph import _llm

    return _llm().bind_tools(TOOLS)


def handle_chat(req: ChatRequest) -> ChatResponse:
    instruction = _last_instruction(req)

    if instruction.strip().lower() == RECOVERY_TRIGGER:
        words = _recovery_words()
        if not words:
            return ChatResponse(
                reply="没有找到可恢复的词表文件。",
                candidates=[],
                notes=[],
            )
        return ChatResponse(
            reply=f"找到 {len(words)} 个缓存单词，正在写回单词本。",
            actions=[ChatAction(words=words, reason="从缓存照片恢复")],
            candidates=words,
            notes=[f"从缓存照片恢复 {len(words)} 个单词"],
        )

    candidates, kept, notes, intent = _collect_state(req, instruction)

    if not candidates:
        if not req.image_base64 and not req.ocr_text:
            return ChatResponse(
                reply=_chat_reply(req, instruction),
                candidates=[],
                notes=notes,
            )
        return ChatResponse(
            reply="这张照片里没有读到英文单词，换一张清晰一点、英文占画面大一些的试试。",
            candidates=[],
            notes=notes,
        )

    # 圈选/划线：用视觉模型给出的白名单生成确定性回复，避免模型把“没圈出的词”也说成圈选词
    if (intent.get("mode") or "") == "marks":
        wanted = {
            str(w).strip().lower()
            for w in (intent.get("keep_words") or [])
            if str(w).strip()
        }
        marked_rows = [row for row in candidates if row["word"].lower() in wanted]
        marked = [row["word"] for row in marked_rows]
        if not marked:
            return ChatResponse(
                reply="没有识别到被圈/划线的单词，请换一张更清晰的照片，或手动勾选。",
                candidates=[],
                notes=notes,
            )

        marked_text = "、".join(marked[:20])
        kept_text = "、".join(row["word"] for row in kept[:20])
        actions: list[ChatAction] = []
        if not kept:
            reply = (
                f"你圈出了 {len(marked)} 个：{marked_text}。"
                "但按你的其他条件没有剩下单词。"
            )
        else:
            reply = f"你圈出了 {len(marked)} 个：{marked_text}。"
            if len(kept) < len(marked):
                reply += f"按你的要求保留 {len(kept)} 个：{kept_text}。"
            else:
                reply += "没有圈出的词不会收录。"
            if _wants_import(instruction, bool(req.image_base64)):
                actions = [ChatAction(words=_items(kept), reason="按圈选结果导入")]

        return ChatResponse(
            reply=reply,
            actions=actions,
            candidates=_items(marked_rows),
            notes=notes,
        )

    known = len([w for w in req.known_words if w.strip()])
    if not kept:
        detail = notes[-1] if notes else "没有符合要求的单词"
        return ChatResponse(
            reply=f"这次没有筛出单词：{detail}",
            candidates=_items(candidates),
            notes=notes,
        )
    reply, actions = _chat_with_tools(req, candidates, kept, known)

    # 用户说"先看看/先别导入"：模型就算调了工具也不写库
    if _SKIP_HINTS.search(instruction):
        actions = []
        if not reply or "导入" in reply or "写入" in reply:
            if kept:
                names = "、".join(row["word"] for row in kept[:12])
                tail = "…" if len(kept) > 12 else ""
                reply = f"筛出 {len(kept)} 个：{names}{tail}。要写进单词本跟我说一声。"
            else:
                reply = "按你的要求没剩下单词；可以放宽条件，或让我保留全部。"

    # 模型没调工具但用户确实要导入（发照片默认导入）：兜底按本轮筛选结果写入
    if not actions and _wants_import(instruction, bool(req.image_base64)) and kept:
        actions = [ChatAction(words=_items(kept), reason="按本轮筛选结果导入")]

    if not reply:
        imported = [w.word for action in actions for w in action.words]
        words = imported or [row["word"] for row in kept]
        names = "、".join(words[:12])
        tail = "…" if len(words) > 12 else ""
        condition = _condition_text(instruction)
        if actions:
            count = len(imported) or len(kept)
            reply = f"{condition}筛出 {count} 个：{names}{tail}，已写入单词本。"
        elif kept:
            reply = f"{condition}筛出 {len(kept)} 个：{names}{tail}。要写进单词本吗？"
        else:
            reply = "按你的要求没剩下单词；可以放宽条件，或让我保留全部。"

    return ChatResponse(
        reply=reply,
        actions=actions,
        candidates=_items(candidates),
        notes=notes,
    )
