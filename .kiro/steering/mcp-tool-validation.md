---
inclusion: always
---

# zenDocker MCP Tool Parameter Validation

Absolute highest priority is to ensure required parameters are included for ALL zenDocker MCP tool calls.

### MINIMUM REQUIRED Parameters for tools: analyze,codereview,consensus,debug,docgen,planner,precommit,refactor,secaudit,testgen,thinkdeep,tracer:
- `step` (string, required)
- `step_number` (integer, required)
- `total_steps` (integer, required)
- `next_step_required` (boolean, required)

### MINIMUM REQUIRED Parameters for tools: challenge,chat:
- `prompt` (string, required)

## next_step_required Rules
- Set `next_step_required: true` for intermediate steps
- Set `next_step_required: false` for final steps
- Never omit required parameters - causes validation failures
```