"""Local Streamlit LLM playground. Run with: streamlit run playground/ui.py"""
import os
import time
import streamlit as st
from configuration import DEFAULT_SYSTEM_PROMPT, enabled_providers, setting
from providers import call_gemini, call_openai

st.set_page_config(page_title="Cohort LLM Playground", page_icon="🧪", layout="wide")
st.title("🧪 Cohort LLM Playground")
st.caption("Private local workspace for experimenting with language models. Not the student-facing Cohort UI.")
providers = enabled_providers()
if not providers:
    st.error("No provider API key found. Add OPENAI_API_KEY and/or GEMINI_API_KEY to services/student-ai/.env, then restart Streamlit.")
    st.stop()
if "messages" not in st.session_state: st.session_state.messages = []
if "system_prompt" not in st.session_state: st.session_state.system_prompt = DEFAULT_SYSTEM_PROMPT

with st.sidebar:
    st.header("Experiment settings")
    mode = st.radio("Mode", ["Single model", "Compare providers"])
    provider = st.selectbox("Provider", providers, disabled=mode == "Compare providers")
    openai_model = st.text_input("OpenAI model", setting("PLAYGROUND_OPENAI_MODEL", setting("OPENAI_MODEL", "gpt-6-luna")))
    gemini_model = st.text_input("Gemini model", setting("PLAYGROUND_GEMINI_MODEL", setting("GEMINI_MODEL", "gemini-3.5-flash-lite")))
    st.divider()
    temperature = st.slider("Temperature", 0.0, 2.0, float(setting("PLAYGROUND_TEMPERATURE", "0.7")), 0.05)
    oe = ["none", "low", "medium", "high"]; ov = ["low", "medium", "high"]; gt = ["minimal", "low", "medium", "high"]
    reasoning = st.selectbox("OpenAI reasoning effort", oe, index=oe.index(setting("OPENAI_REASONING_EFFORT", "medium")) if setting("OPENAI_REASONING_EFFORT", "medium") in oe else 2)
    verbosity = st.selectbox("OpenAI text verbosity", ov, index=ov.index(setting("OPENAI_TEXT_VERBOSITY", "medium")) if setting("OPENAI_TEXT_VERBOSITY", "medium") in ov else 1)
    thinking = st.selectbox("Gemini thinking level", gt, index=gt.index(setting("GEMINI_THINKING_LEVEL", "medium")) if setting("GEMINI_THINKING_LEVEL", "medium") in gt else 2)
    max_tokens = st.number_input("Gemini max output tokens", 1, 65536, int(setting("GEMINI_MAX_OUTPUT_TOKENS", "8192")), 256)
    timeout = st.number_input("OpenAI timeout (seconds)", 5, 300, int(setting("OPENAI_TIMEOUT_SECONDS", "60")))
    retries = st.number_input("OpenAI retries", 0, 10, int(setting("OPENAI_MAX_RETRIES", "2")))
    if st.button("New conversation", use_container_width=True):
        st.session_state.messages = []; st.rerun()
    if st.button("Reset system prompt", use_container_width=True): st.session_state.system_prompt = DEFAULT_SYSTEM_PROMPT
    st.caption("Settings apply to the next request. API keys are never displayed.")

st.session_state.system_prompt = st.text_area("System prompt", value=st.session_state.system_prompt, height=140)
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])
        if message.get("meta"): st.caption(message["meta"])
prompt = st.chat_input("Send a prompt to the model…")
if prompt:
    st.session_state.messages.append({"role": "user", "content": prompt})
    history = [{"role": m["role"], "content": m["content"]} for m in st.session_state.messages[:-1]]
    targets = providers if mode == "Compare providers" else [provider]
    results = []
    with st.chat_message("assistant"):
        cols = st.columns(len(targets))
        for col, target in zip(cols, targets):
            with col:
                st.markdown("**" + target + "**")
                started = time.perf_counter()
                try:
                    if target == "OpenAI":
                        result = call_openai(model=openai_model, system_prompt=st.session_state.system_prompt, history=history, prompt=prompt, reasoning_effort=reasoning, verbosity=verbosity, timeout=float(timeout), max_retries=int(retries))
                    else:
                        result = call_gemini(model=gemini_model, system_prompt=st.session_state.system_prompt, history=history, prompt=prompt, temperature=temperature, thinking_level=thinking, max_output_tokens=int(max_tokens), api_version=setting("GEMINI_API_VERSION", "v1"))
                    elapsed = time.perf_counter() - started
                    st.markdown(result["text"] or "_Empty response._")
                    u = result["usage"]
                    detail = "Latency: %.2fs" % elapsed
                    if u["input_tokens"] is not None: detail += " · Tokens in/out: %s/%s" % (u["input_tokens"], u["output_tokens"])
                    if u["estimated_cost"] is not None: detail += " · Estimated cost: $%.6f" % u["estimated_cost"]
                    else: detail += " · Cost unavailable (set pricing rates in .env)"
                    st.caption(detail)
                    with st.expander("Usage details"): st.json(u)
                    results.append({"provider": target, "text": result["text"], "meta": detail})
                except Exception as exc:
                    st.error(type(exc).__name__ + ": " + str(exc))
                    results.append({"provider": target, "text": "Request failed: " + str(exc), "meta": "Request failed"})
    preferred = provider if mode == "Single model" else ("OpenAI" if "OpenAI" in providers else providers[0])
    chosen = next((r for r in results if r["provider"] == preferred), results[0])
    st.session_state.messages.append({"role": "assistant", "content": chosen["text"], "meta": chosen["provider"] + " · " + chosen["meta"]})
