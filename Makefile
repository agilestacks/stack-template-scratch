.DEFAULT_GOAL := deploy

export NAME        ?= scratch
export DOMAIN_NAME ?= dev.cloud-account-name.superhub.io

STATE_BUCKET ?= agilestacks.cloud-account-name.superhub.io
STATE_REGION ?= us-east-2

STACK_NAME ?= overlay

ELABORATE_FILE_FS := hub.yaml.elaborate
ELABORATE_FILE_S3 := s3://$(STATE_BUCKET)/$(DOMAIN_NAME)/hub/$(STACK_NAME)-$(NAME)/hub.elaborate
ELABORATE_FILES   := $(ELABORATE_FILE_FS),$(ELABORATE_FILE_S3)
STATE_FILE_FS     := hub.yaml.state
STATE_FILE_S3     := s3://$(STATE_BUCKET)/$(DOMAIN_NAME)/hub/$(STACK_NAME)-$(NAME)/hub.state
STATE_FILES       := $(STATE_FILE_FS),$(STATE_FILE_S3)

TEMPLATE_PARAMS ?= params/template.yaml
STACK_PARAMS    ?= params/$(DOMAIN_NAME).yaml

PLATFORM_PROVIDES    ?= tiller
PLATFORM_STATE_FILES ?=

COMPONENT :=
VERB :=

RESTORE_BUNDLE_FILE ?= restore-bundles/$(DOMAIN_NAME).yaml
RESTORE_PARAMS_FILE ?= restore-params.yaml

HUB_OPTS ?=

hub ?= hub -d --aws_region $(STATE_REGION)
aws ?= aws --region $(STATE_REGION)

ifdef HUB_API
ifdef HUB_TOKEN
ifdef HUB_ENVIRONMENT
ifdef HUB_STACK_INSTANCE
HUB_LIFECYCLE_OPTS ?= --hub-environment "$(HUB_ENVIRONMENT)" --hub-stack-instance "$(HUB_STACK_INSTANCE)"
endif
endif
endif
endif

.PHONY: $(RESTORE_BUNDLE_FILE)

$(RESTORE_PARAMS_FILE): $(RESTORE_BUNDLE_FILE)
	@echo --- > $(RESTORE_PARAMS_FILE)
	@if test -f $(RESTORE_BUNDLE_FILE); then \
		$(hub) backup unbundle $(RESTORE_BUNDLE_FILE) -o $(RESTORE_PARAMS_FILE); \
	fi

$(ELABORATE_FILE_FS): hub.yaml cloud.yaml $(TEMPLATE_PARAMS) $(STACK_PARAMS) $(RESTORE_PARAMS_FILE) params/user.yaml
	$(hub) elaborate \
		hub.yaml cloud.yaml $(TEMPLATE_PARAMS) $(STACK_PARAMS) $(RESTORE_PARAMS_FILE) params/user.yaml \
		-p $(PLATFORM_PROVIDES) \
		$(if $(PLATFORM_STATE_FILES),-s $(PLATFORM_STATE_FILES),) \
		$(HUB_OPTS) \
		-o $(ELABORATE_FILES)

elaborate:
	-rm -f $(ELABORATE_FILE_FS)
	$(MAKE) $(ELABORATE_FILE_FS)
.PHONY: elaborate

pull:
	$(hub) pull hub.yaml
.PHONY: pull

explain:
	$(hub) explain $(ELABORATE_FILES) $(STATE_FILES) $(HUB_OPTS) --color -r | less -R
.PHONY: explain

ifneq ($(PLATFORM_STATE_FILES),)
kubeconfig:
	$(hub) kubeconfig --switch-kube-context $(HUB_OPTS) $(PLATFORM_STATE_FILES)
.PHONY: kubeconfig
endif

COMPONENT_LIST := $(if $(COMPONENT),-c $(COMPONENT),)

deploy: $(ELABORATE_FILE_FS)
	$(hub) deploy $(ELABORATE_FILES) -s $(STATE_FILES) $(HUB_LIFECYCLE_OPTS) $(HUB_OPTS) \
		$(COMPONENT_LIST)
.PHONY: deploy

undeploy: $(ELABORATE_FILE_FS)
	$(hub) --force undeploy $(ELABORATE_FILES) -s $(STATE_FILES) $(HUB_LIFECYCLE_OPTS) $(HUB_OPTS) \
		$(COMPONENT_LIST)
.PHONY: undeploy

ifneq ($(COMPONENT),)
invoke: $(ELABORATE_FILE_FS)
	$(eval , := ,)
	$(eval WORDS := $(subst $(,), ,$(COMPONENT)))
	@$(foreach c,$(WORDS), \
		$(hub) invoke $(c) $(VERB) -m $(ELABORATE_FILES) -s $(STATE_FILES) $(HUB_OPTS);)
.PHONY: invoke
endif

backup: $(ELABORATE_FILE_FS)
	$(hub) backup create --json $(ELABORATE_FILES) -s $(STATE_FILES) -o "$(BACKUP_BUNDLE_FILE)" -c "$(COMPONENTS)"
	@$(if $(BACKUP_BUNDLE_FILE),echo "--- backup bundle"; cat $(BACKUP_BUNDLE_FILE); echo,)
.PHONY: backup

remove_s3_state:
	-$(aws) s3 rm $(STATE_FILE_S3)
.PHONY: remove_s3_state

clean: remove_s3_state
	@rm -f hub.yaml.state hub.yaml.elaborate
.PHONY: clean

toolbox:
	$(SHELL) bin/toolbox
.PHONY: toolbox
