# minimal-rpc-repro

We're building interactive Python agents that need to talk back to the host process while running inside `minimal run` — think LLM calls, tool calls, HTTP requests, streaming events. It's a conversation, not a batch job, and we're hitting some friction.

We've been poking at this from a few angles. Here's what we found, in case it's useful context for the team.

## Where we got stuck

**stdio JSON-RPC**: `minimal run` buffers stdout until the process exits. Our agent writes a request and waits on stdin for the response, which deadlocks — the host never sees the request because it's still in the buffer. We might be pushing `run` past what it's designed for here.

**Unix sockets in the repo directory**: The overlay filesystem handles regular files great, but special files don't seem to tunnel through. We hit `OSError: [Errno 116] Stale file handle` — the socket file shows up at the right path but with no kernel endpoint behind it.

**Unix sockets via `patches`**: `patches.dir` looks like a snapshot at sandbox setup time rather than a live bind mount. The directory exists inside the sandbox but reads as empty.

**TCP on `127.0.0.1`**: The sandbox has its own network namespace, so `127.0.0.1` inside the container isn't the host's loopback. Fair enough — that's standard container behavior.

## What works (for now)

TCP on the host's actual LAN IP. The sandbox outbound networking (via `pasta`/`passt`) can reach the host's real IP address just fine.

Host binds to `0.0.0.0`, discovers its LAN IP, passes it in as an arg:

```bash
minimal run my-agent-task --host 192.168.100.130 --port 53499
```

Python inside connects back:

```python
sock.connect(("192.168.100.130", 53499))
```

Full bidirectional JSON-RPC over TCP works great. The startup time adds up, though.

## The startup cost

```bash
bash repro.sh
```

On macOS (Apple Silicon, warm cache):

- Native `echo`: ~1ms
- `uv run echo`: ~100ms
- `minimal run echo`: **~5.5s**

For an agent that might spawn a few times per user message, that 5 seconds starts to sting. We suspect this is just the cost of spinning up a fresh sandbox each time, which makes total sense for build tasks — it's just a lot for a conversational loop.

## What we're hoping for

Any of these would be a huge win for our use case:

1. **Warm or persistent sandboxes**: Keep a sandbox alive across task invocations instead of cold-starting every time. Maybe a `minimal run --reuse` or a persistent shell session model?

2. **A real host socket or pipe** inside the sandbox: Something we can read from and write to in real time. We know this is tricky with overlay filesystems — just flagging it as something that would unlock a lot of interactive patterns.

3. **Streaming stdio for `run`**: `interactive = true` seems oriented toward TUI apps. We'd love a mode where stdout streams live and stdin stays open for ongoing back-and-forth, driven programmatically from a parent process rather than a human terminal. Basically `docker run -it` but for code.

We're huge fans of minimal and this isn't a complaint — just sharing where we hit the wall in case it's helpful for future roadmapping. Happy to test anything you want to throw at us.
