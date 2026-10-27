from __future__ import annotations
from functools import lru_cache
import hashlib
import math
from pypdf import PdfReader
from .groq_client import complete
from ..db import run_sql

@lru_cache(maxsize=1)
def encoder():
    """Use MiniLM when optionally installed; otherwise keep Docker lightweight.

    The fallback is a deterministic signed-hash embedding in the same 384-vector
    space. It preserves RAG functionality for demos without requiring PyTorch.
    """
    try:
        from sentence_transformers import SentenceTransformer
        return SentenceTransformer("all-MiniLM-L6-v2")
    except ImportError:
        return None

def embed(text: str) -> list[float]:
    model = encoder()
    if model is not None:
        return model.encode(text).tolist()
    vector = [0.0] * 384
    for token in text.lower().split():
        digest = hashlib.sha256(token.encode("utf-8")).digest()
        index = int.from_bytes(digest[:2], "big") % 384
        vector[index] += 1 if digest[2] & 1 else -1
    magnitude = math.sqrt(sum(value * value for value in vector)) or 1.0
    return [value / magnitude for value in vector]
def chunks(text: str, size: int = 180) -> list[str]:
    words = text.split(); return [" ".join(words[i:i+size]) for i in range(0, len(words), size) if words[i:i+size]]
def index_text(doc_name: str, text: str, supplier_id: int | None = None) -> int:
    parts = chunks(text); vectors = [embed(part) for part in parts]
    for part, vector in zip(parts, vectors): run_sql("INSERT INTO document_chunk(supplier_id,doc_name,chunk_text,embedding) VALUES (%s,%s,%s,%s::vector)", [supplier_id, doc_name, part, str(vector)], app_role="admin")
    return len(parts)
def answer(question: str) -> dict:
    vector = str(embed(question))
    result = run_sql("SELECT chunk_id,doc_name,chunk_text FROM document_chunk ORDER BY embedding <=> %s::vector LIMIT 4", [vector], app_role="admin")
    context = "\n\n".join(f"[{row['doc_name']} #{row['chunk_id']}] {row['chunk_text']}" for row in result["data"])
    text = complete("Answer only from the supplied contract/policy excerpts. Cite excerpt labels. If absent, say you do not know.", f"Question: {question}\n\nExcerpts:\n{context}")
    return {"answer": text, "sources": result["data"]}
