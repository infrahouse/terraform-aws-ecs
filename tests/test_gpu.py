import json
from os import path as osp
from textwrap import dedent
from typing import Callable

import pytest
from boto3 import Session
from infrahouse_core.aws.ec2_instance import EC2Instance
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
    wait_for_success,
    update_terraform_tf,
    cleanup_dot_terraform,
)


@pytest.mark.gpu
@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
def test_gpu_smoke(
    service_network: dict,
    keep_after: bool,
    test_role_arn: str,
    aws_region: str,
    subzone: dict,
    aws_provider_version: str,
    cleanup_ecs_task_definitions: Callable[[str], None],
    boto3_session: Session,
) -> None:
    """
    Real GPU smoke test (Tier 2).

    Launches an ECS service on a GPU instance (g4dn.xlarge) booted from the
    GPU-optimized ECS AMI, with ``gpu_count = 1`` so the task reserves a GPU.
    The container's health check runs ``nvidia-smi``, so the service only
    becomes healthy if the GPU device and driver are visible inside the
    container. This verifies end-to-end that:

      - the GPU instance launches and the ECS agent registers a GPU resource
        on the container instance,
      - the task carrying a GPU resourceRequirement is placed and runs,
      - the container can talk to the GPU (the nvidia-smi health check), and
      - the service serves traffic through the load balancer.

    Not run in CI (requires GPU capacity and incurs cost). Run it explicitly
    with ``make test-gpu`` (add ``KEEP_AFTER=1`` to keep the resources).

    :param service_network: Fixture providing VPC subnet IDs.
    :param keep_after: If True, do not destroy infrastructure after test.
    :param test_role_arn: IAM role ARN to assume for the test.
    :param aws_region: AWS region for the test.
    :param subzone: Fixture providing Route53 subzone ID.
    :param aws_provider_version: AWS provider version constraint.
    :param cleanup_ecs_task_definitions: Fixture to deregister task definitions.
    :param boto3_session: Boto3 session for AWS API calls.
    """
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    zone_id = subzone["subzone_id"]["value"]

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "test_gpu")
    cleanup_dot_terraform(terraform_module_dir)
    update_terraform_tf(terraform_module_dir, aws_provider_version)
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(dedent(f"""
                zone_id       = "{zone_id}"
                region        = "{aws_region}"

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
        cleanup_ecs_task_definitions(service_name)

        # End-to-end proof: the service only serves traffic if the GPU task
        # placed on the GPU instance and the nvidia-smi health check passed.
        for hostname in tf_output["dns_hostnames"]["value"]:
            wait_for_success(f"https://{hostname}")

        ecs_client = boto3_session.client("ecs", region_name=aws_region)

        # Host-level proof: the GPU instance registered a GPU resource with
        # the ECS agent. Without the GPU-optimized AMI this set is empty.
        cluster_name = tf_output["cluster_name"]["value"]
        container_instance_arns = ecs_client.list_container_instances(
            cluster=cluster_name
        )["containerInstanceArns"]
        assert container_instance_arns, "No container instances registered in cluster"

        container_instances = ecs_client.describe_container_instances(
            cluster=cluster_name,
            containerInstances=container_instance_arns,
        )["containerInstances"]
        gpu_ids = [
            gpu_id
            for ci in container_instances
            for resource in ci["registeredResources"]
            if resource["name"] == "GPU"
            for gpu_id in resource["stringSetValue"]
        ]
        assert gpu_ids, (
            "No GPU resource registered on any container instance; the "
            "GPU-optimized AMI / GPU instance type did not expose a GPU"
        )
        LOG.info("Container instances registered GPUs: %s", gpu_ids)

        # Task-level proof: the running task definition reserves a GPU. Select the
        # app container by name rather than by index, to stay correct if a sidecar
        # is ever added to the task definition.
        task_def_arn = tf_output["task_definition_arn"]["value"]
        container_defs = ecs_client.describe_task_definition(
            taskDefinition=task_def_arn
        )["taskDefinition"]["containerDefinitions"]
        container_def = next(
            (c for c in container_defs if c["name"] == service_name), None
        )
        assert (
            container_def
        ), f"No container definition named {service_name}; got {[c['name'] for c in container_defs]}"
        gpu_reqs = [
            r
            for r in container_def.get("resourceRequirements", [])
            if r["type"] == "GPU"
        ]
        assert (
            len(gpu_reqs) == 1
        ), f"Expected exactly one GPU resourceRequirement, got: {gpu_reqs}"
        assert (
            gpu_reqs[0]["value"] == "1"
        ), f"Expected GPU value '1', got: '{gpu_reqs[0]['value']}'"
        LOG.info("Task definition reserves GPU: %s", gpu_reqs)

        # Allocation proof: the running task got a physical GPU device bound to
        # it, and the nvidia-smi container health check reports HEALTHY.
        running_task_arns = ecs_client.list_tasks(
            cluster=cluster_name, desiredStatus="RUNNING"
        )["taskArns"]
        running_tasks = ecs_client.describe_tasks(
            cluster=cluster_name, tasks=running_task_arns
        )["tasks"]
        gpu_tasks = [t for t in running_tasks if t["taskDefinitionArn"] == task_def_arn]
        assert (
            gpu_tasks
        ), f"No running task for {task_def_arn}; running={running_task_arns}"
        task_containers = gpu_tasks[0]["containers"]
        gpu_container = next(
            (c for c in task_containers if c["name"] == service_name), None
        )
        assert (
            gpu_container
        ), f"No container named {service_name} in running task; got {[c['name'] for c in task_containers]}"
        assert gpu_container["gpuIds"], "Running task was not allocated a GPU device"
        assert (
            gpu_container["healthStatus"] == "HEALTHY"
        ), f"Container not HEALTHY (nvidia-smi health check): {gpu_container['healthStatus']}"
        LOG.info(
            "Running task GPU devices: %s (health=%s)",
            gpu_container["gpuIds"],
            gpu_container["healthStatus"],
        )

        # Strongest proof: run nvidia-smi over SSM (via infrahouse-core) on the
        # ECS host and inside the running container. Confirms the GPU is usable
        # both on the instance and from within the task's container.
        host = EC2Instance(
            instance_id=container_instances[0]["ec2InstanceId"],
            region=aws_region,
            session=boto3_session,
        )

        # Larger execution_timeout than the infrahouse-core default of 60s: on a
        # freshly booted GPU host the first nvidia-smi (and the docker exec) can
        # be slow while the NVIDIA stack initializes.
        exit_code, stdout, stderr = host.execute_command(
            "nvidia-smi -L", execution_timeout=180
        )
        assert exit_code == 0, f"nvidia-smi failed on host: {stderr}"
        assert "GPU" in stdout, f"No GPU listed on host: {stdout}"
        LOG.info("Host nvidia-smi -L:\n%s", stdout)

        # head -n1 guards against more than one matching container ever landing
        # on the host; docker exec needs exactly one container ID.
        exit_code, stdout, stderr = host.execute_command(
            f'docker exec "$(docker ps -qf '
            f"label=com.amazonaws.ecs.container-name={service_name} "
            f'| head -n1)" nvidia-smi -L',
            execution_timeout=180,
        )
        assert exit_code == 0, f"nvidia-smi failed inside container: {stderr}"
        assert "GPU" in stdout, f"No GPU visible inside container: {stdout}"
        LOG.info("Container nvidia-smi -L:\n%s", stdout)
