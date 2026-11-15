"""Synchronous Gemini adapter for Streamlit's request/response interaction model."""
import os

from google import genai

from metrics import usage_summary


def call_gemini(
    *,
    model,
    system_prompt,
    history,
    prompt,
    temperature,
    thinking_level,
    max_output_tokens,
    api_version,
):
    transcript = "\n\n".join(
        f'{("Student" if item["role"] == "user" else "Assistant")}:\n{item["content"]}'
        for item in [*history, {"role": "user", "content": prompt}]
    )
    client = genai.Client(
        api_key=os.environ["GEMINI_API_KEY"],
        http_options={"api_version": api_version},
    )
    try:
        response = client.interactions.create(
            model=model,
            input=transcript,
            system_instruction=system_prompt,
            generation_config={
                "thinking_level": thinking_level,
                "temperature": temperature,
                "max_output_tokens": max_output_tokens,
            },
            store=False,
        )
        answer = getattr(response, "output_text", "") or ""
        if not answer:
            raise ValueError("Gemini returned an empty response.")

        return {
            "text": answer,
            "usage": usage_summary(
                response,
                float(os.getenv("PLAYGROUND_GEMINI_INPUT_USD_PER_MILLION", "0")),
                float(os.getenv("PLAYGROUND_GEMINI_OUTPUT_USD_PER_MILLION", "0")),
            ),
        }
    finally:
        client.close()