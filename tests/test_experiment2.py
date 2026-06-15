import base64
import json
import subprocess
import time
from os import path as osp
from textwrap import dedent
from typing import Callable

import pytest
import requests
from boto3 import Session
from infrahouse_core.aws.ec2_instance import EC2Instance
from requests.exceptions import RequestException
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
    update_terraform_tf,
    cleanup_dot_terraform,
)

# Must match var.model_src basename in test_data/experiment2 and the
# --served-model-name the container passes to vLLM.
MODEL_NAME = "Qwen2.5-7B-Instruct"
MODEL_DIR_ON_HOST = "/var/models"

# Ungated Apache-2.0 7B instruct model; ~15 GB in bf16, fits one A10G.
PROMPT = "In one sentence, what is the capital of France?"


def _wait_for_vllm_health(hostname: str, timeout_s: int = 1500) -> None:
    """
    Poll the vLLM ``/health`` endpoint through the ALB until it returns 200.

    vLLM only serves ``/health`` 200 once the model has been fetched and loaded,
    which on a fresh GPU node (download ~15 GB + load) takes several minutes.

    :param hostname: ALB hostname serving the model.
    :param timeout_s: Maximum seconds to wait for the model to come up.
    :raises AssertionError: If the endpoint is not healthy within the timeout.
    """
    url = f"https://{hostname}/health"
    deadline = time.time() + timeout_s
    last = "no response"
    LOG.info("Waiting for vLLM to load and serve at %s (timeout %ds)", url, timeout_s)
    while time.time() < deadline:
        try:
            response = requests.get(url, timeout=10)
            if response.status_code == 200:
                LOG.info("vLLM /health is 200; model is loaded and serving")
                return
            last = f"status {response.status_code}"
        except RequestException as err:
            last = type(err).__name__
        remaining = int(deadline - time.time())
        LOG.info("vLLM not ready yet (%s); %ds remaining", last, remaining)
        time.sleep(15)
    raise AssertionError(
        f"vLLM did not become healthy at {url} within {timeout_s}s (last: {last})"
    )


@pytest.fixture(scope="module")
def vllm_image(
    boto3_session: Session,
    aws_region: str,
    keep_after: bool,
) -> str:
    """
    Build the vLLM + fetch_model.sh image and push it to a throwaway ECR repo.

    The image bakes in fetch_model.sh and the fetch-then-serve entrypoint
    (docker/vllm). Built for linux/amd64 because vLLM only publishes amd64 GPU
    images; on an arm64 host this uses emulation. The repo (and image) are
    deleted on teardown unless ``--keep-after`` is set.

    :param boto3_session: Boto3 session for AWS API calls.
    :param aws_region: AWS region to host the ECR repo in.
    :param keep_after: If True, keep the ECR repo/image after the test.
    :return: The pushed image URI (``<registry>/<repo>:experiment2``).
    """
    ecr = boto3_session.client("ecr", region_name=aws_region)
    account_id = boto3_session.client(
        "sts", region_name=aws_region
    ).get_caller_identity()["Account"]
    repo_name = "terraform-aws-ecs-test-vllm"
    registry = f"{account_id}.dkr.ecr.{aws_region}.amazonaws.com"
    image_uri = f"{registry}/{repo_name}:experiment2"

    try:
        ecr.create_repository(repositoryName=repo_name)
    except ecr.exceptions.RepositoryAlreadyExistsException:
        pass

    auth = ecr.get_authorization_token()["authorizationData"][0]
    username, password = (
        base64.b64decode(auth["authorizationToken"]).decode().split(":", 1)
    )
    context = osp.join(osp.dirname(__file__), "..", "docker", "vllm")

    LOG.info("Logging in to ECR registry %s", registry)
    subprocess.run(
        ["docker", "login", "--username", username, "--password-stdin", registry],
        input=password.encode(),
        check=True,
    )
    LOG.info("Building vLLM image %s (linux/amd64)", image_uri)
    subprocess.run(
        ["docker", "build", "--platform", "linux/amd64", "-t", image_uri, context],
        check=True,
    )
    LOG.info("Pushing vLLM image %s", image_uri)
    subprocess.run(["docker", "push", image_uri], check=True)

    yield image_uri

    if keep_after:
        LOG.info("keep_after set; leaving ECR repo %s in place", repo_name)
        return
    LOG.info("Deleting ECR repo %s", repo_name)
    try:
        ecr.delete_repository(repositoryName=repo_name, force=True)
    except ecr.exceptions.RepositoryNotFoundException:
        pass


