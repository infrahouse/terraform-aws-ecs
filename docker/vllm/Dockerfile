# vLLM OpenAI server with the fetch-then-serve wrapper baked in.
#
# The image keeps the production rule from the Experiment 2 spec: the serving
# container fetches the model to local disk via fetch_model.sh, then runs
# `vllm serve <local-path>` — it never pulls from Hugging Face at serve time.
#
# linux/amd64 only (vLLM publishes amd64 GPU images). Build with:
#   docker build --platform linux/amd64 -t <ecr-uri> docker/vllm
FROM vllm/vllm-openai:latest

# hf_xet enables Xet high-performance Hugging Face downloads (fetch_model.sh sets
# HF_XET_HIGH_PERFORMANCE=1). Also ensures the current `hf` CLI is present.
RUN pip install --no-cache-dir -U "huggingface_hub[hf_xet]"

COPY fetch_model.sh /usr/local/bin/fetch_model.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/fetch_model.sh /usr/local/bin/entrypoint.sh

# Replace vLLM's default entrypoint with the fetch-then-serve wrapper.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
