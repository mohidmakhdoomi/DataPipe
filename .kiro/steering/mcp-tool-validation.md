---
inclusion: always
---

# Zen MCP Server Tool Parameter Validation

## Purpose
This steering document ensures that when using the Zen MCP tools, the required parameters are ALWAYS included.

### MINIMUM REQUIRED Parameters for tools: analyze,codereview,consensus,debug,docgen,planner,precommit,refactor,secaudit,testgen,thinkdeep,tracer:
- `next_step_required` (boolean, required)
- `step` (string, required)
- `step_number` (integer, required)
- `total_steps` (integer, required)

### MINIMUM REQUIRED Parameters for tools: challenge,chat:
- `prompt` (string, required)

## next_step_required Rules
- Set `next_step_required: true` for intermediate steps
- Set `next_step_required: false` for final steps
- Never omit required parameters - causes validation failures