from __future__ import annotations
import os
from openai import OpenAI

MODEL = os.getenv("GROQ_MODEL", "openai/gpt-oss-20b")
def complete(instructions: str, prompt: str) -> str:
    key = os.getenv("GROQ_API_KEY")
    if not key: raise RuntimeError("GROQ_API_KEY is not configured")
    client = OpenAI(api_key=key, base_url="https://api.groq.com/openai/v1")
    response = client.responses.create(model=MODEL, instructions=instructions, input=prompt)
    return response.output_text.strip()
