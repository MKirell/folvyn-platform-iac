ifeq ($(OS),Windows_NT)
SHELL := C:/PROGRA~1/Git/bin/bash.exe
else
SHELL := /bin/bash
endif
.SHELLFLAGS := -eu -o pipefail -c

ENV ?= dev
AWS_PROFILE ?= mkirell
REGION ?= eu-west-3

MAIN := terraform/main
PERSISTENT := terraform/persistent

VARS := -var-file=environments/$(ENV).tfvars
SHARED := -var-file=shared.tfvars

IMAGE_TAG = -var "app_image_tag=$$(aws lambda get-function-configuration \
	--function-name folvyn-portfolio-ms-$(ENV) --region $(REGION) \
	--query 'Environment.Variables.APP_IMAGE_TAG' --output text 2>/dev/null || echo '')"

export AWS_PROFILE
export MSYS_NO_PATHCONV := 1
export MSYS2_ARG_CONV_EXCL := *

.PHONY: help init init-main init-persistent plan plan-main plan-persistent plan-all \
        apply apply-main apply-persistent apply-all \
        destroy destroy-main destroy-persistent destroy-all \
        image-tag fmt validate output

help:
	@echo "Folvyn infrastructure. Every environment target takes ENV=dev or ENV=prod, default dev."
	@echo
	@echo "  make plan ENV=prod           what an apply would change"
	@echo "  make apply ENV=prod          apply it, pinned to the image already running"
	@echo "  make apply-all ENV=prod      the shared stack first, then the environment"
	@echo "  make destroy ENV=dev         take the billable half down"
	@echo "  make output ENV=prod         the environment's outputs"
	@echo
	@echo "  make plan-persistent         the shared stack: zone, Cognito, ECR, Atlas, CI config"
	@echo "  make apply-persistent        apply it"
	@echo
	@echo "  make fmt                     format every stack"
	@echo "  make validate                validate every stack"
	@echo "  make image-tag ENV=prod      the image tag the function is running"
	@echo
	@echo "destroy-persistent and destroy-all are guarded. They delete the Cognito pool with"
	@echo "every user, the Atlas cluster with the content, and every image. Read the README,"
	@echo "then pass CONFIRM=i-know-what-this-deletes."

image-tag:
	@aws lambda get-function-configuration --function-name folvyn-portfolio-ms-$(ENV) \
		--region $(REGION) --query 'Environment.Variables.APP_IMAGE_TAG' --output text

init-main:
	@cd $(MAIN) && terraform init -reconfigure \
		-backend-config=backends/bucket.hcl -backend-config=backends/$(ENV).hcl

init-persistent:
	@cd $(PERSISTENT) && terraform init -reconfigure -backend-config=backends/bucket.hcl

init: init-persistent init-main

plan-main: init-main
	@cd $(MAIN) && terraform plan $(VARS) $(IMAGE_TAG)

plan-persistent: init-persistent
	@cd $(PERSISTENT) && terraform plan $(SHARED)

plan: plan-main

plan-all: plan-persistent plan-main

apply-main: init-main
	@cd $(MAIN) && terraform apply $(VARS) $(IMAGE_TAG)

apply-persistent: init-persistent
	@cd $(PERSISTENT) && terraform apply $(SHARED)

apply: apply-main

apply-all: apply-persistent apply-main

destroy-main: init-main
	@cd $(MAIN) && terraform destroy $(VARS) $(IMAGE_TAG)

destroy: destroy-main

destroy-persistent:
ifneq ($(CONFIRM),i-know-what-this-deletes)
	@echo "Refusing. Destroying the shared stack deletes the Cognito pool with every user,"
	@echo "the Atlas cluster with the portfolio content, every image in ECR and the DNS zone."
	@echo "None of it is billable enough to be worth destroying."
	@echo
	@echo "  make destroy-persistent CONFIRM=i-know-what-this-deletes"
	@exit 1
else
	@$(MAKE) init-persistent
	@cd $(PERSISTENT) && terraform destroy $(SHARED)
endif

destroy-all:
ifneq ($(CONFIRM),i-know-what-this-deletes)
	@echo "Refusing. destroy-all takes the shared stack with it. See destroy-persistent."
	@echo
	@echo "  make destroy-all ENV=$(ENV) CONFIRM=i-know-what-this-deletes"
	@exit 1
else
	@$(MAKE) destroy-main ENV=$(ENV)
	@$(MAKE) destroy-persistent CONFIRM=$(CONFIRM)
endif

output: init-main
	@cd $(MAIN) && terraform output

fmt:
	@terraform fmt -recursive terraform

validate: init
	@cd $(PERSISTENT) && terraform validate
	@cd $(MAIN) && terraform validate
