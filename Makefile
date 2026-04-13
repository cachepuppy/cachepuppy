.PHONY: compose-up sdk-build demo-interactive demo-backend

compose-up:
	cd cachepuppy_core && docker compose up --build

sdk-build:
	cd sdk/javascript && npm run build

demo-interactive:
	cd example/javascript_demo/interactive && npm run dev

demo-backend:
	cd example/javascript_demo/webhook-server && npm start
