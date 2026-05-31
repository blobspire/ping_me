---
description: Keep the Mac awake and notify when the current Claude Code task finishes
argument-hint: [optional task/reminder]
---

Use ping-me as a one-shot completion ping for the current Claude Code task only.

Immediately arm ping-me:

```bash
"$HOME/.local/share/ping-me/scripts/ping_me_request.sh" arm \
  --agent Claude \
  --message "The requested task finished."
```

If `$ARGUMENTS` describes work to do, do that work. If no arguments were provided, apply this to the current task already underway in the conversation.

When the task succeeds, run:

```bash
"$HOME/.local/share/ping-me/scripts/ping_me_request.sh" complete \
  --agent Claude \
  --status success
```

If the task fails, use `--status failure` and a short message describing the failed step.

If the task becomes blocked because you need user input or an external change, use `--status blocked` and a short message describing the blocker.

Do not include secrets, command output, file contents, tokens, or large logs in the notification message.
