---
description: Keep the Mac awake and notify when the current Claude Code task finishes
argument-hint: [optional task/reminder]
disable-model-invocation: true
---

One-shot completion ping for the current Claude Code task. This runs only when the user types `/ping-me`. Arming a ping never replaces or shortens the actual work.

1. Arm immediately with a short, specific message naming the task. This also starts the caffeinate wake guard, and the completion ping reuses this message, so make it descriptive:

```bash
"$HOME/.local/share/ping-me/scripts/ping_me_request.sh" arm \
  --agent Claude \
  --message "Test suite run finished."
```

Replace the message with one short line naming the user's actual task.

2. Do the task. If `$ARGUMENTS` names work to do, do that; otherwise apply this to the task already underway in the conversation. Complete it exactly as you normally would — do not skip, shorten, or rush any step because a ping is pending.

3. When the task finishes, complete in the background (this reuses the armed message):

```bash
"$HOME/.local/share/ping-me/scripts/ping_me_request.sh" complete \
  --agent Claude \
  --status success \
  --background
```

If the task failed, add `--status failure --message "<short failed step>"`. If it is blocked because you need user input or an external change, add `--status blocked --message "<short blocker>"`.

If the optional Stop hook is installed, it completes the armed ping automatically when Claude stops — so the notification still arrives even if you do not reach step 3, and completion is claim-locked so only one ping is ever sent. Keep messages to one short line. Never include secrets, command output, file contents, tokens, or large logs.
