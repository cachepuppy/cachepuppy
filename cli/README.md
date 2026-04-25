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
- `cachepuppy logs [--service app1] [--tail 100] [--since 10m]`

## Runtime files

The CLI writes local runtime state to:

- `.cachepuppy/config.json`
- `.cachepuppy/.env`
- `.cachepuppy/docker-compose.runtime.yml`
- `.cachepuppy/nginx/nginx.conf`

## Expected flow

```bash
cachepuppy init
cachepuppy start
cachepuppy status
cachepuppy logs
cachepuppy stop
```

## Exit codes

- `0` success
- `1` generic failure
- `2` prerequisites missing
- `3` invalid or missing config
- `4` readiness timeout
- `5` user cancelled
