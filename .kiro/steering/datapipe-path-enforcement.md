---
inclusion: always
---

# code2prompt get_context DataPipe Path Enforcement

## Purpose
This steering document ensures that when using the MCP tool `get_context`, the path parameter is always set to "DataPipe" for consistency and proper project context.

## Rule
When using the `mcp__code2prompt__get_context` tool, always set the `path` parameter to "DataPipe".

## Example Usage
```
mcp__code2prompt__get_context:
  path: "DataPipe"
  include_patterns: ["*.yaml", "*.md", "*.json"]
  exclude_patterns: ["logs/*"]
  include_hidden: true
```

## Rationale
- Maintains consistent project root reference
- Ensures all context gathering operates from the correct base directory
- Prevents path confusion in multi-directory projects
- Aligns with the established project structure where "DataPipe" is the root directory