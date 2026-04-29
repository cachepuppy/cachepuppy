.PHONY: compose-up compose-clean-rebuild compose-single-up compose-single-down compose-single-clean-rebuild sdk-core-build sdk-react-build sdk-build demo-interactive demo-backend

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

demo-interactive:
	cd example/javascript_demo/interactive && npm run dev

demo-backend:
	cd example/javascript_demo/webhook-server && npm start
