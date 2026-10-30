# 单词筛选智能体（LangGraph）

把「拍照识别出来的文字」+「用户的一句话要求」变成「只保留该留的单词，并补齐音标/释义」。
这个服务是**可选**的：不启动它，App 仍可正常识别，只是不能按自然语言筛选。

## 它做什么

```
OCR 文本 ──► parse ──► understand ──┬─(要求看圈选且未授权看图)→ ask_image ─┐
                                    └─(其他)→ vision(可选) ───────────────┴─► filter ──► enrich ──► review ──► JSON
```

| 节点 | 作用 | 用到的能力 |
| --- | --- | --- |
| `parse` | 把 OCR 文本切成候选词（与 App 端规则一致） | 纯规则，不联网 |
| `understand` | 把「只要名词/只保留我不认识的/前 10 个」理解成结构化条件 | LLM 结构化输出 |
| `vision` | 可选：识别照片上被圈出/划线的单词 | 视觉模型（仅用户授权时） |
| `ask_image` | 要求看图但没授权 → 返回 `needs_image=true` 提示 | — |
| `filter` | 按条件（词性/长度/是否有释义/白名单）筛词 | 纯规则，可控 |
| `enrich` | 并发查音标（dictionaryapi.dev）+ 补缺失的中文释义 | 工具 + LLM |
| `review` | 筛空了自动回退为「保留全部」并说明 | 自愈，避免空结果 |

设计原则：**能规则判断的绝不交给模型**。模型只负责"理解意图"，筛选执行由确定性代码完成，避免模型漏词/幻觉。

## 启动

### 一键启动（推荐）

双击 **`agent/start.bat`**。它会自动：检查依赖 → 缺了就装 → 打印本机/局域网地址 → 启动服务。

关闭窗口即停止服务。

### 命令行启动

```bash
cd agent
python -m pip install -r requirements.txt   # 只在第一次或换 Python 后需要
python -m uvicorn app:app --host 0.0.0.0 --port 8787
```

### ⚠️ 最常见的启动失败：依赖装到了"另一个 Python"

`python -m uvicorn` 报下面这种错，基本只有一个原因 —— **`langgraph` 没装在当前这个 Python 里**：

```
File "...\uvicorn\importer.py", line 22, in import_from_string
    raise exc from None
```

电脑上常常有多个 Python（系统装一个、conda 一个、IDE 自带一个）。安装依赖和启动服务必须是**同一个解释器**：

```bash
# 看当前用的是哪个 Python
python -c "import sys; print(sys.executable)"

# 用同一个 python 装依赖
python -m pip install -r requirements.txt

# 再确认四个包都能导入（不报错就是好了）
python -c "import fastapi, uvicorn, langgraph, langchain_openai; print('deps ok')"
```

判断依据：报错路径里是 `...\Python310\Lib\site-packages\uvicorn\...`，就说明启动用的是 Python 3.10；
那就必须让 `...\Python310\python.exe -m pip install ...` 装上依赖，而不是别的版本。

> 本项目验证过的组合：Python 3.10 + fastapi 0.156 + langgraph 1.2.18 + langchain-openai 1.7.3；
> Python 3.13 同样可用。`requirements.txt` 用的是版本区间，因此两个版本都能装。

### 配置模型（可选）

复制 `.env.example` 为 `.env` 并填 Key；不填则自动进入离线模拟模式（规则模拟"理解意图"，不花钱）。

## 手机怎么连上这个服务（两种方式，任选）

服务默认监听 `0.0.0.0:8787`，两种连法：

### 方式 A：USB + adb reverse（推荐，最省事）

不用改防火墙，也不受校园网/公司网"客户端隔离"影响。

```bash
# 1) 电脑启动服务
cd agent && python -m uvicorn app:app --host 0.0.0.0 --port 8787

# 2) 另开一个终端，手机用 USB 连上电脑后执行（每次重新插拔都要执行一次）
adb reverse tcp:8787 tcp:8787
```

App 里 `agentBaseUrl` 填 `http://127.0.0.1:8787`（手机访问自己的 8787，被 adb 转发到电脑）。

### 方式 B：同一 Wi-Fi + 局域网 IP

