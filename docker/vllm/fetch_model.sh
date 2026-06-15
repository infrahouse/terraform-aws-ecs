#!/bin/sh
# fetch_model.sh <source-ref> <dest>
#
# Populates a local model directory from a configurable source so the serving
# layer always runs `vllm serve <local-path>` and never pulls from Hugging Face
# at serve time. The source of the weights (HF today; a mirror, P2P swarm, or
# Lustre later) can change without touching the serving command or image.
#
# Experiment 2 implements only FETCH_BACKEND=http with an hf:// source. The
# https://, p2p, and lustre paths are intentionally stubs so the interface
# (<source-ref>, <dest>, FETCH_BACKEND) stays stable for later specs.
set -eu

SRC="$1"
DEST="$2"
: "${FETCH_BACKEND:=http}"

case "$FETCH_BACKEND" in
  http)
    case "$SRC" in
      hf://*)
        REPO="${SRC#hf://}"
        # `hf` is the current Hugging Face CLI (huggingface-cli is deprecated and
        # no longer functional). Xet high-performance transfer replaces the old
        # hf_transfer backend; the hf_xet package is installed in the image.
        HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-1}" \
          hf download "$REPO" \
          --local-dir "$DEST/$(basename "$REPO")"
        ;;
      https://*|http://*)
        echo "https source deferred to Experiment 1" >&2
        exit 2
        ;;
      *)
        echo "unsupported source ref: $SRC" >&2
        exit 2
        ;;
    esac
    ;;
  p2p|lustre)
    echo "backend $FETCH_BACKEND deferred to fetch spec" >&2
    exit 2
    ;;
  *)
    echo "unknown FETCH_BACKEND: $FETCH_BACKEND" >&2
    exit 2
    ;;
esac
