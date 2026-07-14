#!/bin/bash

helm package charts/parseable -d helm-releases/
helm package charts/pai -d helm-releases/

helm repo index --merge index.yaml --url https://charts.parseable.com .
