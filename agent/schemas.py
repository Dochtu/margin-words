"""智能体服务的请求/响应模型。"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field


class WordItem(BaseModel):
    word: str = Field(description="英文单词或短语")
    phonetic: str = Field(default="", description="音标，形如 /ˈæpl/，未知则空")
    meaning: str = Field(default="", description="中文释义")
    reason: str = Field(default="", description="为什么保留它（给用户看的短句）")


class ExtractRequest(BaseModel):
    ocr_text: str = Field(description="本地 OCR 出来的原始文字")
    instruction: str = Field(default="", description="用户的自然语言筛选要求")
    image_base64: str | None = Field(
        default=None, description="可选：图片 base64（仅在用户允许上传时提供）"
    )
    allow_vision: bool = Field(default=False, description="是否允许把图片交给视觉模型")
    max_words: int = Field(default=80, ge=1, le=120)
    known_words: list[str] = Field(
        default_factory=list,
        description="用户已掌握/已在单词本里的单词，用于理解「只保留我不认识的」",
    )


class Intent(BaseModel):
    """LLM 对筛选意图的结构化理解。"""

    mode: Literal["none", "semantic", "marks"] = "none"
    keep_words: list[str] = Field(
        default_factory=list,
        description="需要保留的单词（只能来自候选词），空表示不做逐个挑选",
    )
    drop_words: list[str] = Field(
        default_factory=list,
        description="用户点名要剔除的单词（只能来自候选词）",
    )
    keep_pos: list[str] = Field(default_factory=list, description="保留的词性，如 n./v.")
    drop_pos: list[str] = Field(default_factory=list, description="剔除的词性")
    require_meaning: bool = Field(default=False, description="只保留能给出中文释义的")
    require_phonetic: bool = Field(default=False, description="只保留能给出音标的")
    min_length: int = 0
    max_length: int = 0
    exclude_proper_noun: bool = Field(
        default=False, description="剔除人名/地名等专有名词（仅当用户明确要求）"
    )
    keyword_in_meaning: str = ""
    limit: int = 0
    rationale: str = ""


class ExtractResponse(BaseModel):
    words: list[WordItem]
    raw_count: int = 0
    kept_count: int = 0
    intent: dict[str, Any] = Field(default_factory=dict)
    notes: list[str] = Field(default_factory=list)
    needs_image: bool = False


# --------------------------------------------------------------- 对话模式


class ChatMessage(BaseModel):
    role: Literal["user", "assistant"] = "user"
    content: str = ""


class ChatRequest(BaseModel):
    """对话请求：服务端不存会话，上下文由手机端每轮带上（单次会话记忆）。"""

    messages: list[ChatMessage] = Field(default_factory=list)
    image_base64: str | None = Field(default=None, description="本轮新发的照片")
    ocr_text: str | None = Field(default=None, description="本地 OCR 出来的文字，可作读图兜底")
    candidates: list[WordItem] = Field(
        default_factory=list,
        description="上一轮得到的候选词；用户再提要求时在这批词上重筛，不用重读照片",
    )
    known_words: list[str] = Field(default_factory=list)
    max_words: int = Field(default=80, ge=1, le=120)


class ChatAction(BaseModel):
    """需要手机端执行的动作（服务端不直接碰手机上的数据库）。"""

    type: Literal["import_words"] = "import_words"
    words: list[WordItem]
    reason: str = ""


class ChatResponse(BaseModel):
    reply: str
    actions: list[ChatAction] = Field(default_factory=list)
    candidates: list[WordItem] = Field(default_factory=list)
    notes: list[str] = Field(default_factory=list)
