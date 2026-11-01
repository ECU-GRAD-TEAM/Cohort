"""Environment-backed defaults for the local playground."""
import os
from dotenv import load_dotenv

load_dotenv()
DEFAULT_SYSTEM_PROMPT = os.getenv("PLAYGROUND_SYSTEM_PROMPT", "You are a helpful, accurate, patient assistant. Be clear about uncertainty.")

def setting(name: str, default: str) -> str:
    return os.getenv(name, default)

def enabled_providers() -> list[str]:
    return [name for name, key in [("OpenAI", "OPENAI_API_KEY"), ("Gemini", "GEMINI_API_KEY")] if os.getenv(key)]
