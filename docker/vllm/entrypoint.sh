#!/bin/sh
# Container entrypoint: fetch the model to local disk, then serve it with vLLM.
#
# The two steps are deliberately decoupled (see fetch_model.sh): the weights are
# materialized locally first, and vLLM only ever serves a local path. Swapping
# the weight source never changes the serve command.
set -eu

: "${MODEL_SRC:=hf://Qwen/Qwen2.5-7B-Instruct}"
: "${MODEL_DIR:=/models}"
: "${VLLM_MAX_MODEL_LEN:=8192}"

fetch_model.sh "$MODEL_SRC" "$MODEL_DIR"

# basename of the source ref is the on-disk directory fetch_model.sh created.
MODEL_NAME="$(basename "${MODEL_SRC#hf://}")"

exec vllm serve "$MODEL_DIR/$MODEL_NAME" \
  --host 0.0.0.0 \
  --port 8000 \
  --served-model-name "$MODEL_NAME" \
  --max-model-len "$VLLM_MAX_MODEL_LEN"
