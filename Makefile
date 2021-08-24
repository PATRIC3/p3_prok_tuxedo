TOP_DIR = ../..
include $(TOP_DIR)/tools/Makefile.common

ABS_BIN_DIR = $(realpath $(BIN_DIR))

DEPLOY_RUNTIME ?= /kb/runtime
TARGET ?= /kb/deployment

APP_SERVICE = app_service

SRC_PERL = $(wildcard scripts/*.pl)
BIN_PERL = $(addprefix $(BIN_DIR)/,$(basename $(notdir $(SRC_PERL))))
DEPLOY_PERL = $(addprefix $(TARGET)/bin/,$(basename $(notdir $(SRC_PERL))))

SRC_SERVICE_PERL = $(wildcard service-scripts/*.pl)
BIN_SERVICE_PERL = $(addprefix $(BIN_DIR)/,$(basename $(notdir $(SRC_SERVICE_PERL))))
DEPLOY_SERVICE_PERL = $(addprefix $(SERVICE_DIR)/bin/,$(basename $(notdir $(SRC_SERVICE_PERL))))

CLIENT_TESTS = $(wildcard t/client-tests/*.t)
SERVER_TESTS = $(wildcard t/server-tests/*.t)
PROD_TESTS = $(wildcard t/prod-tests/*.t)

STARMAN_WORKERS = 8
STARMAN_MAX_REQUESTS = 100

TPAGE_ARGS = --define kb_top=$(TARGET) --define kb_runtime=$(DEPLOY_RUNTIME) --define kb_service_name=$(SERVICE) \
	--define kb_service_port=$(SERVICE_PORT) --define kb_service_dir=$(SERVICE_DIR) \
	--define kb_sphinx_port=$(SPHINX_PORT) --define kb_sphinx_host=$(SPHINX_HOST) \
	--define kb_starman_workers=$(STARMAN_WORKERS) \
	--define kb_starman_max_requests=$(STARMAN_MAX_REQUESTS)

DEPLOY_VENV = $(TARGET)/libexec/$(CURRENT_DIR)

VENV = prok_tuxedo_venv
VENV_PATH = $(realpath $(VENV))
PROK_TUXEDO_SRC = https://github.com/cucinellclark/Prok-tuxedo

BUILD_MULTIQC = $(shell $(VENV_PATH)/bin/python3 -c 'import multiqc; import os.path; print(os.path.dirname(multiqc.__file__))')
DEPLOY_MULTIQC = $(shell $(DEPLOY_VENV)/bin/python3 -c 'import multiqc; import os.path; print(os.path.dirname(multiqc.__file__))')

all: bin build-local-venv

build-local-venv: local-venv local-multiqc local-prok-tuxedo

local-venv: $(VENV)/bin/pip3
local-multiqc: $(VENV)/bin/multiqc
local-prok-tuxedo: $(ABS_BIN_DIR)/prok_tuxedo.py

$(VENV)/bin/pip3:
	python3 -mvenv $(VENV)

$(VENV)/bin/multiqc: 
	$(VENV)/bin/pip install multiqc

$(ABS_BIN_DIR)/prok_tuxedo.py:
	rm -rf Prok-tuxedo
	git clone $(PROK_TUXEDO_SRC) Prok-tuxedo
	for py in Prok-tuxedo/src/*.py ; do \
		f=`basename $$py`; \
		(echo "#!$(VENV_PATH)/bin/python3"; cat $$py) > $(ABS_BIN_DIR)/$$f; \
		chmod +x $(ABS_BIN_DIR)/$$f; \
	done;
	echo "Deploy multiqc files to $(BUILD_MULTIQC)";
	for mod_dir in Prok-tuxedo/lib/Multiqc/modules/* ; do \
		mod_name=`basename $$mod_dir`; \
		mkdir -p $(BUILD_MULTIQC)/modules/$$mod_name; \
		cp -r $$mod_dir/* $(BUILD_MULTIQC)/modules/$$mod_name; \
	done; 
	cp Prok-tuxedo/lib/Multiqc/BV_BRC.png $(BUILD_MULTIQC)
	multiqc_version=`$(VENV_PATH)/bin/python3 -c 'import multiqc; print(multiqc.__version__.split()[0])'`; \
	echo "version=$$multiqc_version"; \
	cp Prok-tuxedo/lib/Multiqc/entry_points.txt $(BUILD_MULTIQC)-$${multiqc_version}.dist-info/
	cp Prok-tuxedo/lib/Multiqc/utils/search_patterns.yaml $(BUILD_MULTIQC)/utils/

SRC_R = $(wildcard Prok-tuxedo/src/*.R)
BIN_R = $(addprefix $(BIN_DIR)/,$(basename $(notdir $(SRC_R))))
DEPLOY_R = $(addprefix $(TARGET)/bin/,$(basename $(notdir $(SRC_R))))

deploy-local-venv: deploy-venv deploy-multiqc deploy-prok-tuxedo
deploy-venv: $(DEPLOY_VENV)/bin/pip3
deploy-multiqc: $(DEPLOY_VENV)/bin/multiqc
deploy-prok-tuxedo: $(TARGET)/bin/prok_tuxedo.py

$(DEPLOY_VENV)/bin/pip3:
	python3 -mvenv $(DEPLOY_VENV)

$(DEPLOY_VENV)/bin/multiqc: 
	$(DEPLOY_VENV)/bin/pip install multiqc

$(TARGET)/bin/prok_tuxedo.py:
	rm -rf Prok-tuxedo
	git clone $(PROK_TUXEDO_SRC) Prok-tuxedo
	for py in Prok-tuxedo/src/*.py ; do \
		f=`basename $$py`; \
		(echo "#!$(DEPLOY_VENV)/bin/python3"; cat $$py) > $(TARGET)/bin/$$f; \
		chmod +x $(TARGET)/bin/$$f; \
	done;
	echo "Deploy multiqc files to $(DEPLOY_MULTIQC)"
	for mod_dir in Prok-tuxedo/lib/Multiqc/modules/* ; do \
		mod_name=`basename $$mod_dir`; \
		mkdir -p $(DEPLOY_MULTIQC)/modules/$$mod_name; \
		cp $$mod_dir/* $(DEPLOY_MULTIQC)/modules/$$mod_name; \
	done;
	cp Prok-tuxedo/lib/Multiqc/BV_BRC.png $(DEPLOY_MULTIQC)
	multiqc_version=$(shell $(DEPLOY_VENV)/bin/python3 -c 'import multiqc; print(multiqc.__version__.split()[0])'); \
	echo "version=$$multiqc_version"; \
	cp Prok-tuxedo/lib/Multiqc/entry_points.txt $(DEPLOY_MULTIQC)-$${multiqc_version}.dist-info/ 
	cp Prok-tuxedo/lib/Multiqc/utils/search_patterns.yaml $(DEPLOY_MULTIQC)/utils/

bin: $(BIN_PERL) $(BIN_SERVICE_PERL) $(BIN_R)

deploy: deploy-all 
deploy-all: deploy-client 
deploy-client: deploy-libs deploy-scripts deploy-docs deploy-local-venv

deploy-service: deploy-libs deploy-scripts deploy-service-scripts deploy-specs

deploy-specs:
	mkdir -p $(TARGET)/services/$(APP_SERVICE)
	rsync -arv app_specs $(TARGET)/services/$(APP_SERVICE)/.

deploy-service-scripts:
	export KB_TOP=$(TARGET); \
	export KB_RUNTIME=$(DEPLOY_RUNTIME); \
	export KB_PERL_PATH=$(TARGET)/lib ; \
	for src in $(SRC_SERVICE_PERL) ; do \
	        basefile=`basename $$src`; \
	        base=`basename $$src .pl`; \
	        echo install $$src $$base ; \
	        cp $$src $(TARGET)/plbin ; \
	        $(WRAP_PERL_SCRIPT) "$(TARGET)/plbin/$$basefile" $(TARGET)/bin/$$base ; \
	done


deploy-dir:
	if [ ! -d $(SERVICE_DIR) ] ; then mkdir $(SERVICE_DIR) ; fi
	if [ ! -d $(SERVICE_DIR)/bin ] ; then mkdir $(SERVICE_DIR)/bin ; fi

deploy-docs: 


clean:


$(BIN_DIR)/%: service-scripts/%.pl $(TOP_DIR)/user-env.sh
	$(WRAP_PERL_SCRIPT) '$$KB_TOP/modules/$(CURRENT_DIR)/$<' $@

$(BIN_DIR)/%: service-scripts/%.py $(TOP_DIR)/user-env.sh
	$(WRAP_PYTHON_SCRIPT) '$$KB_TOP/modules/$(CURRENT_DIR)/$<' $@

include $(TOP_DIR)/tools/Makefile.common.rules
