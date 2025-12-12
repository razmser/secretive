# SecretAgent Development & Debugging Guide

This guide documents the workflow to build the SecretAgent binary, run high-concurrency signing stress tests, and inspect the instrumentation that logs Secure Enclave activity.

## 1. Build the Debug Agent

```bash
# From the repository root
xcodebuild \
  -project Sources/Secretive.xcodeproj \
  -scheme SecretAgent \
  -configuration Debug \
  build
```

Artifacts are emitted into Xcode’s derived data directory (look for the path near the end of the build). The debug executable lives at:

```
~/Library/Developer/Xcode/DerivedData/Secretive-*/Build/Products/Debug/SecretAgent.app
```

## 2. Launch the Debug Agent

1. Stop any running SecretAgent/Secretive processes to free the `socket-debug.ssh` endpoint:
   ```bash
   pgrep -fl SecretAgent | awk '{print $1}' | xargs kill
   ```
2. Start the freshly built agent and tee output to a file for quick inspection:
   ```bash
   ~/Library/Developer/Xcode/DerivedData/Secretive-*/Build/Products/Debug/SecretAgent.app/Contents/MacOS/SecretAgent \
     > /tmp/secretagent.log 2>&1 &
   ```

## 3. Inspect Structured Logs

The new instrumentation writes to the `com.razmser.secretive.secretagent` subsystem (categories such as `Agent`, `SecureEnclaveStore`, `SigningSerializer`).

- Live stream:
  ```bash
  log stream --style compact --level debug \
    --predicate 'subsystem == "com.razmser.secretive.secretagent"'
  ```
- Historical slice (example: previous five minutes):
  ```bash
  log show --style compact --last 5m \
    --predicate 'subsystem == "com.razmser.secretive.secretagent"'
  ```

Each SSH request now logs a UUID, start/end timestamps, and Secure Enclave actor timings to help correlate agent activity with client failures.

## 4. Run the CSR Stress Harness

Point `SSH_AUTH_SOCK` at the debug agent’s socket and run CSR with your preferred concurrency window:

```bash
export SSH_AUTH_SOCK="/Users/razmser/Library/Containers/com.razmser.Secretive.SecretAgent/Data/socket-debug.ssh"
./csr --parallel 50 --timeout 60
```

CSR opens 50 connections and hammers the agent for one minute. Failures appear both in CSR output and, thanks to the new logging, in the Secure Enclave traces.

## 5. Run the Python Signing Verifier

A simple verifier script (`/tmp/sign_verify.py`) repeatedly signs random payloads and validates each signature locally using `cryptography`:

```bash
SSH_AUTH_SOCK="/Users/razmser/Library/Containers/com.razmser.Secretive.SecretAgent/Data/socket-debug.ssh" \
  THREADS=50 ITER=100 python3 /tmp/sign_verify.py
```

Use this to confirm the agent behaves under controlled concurrency before blaming the client workload.

## 6. Use the Asyncio Proxy for Traffic Tracing

`proxy_agent.py` forwards requests to the real agent while printing every SSH message (with IDs and sign flags) so you can see whether the agent returns `SSH_AGENT_FAILURE` responses.

```bash
python3 proxy_agent.py > /tmp/proxy.log 2>&1 &
export SSH_AUTH_SOCK="/tmp/secretive-proxy-agent.sock"
./csr --parallel 50 --timeout 10
```

Inspect `/tmp/proxy.log` for message sequences (type 13 = sign request, type 14 = sign response, type 5 = agent failure).

## 7. Tips & Troubleshooting

- **Socket contention:** `lsof -U | rg socket-debug` shows which processes currently own the debug socket.
- **Menu warnings:** running the agent headless still emits AppKit menu warnings; they are noisy but harmless.
- **Log visibility:** if the new logs do not appear, raise the subsystem level with `log config --mode "level:info" --subsystem com.razmser.secretive.secretagent`.
- **DerivedData cleanup:** delete `~/Library/Developer/Xcode/DerivedData/Secretive-*` to force a clean rebuild if frameworks or resources become stale.

Following these steps lets you rebuild, observe, and stress-test the SecretAgent signing path end-to-end.
