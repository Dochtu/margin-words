"""FastAPI 入口：把 LangGraph 智能体包装成 HTTP 接口。

启动：
    cd agent
    python -m uvicorn app:app --host 0.0.0.0 --port 8787

接口：
    GET  /health     健康检查
    POST /chat       对话式：发照片/文字 → 筛词 → 导入单词本（主用法）
    POST /extract    一次性识别（保留兼容，App 已改用 /chat）
    GET  /docs       自动生成的接口文档
"""

from __future__ import annotations

import os
import time

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from chat import handle_chat
from graph import MOCK, MODEL, run_agent
from schemas import (
    ChatRequest,
    ChatResponse,
    ExtractRequest,
    ExtractResponse,
    WordItem,
)

app = FastAPI(
    title="错题单词本 · 单词筛选智能体",
    version="2.0.0",
    description="对话式：读照片 → 理解要求 → 筛词 → 导入单词本",
)

# 手机与电脑同网段直连；如需公网访问请自行加鉴权与 HTTPS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict:
    return {
        "ok": True,
        "mock": MOCK,
        "model": "mock" if MOCK else MODEL,
        "has_key": bool(os.getenv("AGENT_API_KEY")),
        "time": int(time.time()),
    }


@app.post("/chat", response_model=ChatResponse)
def chat(req: ChatRequest) -> ChatResponse:
    """对话一轮：可带照片，也可只带文字；需要写入单词本时返回 import_words 动作。"""
    return handle_chat(req)


@app.post("/extract", response_model=ExtractResponse)
def extract(req: ExtractRequest) -> ExtractResponse:
    state = run_agent(
        ocr_text=req.ocr_text,
        instruction=req.instruction,
        image_base64=req.image_base64,
        allow_vision=req.allow_vision,
        max_words=req.max_words,
        known_words=req.known_words,
    )
    kept = state.get("kept") or []

    intent = dict(state.get("intent") or {})
    words = [
        WordItem(
            word=w["word"],
            phonetic=w.get("phonetic", ""),
            meaning=w.get("meaning", ""),
            reason=intent.get("rationale", "") if len(kept) < len(state.get("candidates") or []) else "",
        )
        for w in kept
    ]

    return ExtractResponse(
        words=words,
        raw_count=len(state.get("candidates") or []),
        kept_count=len(words),
        intent=intent,
        notes=list(dict.fromkeys(state.get("notes") or [])),  # 去重保序
        needs_image=bool(state.get("needs_image")),
    )


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "app:app",
        host=os.getenv("AGENT_HOST", "0.0.0.0"),
        port=int(os.getenv("AGENT_PORT", "8787")),
        reload=False,
    )
