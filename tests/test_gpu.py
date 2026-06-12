import json
from os import path as osp
from textwrap import dedent
from typing import Any

import pytest
from boto3 import Session
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
    update_terraform_tf,
    cleanup_dot_terraform,
)


@pytest.mark.parametrize(
    "gpu_count, expect_gpu",
    [
        (0, False),
        (1, True),
        (2, True),
    ],
    ids=["no-gpu", "one-gpu", "two-gpu"],
)
@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
def test_gpu_resource_requirements(
    service_network: dict,
    keep_after: bool,
    test_role_arn: str,
    aws_region: str,
    subzone: dict,
    aws_provider_version: str,
    cleanup_ecs_task_definitions: Any,
    boto3_session: Session,
    gpu_count: int,
    expect_gpu: bool,
) -> None:
    """
    Validate that the task definition includes GPU resourceRequirements
    when gpu_count > 0 and omits them when gpu_count == 0.

    :param service_network: Fixture providing VPC subnet IDs.
    :param keep_after: If True, do not destroy infrastructure after test.
    :param test_role_arn: IAM role ARN to assume for the test.
    :param aws_region: AWS region for the test.
    :param subzone: Fixture providing Route53 subzone ID.
    :param aws_provider_version: AWS provider version constraint.
    :param cleanup_ecs_task_definitions: Fixture to deregister task definitions.
    :param boto3_session: Boto3 session for AWS API calls.
    :param gpu_count: Number of GPUs to request (parametrized).
    :param expect_gpu: Whether GPU resourceRequirements should be present.
    """
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    zone_id = subzone["subzone_id"]["value"]

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "test_gpu")
    cleanup_dot_terraform(terraform_module_dir)
    update_terraform_tf(terraform_module_dir, aws_provider_version)
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                zone_id       = "{zone_id}"
                region        = "{aws_region}"
                gpu_count     = {gpu_count}

                subnet_public_ids   = {json.dumps(subnet_public_ids)}
                subnet_private_ids  = {json.dumps(subnet_private_ids)}
                """
            )
        )
        if test_role_arn:
            fp.write(
                dedent(
                    f"""
                    role_arn      = "{test_role_arn}"
                    """
                )
            )

    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
        json_output=True,
    ) as tf_output:
        LOG.info(json.dumps(tf_output, indent=4))
        cleanup_ecs_task_definitions(tf_output["service_name"]["value"])

        task_def_arn = tf_output["task_definition_arn"]["value"]
        LOG.info("Task definition ARN: %s", task_def_arn)

        ecs_client = boto3_session.client("ecs", region_name=aws_region)
        response = ecs_client.describe_task_definition(taskDefinition=task_def_arn)
        container_def = response["taskDefinition"]["containerDefinitions"][0]

        resource_requirements = container_def.get("resourceRequirements", [])

        if expect_gpu:
            gpu_reqs = [r for r in resource_requirements if r["type"] == "GPU"]
            assert len(gpu_reqs) == 1, (
                f"Expected exactly one GPU resourceRequirement, got: {gpu_reqs}"
            )
            assert gpu_reqs[0]["value"] == str(gpu_count), (
                f"Expected GPU value '{gpu_count}', got: '{gpu_reqs[0]['value']}'"
            )
            LOG.info("GPU resourceRequirements correctly present: %s", gpu_reqs)
        else:
            gpu_reqs = [r for r in resource_requirements if r["type"] == "GPU"]
            assert len(gpu_reqs) == 0, (
                f"Expected no GPU resourceRequirements, got: {gpu_reqs}"
            )
            LOG.info("GPU resourceRequirements correctly absent")
