KIND_CLUSTER ?= courier-dev
IMAGE_NAME ?= ghcr.io/vucongthanh92/courier-user-svc
IMAGE_TAG ?= dev
USER_SERVICE_DIR ?= ../courier-user-svc
CHAT_SERVICE_DIR ?= ../courier-chat-svc
AGENT_GATEWAY_DIR ?= ../courier-agent-gateway
PAYMENT_GATEWAY_DIR ?= ../courier-payment-gateway
CONVERSA_APP_DIR ?= ../courier-conversa-app
FLIKK_APP_DIR ?= ../courier-flikk-app

# config list services to run in local development mode
COURIER_GO_SERVICES ?= user-service chat-service agent-gateway payment-gateway
# COURIER_GO_SERVICES ?= user-service

COURIER_FRONTEND_APPS ?= conversa-app flikk-app
COURIER_RUNTIME_DIR ?= .courier
COURIER_PID_FILE ?= $(COURIER_RUNTIME_DIR)/pids

.PHONY: kind-create kind-delete kind-load-user-service kind-apply-argocd kind-apply-user-service dev-user-up kafka-up kafka-init kafka-topics run-user-service run-chat-service run-agent-gateway run-payment-gateway run-conversa-app run-flikk-app start-courier stop-courier start-argocd start-postgres

kind-create:
	kind create cluster --name $(KIND_CLUSTER) --config infra/kind/courier-dev.yaml

kind-delete:
	kind delete cluster --name $(KIND_CLUSTER)

kind-load-user-service:
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) $(USER_SERVICE_DIR)
	kind load docker-image $(IMAGE_NAME):$(IMAGE_TAG) --name $(KIND_CLUSTER)

kind-apply-argocd:
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

kind-apply-user-service:
	kubectl create namespace courier-dev --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -f argocd/applications/user-service-dev.yaml

dev-user-up: kind-load-user-service kind-apply-argocd kind-apply-user-service

kafka-up:
	docker compose -f event-bus/kafka/docker-compose.yaml up -d

kafka-init:
	docker compose -f event-bus/kafka/docker-compose.yaml up kafka-init

kafka-topics:
	docker exec courier-kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list

run-user-service:
	$(MAKE) -C $(USER_SERVICE_DIR) run-local

run-chat-service:
	$(MAKE) -C $(CHAT_SERVICE_DIR) run-local

run-agent-gateway:
	$(MAKE) -C $(AGENT_GATEWAY_DIR) run-local

run-payment-gateway:
	$(MAKE) -C $(PAYMENT_GATEWAY_DIR) run-local

run-conversa-app:
	pnpm --dir $(CONVERSA_APP_DIR) dev

run-flikk-app:
	pnpm --dir $(FLIKK_APP_DIR) dev

start-courier:
	@echo "Starting Courier local apps..."
	@set -e; \
	mkdir -p $(COURIER_RUNTIME_DIR); \
	: > $(COURIER_PID_FILE); \
	pids=""; \
	stop_process_tree() { \
		pid="$$1"; \
		children=$$(pgrep -P "$$pid" 2>/dev/null || true); \
		for child in $$children; do stop_process_tree "$$child"; done; \
		kill "$$pid" 2>/dev/null || true; \
	}; \
	cleanup() { \
		echo "Stopping Courier local apps..."; \
		for pid in $$pids; do stop_process_tree "$$pid"; done; \
		wait 2>/dev/null || true; \
		rm -f $(COURIER_PID_FILE); \
	}; \
	trap cleanup INT TERM EXIT; \
	for service in $(COURIER_GO_SERVICES); do \
		echo "-> starting $$service"; \
		service_dir="$$service"; \
		if [ "$$service" = "user-service" ]; then service_dir="$(USER_SERVICE_DIR)"; fi; \
		if [ "$$service" = "chat-service" ]; then service_dir="$(CHAT_SERVICE_DIR)"; fi; \
		if [ "$$service" = "agent-gateway" ]; then service_dir="$(AGENT_GATEWAY_DIR)"; fi; \
		if [ "$$service" = "payment-gateway" ]; then service_dir="$(PAYMENT_GATEWAY_DIR)"; fi; \
		($(MAKE) -C $$service_dir run-local) & \
		pids="$$pids $$!"; \
		echo "$$!" >> $(COURIER_PID_FILE); \
	done; \
	for app in $(COURIER_FRONTEND_APPS); do \
		echo "-> starting $$app"; \
		app_dir="$$app"; \
		if [ "$$app" = "conversa-app" ]; then app_dir="$(CONVERSA_APP_DIR)"; fi; \
		if [ "$$app" = "flikk-app" ]; then app_dir="$(FLIKK_APP_DIR)"; fi; \
		(pnpm --dir $$app_dir dev) & \
		pids="$$pids $$!"; \
		echo "$$!" >> $(COURIER_PID_FILE); \
	done; \
	wait

stop-courier:
	@if [ ! -f $(COURIER_PID_FILE) ]; then \
		echo "Courier local apps are not running."; \
		exit 0; \
	fi; \
	echo "Stopping Courier local apps..."; \
	stop_process_tree() { \
		pid="$$1"; \
		children=$$(pgrep -P "$$pid" 2>/dev/null || true); \
		for child in $$children; do stop_process_tree "$$child"; done; \
		kill "$$pid" 2>/dev/null || true; \
	}; \
	while read -r pid; do \
		if [ -n "$$pid" ]; then stop_process_tree "$$pid"; fi; \
	done < $(COURIER_PID_FILE); \
	rm -f $(COURIER_PID_FILE); \
	echo "Courier local apps stopped."

start-argocd:
	./scripts/open-argocd-dashboard.sh

start-postgres:
	./scripts/open-postgres-tunnel.sh
