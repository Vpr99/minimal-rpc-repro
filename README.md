# minimal-rpc-repro

We're trying to run an interactive Python agent inside `minimal run`. The agent needs to talk back to the host process — LLM calls, tool calls, HTTP requests, streaming events. It's a conversation, not a batch job.

`minimal run` doesn't seem built for this. Here's what we found.

## What breaks

**stdio JSON-RPC**: `minimal run` buffers all stdout until the process exits. Our agent writes a request to stdout, waits on stdin for the response, and deadlocks forever. The host only sees the buffered output once the agent times out or crashes.

**Unix sockets in the repo**: The overlay filesystem syncs regular files fine, but special files don't make it through. We get `OSError: [Errno 116] Stale file handle`. The socket file is a ghost — same path, no kernel endpoint.

**Unix sockets via `patches`**: `patches.dir` gives the sandbox a snapshot of the directory at setup time, not a live bind mount. The directory shows up empty inside.

**TCP on `127.0.0.1`**: The sandbox has its own network namespace. `127.0.0.1` inside the container is not the host's loopback.

## What works (sort of)

TCP on the host's actual LAN IP. The sandbox outbound networking (via `pasta`/`passt`) can reach the host's real IP address.

Host binds to `0.0.0.0`, discovers its LAN IP, passes it in:

```bash
minimal run my-agent-task --host 192.168.100.130 --port 53499
```

Python inside the sandbox connects back:

```python
sock.connect(("192.168.100.130", 53499))
```

Full bidirectional JSON-RPC works. But the startup cost is brutal.

## The overhead

```bash
bash repro.sh
```

On macOS (Apple Silicon, warm cache):

- Native `echo`: 1ms
- `uv run echo`: 100ms
- `minimal run echo`: **5.5 seconds**

For an agent that might spawn dozens of times per conversation, 5 seconds per invocation makes the whole thing unusable.

## What we'd love

Three things, any one of which would solve this:

1. **A warm/persistent sandbox** — keep the container alive across task invocations instead of spinning up a new one every time.

2. **A real host socket or pipe** inside the sandbox — something we can read from and write to in real time, not a snapshot.

3. **True interactive mode for `minimal run`** — stdout streams live, stdin stays open, a parent process can drive it programmatically. `interactive = true` seems to mean "this is a TUI app," not "keep stdio open for bidirectional use."

We're basically looking for `docker run -it` or `podman run --tty`, but driven by code instead of a human at a keyboard.
