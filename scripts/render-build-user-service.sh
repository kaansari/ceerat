#!/usr/bin/env bash
set -euo pipefail

git submodule update --init --recursive

go work sync
go mod download

go build -o bin/ceerat-user-service ./services-repo/services/ceerat-user-service