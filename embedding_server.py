#!/usr/bin/env python3
"""本地 Embedding Server — 實現 OpenAI /v1/embeddings 相容 API

使用 fastembed (ONNX) + BGE-small-zh 模型，無需 torch，離線可用。
首次啟動會自動下載模型 (~100MB)。

啟動: source venv/bin/activate && python3 embedding_server.py --port 9090
"""

import argparse
import json
import logging
import sys
from typing import List, Union

from flask import Flask, request, jsonify

app = Flask(__name__)
log = logging.getLogger("embedding_server")

MODEL = None
MODEL_NAME = "BAAI/bge-small-zh-v1.5"


def load_model():
    global MODEL
    from fastembed import TextEmbedding
    log.info("載入模型: %s (fastembed/ONNX) ...", MODEL_NAME)
    MODEL = TextEmbedding(model_name=MODEL_NAME)
    dim = get_embedding_dim()
    log.info("模型載入完成，維度: %d", dim)


def get_embedding_dim() -> int:
    if MODEL is None:
        return 0
    # fastembed stores embedding_dim internally
    return MODEL.embedding_dim if hasattr(MODEL, 'embedding_dim') else 512


def embed_texts(texts: List[str]) -> List[List[float]]:
    embeddings = list(MODEL.embed(texts))
    return [e.tolist() for e in embeddings]


@app.route("/v1/embeddings", methods=["POST"])
def embeddings():
    data = request.get_json(force=True, silent=True)
    if not data:
        return jsonify({"error": "invalid JSON"}), 400

    inp = data.get("input", "")
    if isinstance(inp, str):
        texts = [inp]
    elif isinstance(inp, list):
        texts = [str(t) for t in inp]
    else:
        return jsonify({"error": "input must be string or array"}), 400

    if not texts:
        return jsonify({"error": "empty input"}), 400

    try:
        embeddings = embed_texts(texts)
    except Exception as e:
        log.exception("embedding 失敗")
        return jsonify({"error": str(e)}), 500

    resp = {
        "object": "list",
        "data": [
            {
                "object": "embedding",
                "index": i,
                "embedding": emb,
            }
            for i, emb in enumerate(embeddings)
        ],
        "model": MODEL_NAME,
    }
    return jsonify(resp)


@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "model": MODEL_NAME,
        "dim": get_embedding_dim(),
    })


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=9090)
    parser.add_argument("--host", type=str, default="127.0.0.1")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(name)s] %(message)s")

    log.info("啟動 Embedding Server (fastembed/ONNX): %s:%d", args.host, args.port)
    load_model()

    app.run(host=args.host, port=args.port, debug=False)