```bash
# 先在本机确认服务活着
curl http://<电脑局域网IP>:8787/health
```

App 里填 `http://<电脑局域网IP>:8787`（Windows 用 `ipconfig` 看 WLAN 的 IPv4）。

如果连不上，按顺序检查：
1. Windows 网络类型是不是"公用"——公用档默认**阻止入站**，需要放行 8787 端口：

   ```
   New-NetFirewallRule -DisplayName "wordbook-agent" -Direction Inbound -Protocol TCP -LocalPort 8787 -Action Allow -Profile Private,Public
   ```

2. 第一次跑 uvicorn 时如果弹"是否允许 Python 访问网络"，要允许；
3. 学校/公司 Wi-Fi 常开"客户端隔离"，两台设备互相 ping 不通 —— 这种网络下只能用方式 A。

## 手机连不上服务？按这 4 条查

| # | 现象 | 原因 | 解决 |
| --- | --- | --- | --- |
| 1 | App 里显示"未配置" | `agentBaseUrl` 还是空的 | 填地址后**重新 Run**（热重载不生效） |
| 2 | 诊断提示"需要先执行 adb reverse" | 用了 `127.0.0.1` 但没做端口转发 | 执行 `adb reverse tcp:8787 tcp:8787`，或改填局域网 IP |
| 3 | 显示"这是大模型接口地址" | 把 `https://api.xxx.com/v1` 当成了智能体地址 | 智能体是 `http://IP:8787`；DeepSeek 那类只给大模型用 |
| 4 | 地址对但仍连不上 | 服务没启动 / 防火墙拦截 / 不在同一 Wi-Fi | 先在本机 `curl http://IP:8787/health`；再看上面方式 B 的 1–3 条 |

在电脑上验证：`curl http://127.0.0.1:8787/health`，
返回 `{"ok": true, "mock": false, "model": "deepseek-flash", ...}` 就说明服务与模型都正常
（`mock: true` 表示没读到 Key，退化成了关键词模拟）。

## 能听懂哪些要求

所有条件按"同时满足"处理，可以组合：

| 说法 | 处理方式 |
| --- | --- |
| 只要名词 / 动词 / 形容词 | 按词性筛；词性缺失时先用释义前缀和后缀规则推断，仍推断不出的单独标注 |
| 只保留我不认识的 / 生词 / 没学过的 | 用请求里的 `known_words`（App 传来的已掌握单词）确定性剔除，不靠模型猜难度 |
| 只保留和环保有关的 / 重点词 | 模型从候选里逐个人工挑选（`keep_words`） |
| 去掉 Tom 和 Beijing / 去掉人名 | 点名剔除（`drop_words`）或专名过滤（首字母大写 + 释义提示） |
| 只保留带释义的 / 带音标的 | **先补齐**音标和释义，再判断，避免原文没音标时整批被误判 |
| 前 10 个 / 最多 20 个 | 截断（`limit`） |
| 只提取我画圈的 | 需要图片，走视觉模型（`mode=marks`） |
| 只要第六单元的 | 候选词没有单元信息，模型会明确说明做不到，而不是假装筛过 |

筛选结果会带回 `notes`（如"按已掌握词表排除 12 个，保留生词 8 个"），
App 在确认页顶部用一行灰字展示，避免"筛没筛过看不出来"。


## 接口

### `GET /health`

```json
{"ok": true, "mock": false, "model": "deepseek-flash", "has_key": true}
```

### `POST /chat`（主用法，对话式）

请求：

```json
{
  "messages": [{"role": "user", "content": "只要名词，导入"}],
  "image_base64": "<照片 base64，可空>",
  "ocr_text": "<本地 OCR 文本，作读图兜底，可空>",
  "candidates": [{"word": "abandon", "phonetic": "/əˈbændən/", "meaning": "v. 放弃"}],
  "known_words": ["apple", "banana"],
  "max_words": 80
}
```

响应：

```json
{
  "reply": "已导入 2 个名词：ability、accident。去掉了动词 abandon、pollute。",
  "actions": [{"type": "import_words", "words": [{"word": "ability", "phonetic": "…", "meaning": "n. 能力"}], "reason": "按本轮筛选结果导入"}],
  "candidates": [{"word": "abandon", "phonetic": "…", "meaning": "v. 放弃"}],
  "notes": ["共 4 个候选，保留 2 个"]
}
```