@pytest.mark.serving
@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
def test_experiment2_serves_model(
    service_network: dict,
    keep_after: bool,
    test_role_arn: str,
    aws_region: str,
    subzone: dict,
    aws_provider_version: str,
    vllm_image: str,
    cleanup_ecs_task_definitions: Callable[[str], None],
    boto3_session: Session,
) -> None:
    """
    Experiment 2: serve a real 7B model on the ECS GPU module and prove it answers.

    Stands up two ``g5.2xlarge`` GPU nodes via terraform-aws-ecs (``gpu_count=1``),
    each fetching ``Qwen/Qwen2.5-7B-Instruct`` from Hugging Face with
    ``fetch_model.sh`` and serving it with vLLM behind the ALB. Asserts the model
    loaded (vLLM ``/health``), the weights landed on disk, and a real prompt to
    ``/v1/chat/completions`` returns a well-formed completion.

    Not run in CI (needs GPU capacity and incurs cost). Run with
    ``make test-experiment2`` (add ``KEEP_AFTER=1`` to keep the resources).

    :param service_network: Fixture providing VPC subnet IDs.
    :param keep_after: If True, do not destroy infrastructure after the test.
    :param test_role_arn: IAM role ARN to assume for the test.
    :param aws_region: AWS region for the test.
    :param subzone: Fixture providing the Route53 subzone ID.
    :param aws_provider_version: AWS provider version constraint.
    :param vllm_image: ECR image URI of the built vLLM image.
    :param cleanup_ecs_task_definitions: Fixture to deregister task definitions.
    :param boto3_session: Boto3 session for AWS API calls.
    """
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    zone_id = subzone["subzone_id"]["value"]

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "experiment2")
    cleanup_dot_terraform(terraform_module_dir)
    update_terraform_tf(terraform_module_dir, aws_provider_version)
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(dedent(f"""
                zone_id       = "{zone_id}"
                region        = "{aws_region}"
                docker_image  = "{vllm_image}"

                subnet_public_ids   = {json.dumps(subnet_public_ids)}
                subnet_private_ids  = {json.dumps(subnet_private_ids)}
                """))
        if test_role_arn:
            fp.write(dedent(f"""
                    role_arn = "{test_role_arn}"
                    """))

    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
        json_output=True,
    ) as tf_output:
        LOG.info(json.dumps(tf_output, indent=4))
        service_name = tf_output["service_name"]["value"]
        cluster_name = tf_output["cluster_name"]["value"]
        hostname = tf_output["dns_hostnames"]["value"][0]
        cleanup_ecs_task_definitions(service_name)

        # The assertion that matters: the model loads and the service serves.
        # /health only returns 200 after fetch_model.sh succeeded (set -e in the
        # entrypoint) and vLLM finished loading the weights.
        _wait_for_vllm_health(hostname)

        ecs_client = boto3_session.client("ecs", region_name=aws_region)

        # All requested GPU nodes registered with the cluster.
        container_instance_arns = ecs_client.list_container_instances(
            cluster=cluster_name
        )["containerInstanceArns"]
        assert (
            len(container_instance_arns) >= 2
        ), f"Expected >= 2 container instances, got {len(container_instance_arns)}"
        container_instances = ecs_client.describe_container_instances(
            cluster=cluster_name,
            containerInstances=container_instance_arns,
        )["containerInstances"]

        # Fetch happened: the weights are present on the host with a plausible
        # size (Qwen2.5-7B in bf16 is ~15 GB; assert > 5 GB to stay robust).
        host = EC2Instance(
            instance_id=container_instances[0]["ec2InstanceId"],
            region=aws_region,
            session=boto3_session,
        )
        model_path = f"{MODEL_DIR_ON_HOST}/{MODEL_NAME}"
        exit_code, stdout, stderr = host.execute_command(
            f"du -sb {model_path}", execution_timeout=180
        )
        assert exit_code == 0, f"could not stat {model_path}: {stderr}"
        total_bytes = int(stdout.split()[0])
        assert (
            total_bytes > 5 * 1024**3
        ), f"fetched model implausibly small: {total_bytes} bytes at {model_path}"
        LOG.info("Fetched model size on host: %d bytes (%s)", total_bytes, model_path)

        exit_code, stdout, stderr = host.execute_command(
            f"ls {model_path}", execution_timeout=60
        )
        assert exit_code == 0, f"could not list {model_path}: {stderr}"
        assert "config.json" in stdout, f"no config.json in {model_path}: {stdout}"
        assert ".safetensors" in stdout, f"no weights in {model_path}: {stdout}"

        # The model answers: a real prompt returns a well-formed completion.
        completions_url = f"https://{hostname}/v1/chat/completions"
        payload = {
            "model": MODEL_NAME,
            "messages": [{"role": "user", "content": PROMPT}],
            "max_tokens": 64,
            "temperature": 0,
        }
        response = requests.post(completions_url, json=payload, timeout=120)
        assert (
            response.status_code == 200
        ), f"completion failed: {response.status_code} {response.text}"
        content = response.json()["choices"][0]["message"]["content"]
        assert content.strip(), "model returned an empty completion"
        # Captured for the blog: one real prompt/response pair.
        LOG.info("=== EXPERIMENT 2 PROMPT/RESPONSE ===")
        LOG.info("PROMPT:   %s", PROMPT)
        LOG.info("RESPONSE: %s", content.strip())

        # Both nodes serve: fire several requests; all must succeed.
        for i in range(6):
            r = requests.post(completions_url, json=payload, timeout=120)
            assert r.status_code == 200, f"request {i} failed: {r.status_code} {r.text}"
        LOG.info("Fleet served 6/6 follow-up requests successfully")
