#!/usr/bin/env bash
# Plan and apply one environment. Run by CI after merge to main; the plan is
# saved first so the log shows exactly what was applied.
#
# Usage: scripts/ci-apply.sh dev
set -euo pipefail

env=${1:?usage: ci-apply.sh <env>}
dir="$(git rev-parse --show-toplevel)/terraform/envs/$env"

terraform -chdir="$dir" init -input=false -no-color
terraform -chdir="$dir" plan -input=false -no-color -lock-timeout=120s -out=tf.plan
terraform -chdir="$dir" apply -input=false -no-color -lock-timeout=120s tf.plan
