# QuickAsk

A tiny macOS menu bar helper for quick Gemini answers from anywhere.

## Run

```sh
export GEMINI_API_KEY='your-key'
swift run QuickAsk
```

Press `Option+Space` to open the prompt. Press `Enter` to ask, `Esc` to close, and `Copy` to copy the answer.

The app reads the API key in this order:

1. `GEMINI_API_KEY`
2. `~/.quickask.env` containing `GEMINI_API_KEY='your-key'`
3. `~/Gemini` containing only the raw key

Optional model override:

```sh
export QUICKASK_GEMINI_MODEL='gemini-2.5-flash'
```

The default model is `gemini-3.5-flash-lite` for low-latency quick answers. If your API key cannot access it yet, set `QUICKASK_GEMINI_MODEL='gemini-2.5-flash-lite'`.

Optional output limit override:

```sh
export QUICKASK_MAX_OUTPUT_TOKENS=300
```

Gemini 3 defaults to `QUICKASK_THINKING_LEVEL=minimal` so short answers are not truncated by hidden thinking tokens.

## Build an app bundle

For Finder launch, put your key in `~/Gemini`:

```sh
your-key
```

Then build:

```sh
chmod +x scripts/build-app.sh scripts/quickask-launcher.sh
scripts/build-app.sh
open .build/QuickAsk.app
```

## Start at login

Install a user LaunchAgent:

```sh
scripts/install-launch-agent.sh
```

Remove it:

```sh
scripts/uninstall-launch-agent.sh
```