约定：

- **服务端不存会话**。`messages` + 上一轮 `candidates` 由手机端带回，所以"单次上下文记忆"= App 里的聊天记录；
- `candidates` 只在"用户追问、没发新照片"时使用——在这批词上重新筛，不必重读图片；
- `actions` 里的 `import_words` **不由服务端执行**，手机端拿到后写 SQLite（数据不出手机）；
- 用户说"先看看/先别导入"时，即使模型调了工具也不会返回动作。

### `POST /extract`（旧接口，保留兼容）

一次性识别，不涉及对话与写库。请求/响应与 `/chat` 类似，`max_words` 默认 80。

```json
{
  "ocr_text": "1. abandon /əˈbændən/ v. 放弃\n2. ability [əˈbɪləti] n. 能力",
  "instruction": "只要名词",
  "allow_vision": false,
  "image_base64": null,
  "max_words": 80,
  "known_words": ["apple", "banana"]
}
```

`known_words` 是用户已掌握的单词（App 从本地库取），只在"只保留我不认识的"这类要求下生效；
不传也能用，只是会退回按常见难度估算。

响应：

```json
{
  "words": [
    {"word": "ability", "phonetic": "/əˈbɪl.ə.ti/", "meaning": "n. 能力", "reason": ""}
  ],
  "raw_count": 2,
  "kept_count": 1,
  "intent": {"mode": "none", "keep_pos": ["n"], "rationale": "用户只想要名词"},
  "notes": ["共 2 个候选，保留 1 个"],
  "needs_image": false
}
```

`needs_image=true` 表示：用户的要求需要看图片（如"只保留画圈的"），但没开启图片上传。

## 环境变量

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `AGENT_BASE_URL` | `https://api.openai.com/v1` | OpenAI 兼容接口地址 |
| `AGENT_API_KEY` | 空 | 为空时自动进入模拟模式 |
| `AGENT_MODEL` | `gpt-4o-mini` | 文本模型；DeepSeek 请填 `deepseek-flash`（V4.1-Flash 的 API 名称，`deepseek-chat` 已下线） |
| `AGENT_VISION_MODEL` | 同 `AGENT_MODEL` | 视觉模型；`deepseek-flash` 原生支持读图，无需另配 |
| `AGENT_MOCK` | `0` | 设 `1` 强制离线模拟 |
| `AGENT_HOST` / `AGENT_PORT` | `0.0.0.0` / `8787` | 监听地址 |

> DeepSeek V4.1-Flash 默认开启 thinking，本服务在 `AGENT_BASE_URL` 含 `deepseek` 时会自动
> 传 `thinking: {type: disabled}`，否则推理会吃掉 token 预算、甚至返回空正文。

## 隐私边界

- 默认**只上传 OCR 文字**，不上传图片（`allow_vision=false` 时请求体里没有 `image_base64`）。
- 只有用户在 App 里打开「允许上传照片识别圈选」，才会把这一张照片交给视觉模型。
- API Key 只在服务端（`.env` 或环境变量），App 里只有一个服务地址。
- 服务本身不落盘、不记录请求内容。

## 自测

```bash
# 图 + 工具，不启服务
AGENT_MOCK=1 python -c "
from graph import run_agent
s = run_agent('1. abandon v. 放弃\n2. ability n. 能力', '只要名词')
print([w['word'] for w in s['kept']])"

# 走 HTTP
curl -s -X POST http://127.0.0.1:8787/extract \
  -H 'Content-Type: application/json' \
  -d '{"ocr_text":"1. abandon v. 放弃\n2. ability n. 能力","instruction":"只要名词"}'
```

## 已知边界

- 圈选识别依赖视觉模型能力，手写笔迹浅/照片模糊时可能漏检，App 端仍可在确认页手动勾选。
- 音标来自免费词典接口，生僻词/短语可能查不到，此时留空而不是编造。
- 单实例、无鉴权，只适合局域网自用；要公网访问请自行加 Token 与 HTTPS。
