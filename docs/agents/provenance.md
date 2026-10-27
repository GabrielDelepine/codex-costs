# Codex and model attribution

Use this guide when writing or updating the Codex attribution in a PR description. Identify OpenAI Codex and the exact verified model IDs; a display name may accompany an ID, for example GPT-6.1 Sol (`gpt-6.1-sol`). State explicitly when Codex implemented the change and opened the PR autonomously.

## Model verification

Resolve the model with minimal resource use and output:

1. When the task context supplies a `.codex/visualizations/.../<thread-id>` path, extract the conversation ID from its last segment. Never call `list_threads` when this path is available. If no reliable conversation ID is available, report that limitation rather than guessing.
2. Locate the corresponding log by filename with `rg --files --hidden` in `$CODEX_HOME/sessions` and `$CODEX_HOME/archived_sessions` (`CODEX_HOME` defaults to `~/.codex`). Match only `*<thread-id>*`; do not search the contents of unrelated session logs.
3. Stream the matching file locally and inspect only JSON records whose top-level `type` is `turn_context`. Extract `payload.model`; output only the distinct model IDs and the latest model ID. Never print full log lines or conversation contents. If the matching log is unavailable or the format does not expose a model ID, report that limitation.
4. Attribute the changes to the model recorded for the turns that produced them. The latest model ID alone does not establish authorship of earlier changes. If multiple models contributed, disclose each one. For changes carried over from another source, preserve verified attribution when available and disclose any attribution gaps.
5. Never infer the model from global settings, available model lists, a generic identity such as GPT-6, or unrelated session records. If the evidence cannot establish which model produced a change, explicitly report that limitation.

Keep session logs read-only and local. Publish only the necessary model attribution and its limitations, never conversation IDs, personal paths, or log contents.
