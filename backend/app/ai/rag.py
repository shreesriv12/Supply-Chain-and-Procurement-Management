from __future__ import annotations

from functools import lru_cache
import hashlib
import math

from .groq_client import complete
from ..db import run_sql


@lru_cache(maxsize=1)
def encoder():
    """
    Use MiniLM when available.
    Fall back to deterministic hash embeddings if model loading fails.

    Both embeddings have 384 dimensions, but their vector spaces differ.
    Documents and queries should use the same embedding method.
    """
    try:
        from sentence_transformers import SentenceTransformer

        return SentenceTransformer("all-MiniLM-L6-v2")

    except Exception as exc:
        print(
            f"WARNING: MiniLM could not be loaded: {exc}. "
            "Using hash embeddings instead."
        )
        return None


def embed(text: str) -> list[float]:
    """Generate a 384-dimensional embedding for the supplied text."""
    model = encoder()

    if model is not None:
        vector = model.encode(text).tolist()

        if len(vector) != 384:
            raise ValueError(
                f"Expected a 384-dimensional embedding, got {len(vector)}."
            )

        return vector

    # Deterministic fallback embedding with 384 dimensions.
    vector = [0.0] * 384

    for token in text.lower().split():
        digest = hashlib.sha256(token.encode("utf-8")).digest()
        index = int.from_bytes(digest[:2], "big") % 384
        vector[index] += 1 if digest[2] & 1 else -1

    magnitude = math.sqrt(sum(value * value for value in vector)) or 1.0

    return [value / magnitude for value in vector]


def chunks(text: str, size: int = 180) -> list[str]:
    """Split text into word-based chunks."""
    if size <= 0:
        raise ValueError("Chunk size must be greater than zero.")

    words = text.split()

    return [
        " ".join(words[i:i + size])
        for i in range(0, len(words), size)
        if words[i:i + size]
    ]


def index_text(
    doc_name: str,
    text: str,
    supplier_id: int | None = None,
) -> int:
    """
    Index a text document in PostgreSQL.

    Re-uploading the same document for the same supplier replaces its
    existing chunks. The return value remains an integer for compatibility
    with the current /rag/upload endpoint.
    """
    if not doc_name or not doc_name.strip():
        raise ValueError("Document name cannot be empty.")

    if not text or not text.strip():
        raise ValueError("The uploaded policy file is empty.")

    if supplier_id is not None and supplier_id <= 0:
        raise ValueError("Supplier ID must be greater than zero.")

    parts = chunks(text)

    if not parts:
        raise ValueError("No text chunks could be generated.")

    # Generate all embeddings before modifying existing document chunks.
    vectors = [embed(part) for part in parts]

    # Replace chunks only for this document and supplier combination.
    run_sql(
        """
        DELETE FROM document_chunk
        WHERE doc_name = %s
          AND supplier_id IS NOT DISTINCT FROM %s
        """,
        [doc_name, supplier_id],
        app_role="admin",
    )

    for part, vector in zip(parts, vectors):
        run_sql(
            """
            INSERT INTO document_chunk
                (supplier_id, doc_name, chunk_text, embedding)
            VALUES (%s, %s, %s, %s::vector)
            """,
            [supplier_id, doc_name, part, str(vector)],
            app_role="admin",
        )

    return len(parts)


def answer(question: str) -> dict:
    """Retrieve relevant policy excerpts and answer using those excerpts."""
    if not question or not question.strip():
        raise ValueError("Please enter a question.")

    vector = str(embed(question))

    result = run_sql(
        """
        SELECT chunk_id, doc_name, chunk_text
        FROM document_chunk
        WHERE embedding IS NOT NULL
        ORDER BY embedding <=> %s::vector
        LIMIT 4
        """,
        [vector],
        app_role="admin",
    )

    sources = result["data"]

    if not sources:
        return {
            "answer": (
                "I don't know because no policy excerpts have been indexed. "
                "Upload a .txt policy document first."
            ),
            "sources": [],
        }

    context = "\n\n".join(
        f"[{row['doc_name']} #{row['chunk_id']}] {row['chunk_text']}"
        for row in sources
    )

    response = complete(
        (
            "Answer only from the supplied contract/policy excerpts. "
            "Cite excerpt labels such as [policy.txt #1]. "
            "If the answer is absent from the excerpts, say you do not know. "
            "Do not invent policy terms, payment conditions, or penalties."
        ),
        f"Question: {question}\n\nExcerpts:\n{context}",
    )

    return {
        "answer": response,
        "sources": sources,
    }