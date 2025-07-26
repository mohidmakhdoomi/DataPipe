---
inclusion: always
---

# MCP Tool Parameter Validation

When calling MCP workflow tools, ALWAYS include all required parameters, especially:

## Critical Parameter Requirements

For these workflow tools, the `next_step_required` parameter is REQUIRED in every call:
- thinkdeep
- planner
- debug
- codereview
- precommit
- secaudit
- analyze
- refactor
- testgen
- consensus
- tracer
- docgen

## Parameter Rules
- Set `next_step_required: true` for intermediate steps
- Set `next_step_required: false` for final steps
- Never omit this parameter - it will cause validation failures

## Example
```json
{
  "step": "...",
  "step_number": 3,
  "total_steps": 3,
  "findings": "...",
  "next_step_required": false  // ALWAYS include this
}
```

This prevents MCP validation errors and ensures smooth workflow execution.