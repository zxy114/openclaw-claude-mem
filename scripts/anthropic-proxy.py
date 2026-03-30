#!/usr/bin/env python3
"""
Anthropic-to-OpenAI proxy for claude-mem
Translates Anthropic /v1/messages API calls to OpenAI-compatible format (GLM, etc.)
Allows claude-mem to use any OpenAI-compatible LLM for memory generation.
"""
import json, os, sys, time, uuid
from flask import Flask, request, Response, jsonify
import urllib.request, urllib.error

app = Flask(__name__)

GLM_API_KEY = os.environ.get("GLM_API_KEY", "")
GLM_BASE_URL = os.environ.get("GLM_BASE_URL", "https://open.bigmodel.cn/api/paas/v4")
GLM_MODEL = os.environ.get("GLM_MODEL", "glm-4-flash")
PORT = int(os.environ.get("PORT", "9191"))

def anthropic_to_openai(body):
    messages = []
    if body.get("system"):
        messages.append({"role": "system", "content": body["system"]})
    for msg in body.get("messages", []):
        content = msg["content"]
        if isinstance(content, list):
            text = " ".join(b["text"] for b in content if b.get("type") == "text")
        else:
            text = str(content)
        messages.append({"role": msg["role"], "content": text})
    return {
        "model": GLM_MODEL,
        "messages": messages,
        "max_tokens": body.get("max_tokens", 2048),
        "stream": body.get("stream", False),
        "temperature": 0.3,
    }

def openai_to_anthropic(resp_json):
    choice = resp_json["choices"][0]
    text = choice["message"]["content"] or ""
    usage = resp_json.get("usage", {})
    return {
        "id": "msg_" + resp_json.get("id", uuid.uuid4().hex)[:24],
        "type": "message",
        "role": "assistant",
        "content": [{"type": "text", "text": text}],
        "model": GLM_MODEL,
        "stop_reason": "end_turn",
        "stop_sequence": None,
        "usage": {
            "input_tokens": usage.get("prompt_tokens", 0),
            "output_tokens": usage.get("completion_tokens", 0),
        },
    }

def stream_openai_to_anthropic(openai_stream):
    msg_id = "msg_" + uuid.uuid4().hex[:24]
    yield f'data: {json.dumps({"type":"message_start","message":{"id":msg_id,"type":"message","role":"assistant","content":[],"model":GLM_MODEL,"stop_reason":None,"usage":{"input_tokens":0,"output_tokens":0}}})}\n\n'
    yield f'data: {json.dumps({"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}})}\n\n'
    for line in openai_stream.splitlines():
        if not line.startswith("data: "): continue
        data = line[6:]
        if data == "[DONE]": break
        try:
            chunk = json.loads(data)
            delta = chunk["choices"][0].get("delta", {})
            text = delta.get("content") or ""
            if text:
                yield f'data: {json.dumps({"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":text}})}\n\n'
        except Exception: pass
    yield f'data: {json.dumps({"type":"content_block_stop","index":0})}\n\n'
    yield f'data: {json.dumps({"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":None},"usage":{"output_tokens":0}})}\n\n'
    yield f'data: {json.dumps({"type":"message_stop"})}\n\n'

@app.route("/v1/messages", methods=["POST"])
def messages():
    body = request.get_json()
    openai_body = anthropic_to_openai(body)
    is_stream = openai_body.get("stream", False)
    url = f"{GLM_BASE_URL}/chat/completions"
    req_data = json.dumps(openai_body).encode()
    req = urllib.request.Request(url, data=req_data,
        headers={"Authorization": f"Bearer {GLM_API_KEY}", "Content-Type": "application/json"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            resp_text = resp.read().decode()
        if is_stream:
            return Response(stream_openai_to_anthropic(resp_text), content_type="text/event-stream")
        return jsonify(openai_to_anthropic(json.loads(resp_text)))
    except urllib.error.HTTPError as e:
        return jsonify({"error": str(e)}), e.code

@app.route("/v1/models", methods=["GET"])
def models():
    return jsonify({"data": [{"id": "claude-sonnet-4-5", "object": "model"}]})

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "model": GLM_MODEL, "base_url": GLM_BASE_URL})

if __name__ == "__main__":
    if not GLM_API_KEY:
        print("ERROR: GLM_API_KEY not set. Set via environment variable or edit this file.", file=sys.stderr)
        sys.exit(1)
    print(f"Anthropic-to-OpenAI proxy starting on port {PORT} (model: {GLM_MODEL})", flush=True)
    app.run(host="127.0.0.1", port=PORT, debug=False)
