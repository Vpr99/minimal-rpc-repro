# Minimal Sandbox IPC + Startup Overhead Repro

## Problem

We want to run an interactive Python agent inside `minimal run` that needs
bidirectional communication with the host process (LLM calls, tool calls,
HTTP requests, streaming events). The agent is a long-running process
that makes many round-trips — not a batch job.

## What We Tried

| Approach | Result |
|---|---|
| **stdin/stdout JSON-RPC** | ❌ `minimal run` buffers all stdout until process exit. Agent writes request → buffered, blocks reading stdin → deadlock. |
| **Unix socket in repo directory** | ❌ Overlay filesystem sync doesn't support special files. `OSError: [Errno 116] Stale file handle`. |
| **Unix socket via `patches`** | ❌ `patches.dir` creates a snapshot, not a live bind mount. Directory appears empty inside sandbox. |
| **TCP on `127.0.0.1`** | ❌ Sandbox has its own network namespace. `127.0.0.1` inside is not the host's loopback. |
| **TCP on host LAN IP** | ✅ Works! Sandbox outbound networking (via `pasta`/`passt`) can reach the host's real IP. |

## The Working Solution (Slow)

Host binds TCP server to `0.0.0.0`, discovers its LAN IP (e.g.,
`192.168.100.130`), passes it to the sandboxed task:

```bash
minimal run my-agent-task --host 192.168.100.130 --port 53499
```

Inside the sandbox, Python connects back:
```python
sock.connect(("192.168.100.130", 53499))
```

Full bidirectional JSON-RPC works. But...

## The Overhead

```bash
cd minimal-rpc-repro
bash repro.sh
```

Results (macOS, Apple Silicon, warm cache):

| Method | Time |
|---|---|
| Native `echo` | ~1ms |
| `uv run echo` | ~100ms |
| `minimal run echo` | **~5.5s** |

For an interactive agent that may spawn hundreds of times per session,
5.5s per invocation is prohibitive.

## Question for Minimal Devs

Is there a way to:
1. **Keep a sandbox warm/persistent** across multiple task invocations?
2. **Expose a host socket or pipe** to the sandbox that supports
   bidirectional streaming?
3. **Run a task in "interactive" mode** where stdout is streamed in real-time
   and stdin remains open for ongoing communication?

The `interactive = true` flag exists for TUI apps, but `minimal run` still
seems to capture all output until process exit. We're looking for the
equivalent of `docker run -it` or `podman run --tty` but with programmatic
access from a parent process (not a human terminal).
