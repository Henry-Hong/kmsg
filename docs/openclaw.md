# OpenClaw Integration Guide

This guide shows how to connect `kmsg` to OpenClaw through MCP.

## Overview

The repository includes a local MCP stdio server:

- `tools/kmsg-mcp.py`

It exposes 2 tools:

- `kmsg_read`: reads KakaoTalk messages using `kmsg read --json`
- `kmsg_send`: sends KakaoTalk messages using `kmsg send` (requires explicit confirmation)

## Prerequisites

- macOS with KakaoTalk installed
- Accessibility permission granted for `kmsg`
- `kmsg` binary installed and executable
- Python 3 available

Check first:

```bash
kmsg --version
kmsg status
python3 -m py_compile tools/kmsg-mcp.py
```

## Run MCP server manually

```bash
python3 tools/kmsg-mcp.py
```

Optional environment variables:

- `KMSG_BIN`: absolute path to `kmsg` binary
- `KMSG_DEFAULT_DEEP_RECOVERY`: `true` or `false`
- `KMSG_TRACE_DEFAULT`: `true` or `false`

## OpenClaw MCP config example

Use your OpenClaw MCP config file and register this server:

```json
{
  "mcpServers": {
    "kmsg": {
      "command": "python3",
      "args": ["/ABS/PATH/TO/kmsg/tools/kmsg-mcp.py"],
      "env": {
        "KMSG_BIN": "/Users/you/.local/bin/kmsg",
        "KMSG_DEFAULT_DEEP_RECOVERY": "false",
        "KMSG_TRACE_DEFAULT": "false"
      }
    }
  }
}
```

You can also copy and edit:

- `docs/openclaw.mcp.example.json`

## Tool contracts

## `kmsg_read`

Input:

```json
{
  "chat": "홍근이 일기장",
  "limit": 20,
  "deep_recovery": false,
  "keep_window": false,
  "trace_ax": false
}
```

Success output shape:

```json
{
  "ok": true,
  "chat": "홍근이 일기장",
  "fetched_at": "2026-02-26T03:10:10.123Z",
  "count": 20,
  "messages": [
    {
      "author": "한홍근",
      "time_raw": "00:27",
      "body": "암튼 희찬이가 포스터 만들었던거 생각나네"
    }
  ],
  "meta": {
    "latency_ms": 1820
  }
}
```

## `kmsg_send`

Input:

```json
{
  "chat": "홍근이 일기장",
  "message": "테스트 메시지",
  "confirm": true,
  "deep_recovery": false,
  "keep_window": false,
  "trace_ax": false
}
```

Notes:

- `confirm` must be `true`; otherwise send is rejected with `CONFIRMATION_REQUIRED`.
- This enforces a confirmation step in agent workflows.

## Error model

Both tools return structured errors with:

- `ok: false`
- `error.code`
- `error.message`
- `error.hint`
- `error.raw_stdout`
- `error.raw_stderr`
- `meta.latency_ms`

Common `error.code` values:

- `CHAT_NOT_FOUND`
- `KMSG_BIN_NOT_FOUND`
- `KAKAO_WINDOW_UNAVAILABLE`
- `ACCESSIBILITY_PERMISSION_DENIED`
- `PROCESS_TIMEOUT`
- `INVALID_JSON_OUTPUT`
- `CONFIRMATION_REQUIRED`
- `UNKNOWN_EXEC_FAILURE`

## Recommended prompting pattern in OpenClaw

1. Use `kmsg_read` to fetch latest context.
2. Draft reply.
3. Ask user for approval.
4. Call `kmsg_send` only with `confirm=true` after approval.

## Troubleshooting

If `kmsg_read` fails:

1. Run manually with trace:
   - `kmsg read "채팅방" --json --trace-ax --deep-recovery`
2. Inspect UI tree:
   - `kmsg inspect --window 0 --depth 20`
3. Keep KakaoTalk visible and responsive during tool calls.

If MCP startup check reports failure, validate `KMSG_BIN` and run `kmsg status` directly.
