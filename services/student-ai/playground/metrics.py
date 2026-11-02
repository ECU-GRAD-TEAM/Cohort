"""Best-effort token and cost extraction from Gemini Interactions responses."""


def get_value(obj, *names, default=None):
    for name in names:
        if isinstance(obj, dict) and name in obj:
            return obj[name]
        value = getattr(obj, name, None)
        if value is not None:
            return value
    return default


def usage_summary(response, input_rate: float, output_rate: float) -> dict:
    usage = get_value(response, "usage", default=None)
    if usage is None:
        return {
            "input_tokens": None,
            "output_tokens": None,
            "total_tokens": None,
            "estimated_cost": None,
        }

    input_tokens = get_value(usage, "total_input_tokens", "prompt_token_count", "input_tokens")
    output_tokens = get_value(usage, "total_output_tokens", "candidates_token_count", "output_tokens")
    total = (
        input_tokens + output_tokens
        if isinstance(input_tokens, int) and isinstance(output_tokens, int)
        else get_value(usage, "total_tokens")
    )
    cost = (
        (input_tokens * input_rate + output_tokens * output_rate) / 1_000_000
        if isinstance(input_tokens, int) and isinstance(output_tokens, int)
        else None
    )
    return {
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "total_tokens": total,
        "estimated_cost": cost,
    }