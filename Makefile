# =============================================================================
# CachePuppy — local dev shortcuts (run from repository root)
# =============================================================================
#   cp-*     Docker Compose stacks (Phoenix in cachepuppy_core/)
#   cp-demo  Next.js unified example + linked SDKs
#   sdk-*    Build @cachepuppy/core and @cachepuppy/react only
# =============================================================================

.PHONY: cp-up cp-up-rebuild cp-single-up cp-single-down cp-single-rebuild \
	sdk-core-build sdk-react-build sdk-build cp-demo

# -----------------------------------------------------------------------------
# cp-up — multi-node cluster (3 × Phoenix + nginx on host port 4000)
# -----------------------------------------------------------------------------

cp-up:
	cd cachepuppy_core && docker compose up --build

# Full reset: drop volumes, rebuild images from scratch, start cluster.
cp-up-rebuild:
	cd cachepuppy_core && docker compose down --volumes --remove-orphans --rmi local
	cd cachepuppy_core && docker compose build --no-cache
	cd cachepuppy_core && docker compose up

# -----------------------------------------------------------------------------
# cp-single-* — one Phoenix container on port 4000 (k6 / simpler debugging)
# -----------------------------------------------------------------------------

cp-single-up:
	cd cachepuppy_core && docker compose -f docker-compose.single.yml up --build

cp-single-down:
	cd cachepuppy_core && docker compose -f docker-compose.single.yml down

cp-single-rebuild:
	cd cachepuppy_core && docker compose -f docker-compose.single.yml down --volumes --remove-orphans --rmi local
	cd cachepuppy_core && docker compose -f docker-compose.single.yml build --no-cache
	cd cachepuppy_core && docker compose -f docker-compose.single.yml up

# -----------------------------------------------------------------------------
# sdk-* — workspace packages (used by cp-demo)
# -----------------------------------------------------------------------------

sdk-core-build:
	cd sdk/javascript && npm run build

sdk-react-build:
	cd sdk/react && npm run build

sdk-build: sdk-core-build sdk-react-build

# -----------------------------------------------------------------------------
# cp-demo — unified Next.js example (http://localhost:3000)
# -----------------------------------------------------------------------------
# Defaults WORKFLOW_DEMO_PUBLIC_URL for Docker Desktop so in-container Phoenix
# can POST back to Next.js. Override when needed, e.g.:
#   make cp-demo WORKFLOW_DEMO_PUBLIC_URL=http://192.168.1.10:3000
# -----------------------------------------------------------------------------

WORKFLOW_DEMO_PUBLIC_URL ?= http://host.docker.internal:3000
CACHEPUPPY_API_BASE      ?= http://127.0.0.1:4000
NEXT_PUBLIC_WS_URL       ?= ws://127.0.0.1:4000/socket/websocket

cp-demo: sdk-build
	cd example/javascript_demo/unified && npm install --no-audit --no-fund
	cd example/javascript_demo/unified && \
	  WORKFLOW_DEMO_PUBLIC_URL=$(WORKFLOW_DEMO_PUBLIC_URL) \
	  CACHEPUPPY_API_BASE=$(CACHEPUPPY_API_BASE) \
	  NEXT_PUBLIC_WS_URL=$(NEXT_PUBLIC_WS_URL) \
	  npm run dev
