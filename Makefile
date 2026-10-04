# make up        cluster + registry, traefik + metrics-server, dev/prod namespaces
# make release   import -> deploy dev -> (confirm) -> promote -> deploy prod
# make down      delete everything
#
# needs: docker, terraform >= 1.6, helm, kubectl, curl. (optional: trivy)

SHELL := /bin/bash
TF := infra/terraform
export KUBECONFIG ?= $(HOME)/.kube/hello-platform.kubeconfig
# the terraform docker provider only looks at /var/run/docker.sock.
# Docker Desktop on my mac put the socket elsewhere, so take it from the current docker context
export DOCKER_HOST ?= $(shell docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null)

.PHONY: up release validate rollback status down

up:
	@for d in cluster platform envs/dev envs/prod; do \
	  terraform -chdir=$(TF)/$$d init -input=false && \
	  terraform -chdir=$(TF)/$$d apply -input=false -auto-approve || exit 1; \
	done

release:
	scripts/import-image.sh
	scripts/deploy.sh dev
	@read -p "Promote to prod? [y/N] " ok && [[ $$ok == y ]]
	scripts/promote.sh dev prod
	scripts/deploy.sh prod

validate:
	@for e in dev prod; do \
	  helm lint deploy/helm/podinfo -f deploy/environments/$$e/values.yaml --set image.tag=lint || exit 1; \
	done
	terraform fmt -check -recursive $(TF)
	@for d in cluster platform envs/dev envs/prod; do \
	  terraform -chdir=$(TF)/$$d init -backend=false -input=false >/dev/null && \
	  terraform -chdir=$(TF)/$$d validate || exit 1; \
	done

# make rollback                  -> previous helm revision in prod
# make rollback DIGEST=sha256:.. -> only the image (already in the prod repo)
rollback:
	@if [[ -n "$(DIGEST)" ]]; then scripts/deploy.sh prod $(DIGEST); \
	else helm rollback podinfo -n podinfo-prod --wait; fi

status:
	kubectl get pods -A -l app.kubernetes.io/name=podinfo -o wide
	helm history podinfo -n podinfo-prod --max 5

# namespaces and add-ons live inside the cluster, so their state is useless after this
down:
	terraform -chdir=$(TF)/cluster destroy -input=false -auto-approve
	rm -f $(TF)/{platform,envs/dev,envs/prod}/terraform.tfstate*
