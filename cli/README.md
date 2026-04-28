# cachepuppy-cli

TypeScript CLI for running CachePuppy locally with Docker Compose.

## Install

```bash
npm install
npm run build
npm link
```

After linking, use `cachepuppy` from any project directory.

## Commands

- `cachepuppy init [--image cachepuppy/cachepuppy:sha-xxxx] [--http-port 4000] [--no-pull]`
- `cachepuppy start [--timeout 90] [--skip-port-check]`
- `cachepuppy stop [--volumes] [--remove-orphans]`
- `cachepuppy reset [--yes] [--no-pull] [--no-start]`
- `cachepuppy update [--image cachepuppy/cachepuppy:sha-xxxx] [--no-restart]`
- `cachepuppy status`
- `cachepuppy logs [--service app] [--tail 100] [--since 10m]`

## Runtime files

The CLI writes local runtime state to:

- `.cachepuppy/config.json`
- `.cachepuppy/.env`
- `.cachepuppy/docker-compose.runtime.yml`

## Expected flow

```bash
cachepuppy init
cachepuppy start
cachepuppy status
cachepuppy logs
cachepuppy stop
```

Runtime uses a **single** Phoenix container plus a named volume for cache shards (lower RAM than a multi-node stack).

If you previously used an older CLI with nginx and three nodes, remove `.cachepuppy/docker-compose.runtime.yml` (and the `nginx` folder if present), then run `cachepuppy init --no-pull` to regenerate the compose file.

## Exit codes

- `0` success
- `1` generic failure
- `2` prerequisites missing
- `3` invalid or missing config
- `4` readiness timeout
- `5` user cancelled
