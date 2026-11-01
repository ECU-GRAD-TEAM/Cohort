"""Synchronous provider adapters for Streamlit's request/response interaction model."""
import os
from openai import OpenAI
from google import genai
from .metrics import usage_summary

def call_openai(*, model, system_prompt, history, prompt, temperature, reasoning_effort, verbosity, timeout, max_retries):
    client = OpenAI(api_key=os.environ["OPENAI_API_KEY"], timeout=timeout, max_retries=max_retries)
    try:
        response = client.responses.create(
            model=model, instructions=system_prompt,
            input=[*history, {"role": "user", "content": prompt}],
            temperature=temperature, reasoning={"effort": reasoning_effort},
            text={"verbosity": verbosity}, store=False,
        )
        return {"text": response.output_text or "", "usage": usage_summary(
            response, "OpenAI", float(os.getenv("PLAYGROUND_OPENAI_INPUT_USD_PER_MILLION", "0")),
            float(os.getenv("PLAYGROUND_OPENAI_OUTPUT_USD_PER_MILLION", "0"))), "raw": response}
    finally:
        client.close()

def call_gemini(*, model, system_prompt, history, prompt, temperature, thinking_level, max_output_tokens, api_version):
    transcript = "\\n\\n".join(
        f'{("Student" if item["role"] == "user" else "Assistant")}:\\n{item["content"]}'
        for item in [*history, {"role": "user", "content": prompt}]
    )
    client = genai.Client(api_key=os.environ["GEMINI_API_KEY"], http_options={"api_version": api_version})
    try:
        response = client.interactions.create(
            model=model, input=transcript, system_instruction=system_prompt,
            generation_config={"thinking_level": thinking_level, "temperature": temperature, "max_output_tokens": max_output_tokens},
            store=False,
        )
        return {"text": getattr(response, "output_text", "") or "", "usage": usage_summary(
            response, "Gemini", float(os.getenv("PLAYGROUND_GEMINI_INPUT_USD_PER_MILLION", "0")),
            float(os.getenv("PLAYGROUND_GEMINI_OUTPUT_USD_PER_MILLION", "0"))), "raw": response}
    finally:
        client.close()
