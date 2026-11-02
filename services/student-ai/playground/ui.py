"""Local Gemini playground. Run with: streamlit run playground/ui.py"""
import time

import streamlit as st

from configuration import DEFAULT_SYSTEM_PROMPT, setting
from providers import call_gemini

st.set_page_config(page_title="Cohort Gemini Playground", page_icon="🧪", layout="wide")
st.title("🧪 Cohort Gemini Playground")
st.caption(
    "Private local workspace for experimenting with Gemini 3.5 Flash-Lite. "
    "Not the student-facing Cohort UI."
)

if not setting("GEMINI_API_KEY", ""):
    st.error("GEMINI_API_KEY is missing. Add it to services/student-ai/.env, then restart Streamlit.")
    st.stop()

if "messages" not in st.session_state:
    st.session_state.messages = []
if "system_prompt" not in st.session_state:
    st.session_state.system_prompt = DEFAULT_SYSTEM_PROMPT

with st.sidebar:
    st.header("Experiment settings")
    model = st.text_input(
        "Gemini model",
        setting("PLAYGROUND_GEMINI_MODEL", setting("GEMINI_MODEL", "gemini-3.5-flash-lite")),
    )
    temperature = st.slider(
        "Temperature",
        0.0,
        2.0,
        float(setting("PLAYGROUND_TEMPERATURE", "0.7")),
        0.05,
    )
    thinking_levels = ["minimal", "low", "medium", "high"]
    configured_thinking = setting("GEMINI_THINKING_LEVEL", "medium")
    thinking = st.selectbox(
        "Thinking level",
        thinking_levels,
        index=thinking_levels.index(configured_thinking)
        if configured_thinking in thinking_levels
        else 2,
    )
    max_tokens = st.number_input(
        "Maximum output tokens",
        1,
        65536,
        int(setting("GEMINI_MAX_OUTPUT_TOKENS", "8192")),
        256,
    )
    if st.button("New conversation", use_container_width=True):
        st.session_state.messages = []
        st.rerun()
    if st.button("Reset system prompt", use_container_width=True):
        st.session_state.system_prompt = DEFAULT_SYSTEM_PROMPT
    st.caption("Settings apply to the next request. Your API key is never displayed.")

st.session_state.system_prompt = st.text_area(
    "System prompt",
    value=st.session_state.system_prompt,
    height=180,
)

for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])
        if message.get("meta"):
            st.caption(message["meta"])

prompt = st.chat_input("Send a prompt to Gemini…")
if prompt:
    st.session_state.messages.append({"role": "user", "content": prompt})
    history = [
        {"role": message["role"], "content": message["content"]}
        for message in st.session_state.messages[:-1]
    ]

    with st.chat_message("assistant"):
        started = time.perf_counter()
        try:
            result = call_gemini(
                model=model,
                system_prompt=st.session_state.system_prompt,
                history=history,
                prompt=prompt,
                temperature=temperature,
                thinking_level=thinking,
                max_output_tokens=int(max_tokens),
                api_version=setting("GEMINI_API_VERSION", "v1"),
            )
            elapsed = time.perf_counter() - started
            st.markdown(result["text"])

            usage = result["usage"]
            details = f"Latency: {elapsed:.2f}s"
            if usage["input_tokens"] is not None:
                details += (
                    f" · Tokens in/out: {usage['input_tokens']}/{usage['output_tokens']}"
                )
            if usage["estimated_cost"] is not None:
                details += f" · Estimated cost: ${usage['estimated_cost']:.6f}"
            else:
                details += " · Cost unavailable (set Gemini pricing rates in .env)"
            st.caption(details)
            with st.expander("Usage details"):
                st.json(usage)

            st.session_state.messages.append(
                {"role": "assistant", "content": result["text"], "meta": details}
            )
        except Exception as exc:
            st.error(f"Gemini request failed ({type(exc).__name__}): {exc}")
            st.session_state.messages.append(
                {"role": "assistant", "content": "The Gemini request failed.", "meta": "Request failed"}
            )