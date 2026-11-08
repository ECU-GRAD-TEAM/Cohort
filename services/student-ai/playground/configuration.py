"""Environment-backed defaults for the local Gemini playground."""
import os
from dotenv import load_dotenv

load_dotenv()

DEFAULT_SYSTEM_PROMPT = os.getenv(
    "PLAYGROUND_SYSTEM_PROMPT",
    "You are a helpful, accurate, patient assistant. Be clear about uncertainty.",
)


def setting(name: str, default: str) -> str:
    return os.getenv(name, default)