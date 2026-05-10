.PHONY: compose-up compose-clean-rebuild compose-single-up compose-single-down compose-single-clean-rebuild sdk-core-build sdk-react-build sdk-build demo-unified

compose-up:
	cd cachepuppy_core && docker compose up --build

compose-clean-rebuild:
	cd cachepuppy_core && docker compose down --volumes --remove-orphans --rmi local
	cd cachepuppy_core && docker compose build --no-cache
	cd cachepuppy_core && docker compose up

# Single-node stack (port 4000 → Phoenix directly). Prefer this for k6 / local debugging.
compose-single-up:
	cd cachepuppy_core && docker compose -f docker-compose.single.yml up --build

compose-single-down:
	cd cachepuppy_core && docker compose -f docker-compose.single.yml down

compose-single-clean-rebuild:
	cd cachepuppy_core && docker compose -f docker-compose.single.yml down --volumes --remove-orphans --rmi local
	cd cachepuppy_core && docker compose -f docker-compose.single.yml build --no-cache
	cd cachepuppy_core && docker compose -f docker-compose.single.yml up

sdk-core-build:
	cd sdk/javascript && npm run build

sdk-react-build:
	cd sdk/react && npm run build

sdk-build: sdk-core-build sdk-react-build

# Build both SDKs and run the unified Next.js demo (frontend + API routes in one app).
# `WORKFLOW_DEMO_PUBLIC_URL` defaults to host.docker.internal so Phoenix running
# in Docker Desktop (macOS/Windows) can reach the Next.js callback endpoints.
# Override on the CLI for other setups, e.g.
#   make demo-unified WORKFLOW_DEMO_PUBLIC_URL=http://192.168.1.10:3000
WORKFLOW_DEMO_PUBLIC_URL ?= http://host.docker.internal:3000
CACHEPUPPY_API_BASE      ?= http://127.0.0.1:4000
NEXT_PUBLIC_WS_URL       ?= ws://127.0.0.1:4000/socket/websocket

demo-unified: sdk-build
	cd example/javascript_demo/unified && npm install --no-audit --no-fund
	cd example/javascript_demo/unified && \
	  WORKFLOW_DEMO_PUBLIC_URL=$(WORKFLOW_DEMO_PUBLIC_URL) \
	  CACHEPUPPY_API_BASE=$(CACHEPUPPY_API_BASE) \
	  NEXT_PUBLIC_WS_URL=$(NEXT_PUBLIC_WS_URL) \
	  npm run dev
