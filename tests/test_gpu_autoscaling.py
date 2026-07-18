import json
import time
from os import path as osp
from textwrap import dedent
from typing import Callable

import pytest
from boto3 import Session
from infrahouse_core.timeout import timeout
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
    update_terraform_tf,
    cleanup_dot_terraform,
)

# The aggregated series the GPU scaling policy tracks (see autoscaling.tf and
# assets/cloudwatch_agent_config_gpu.tftmpl): metric nvidia_smi_utilization_gpu in
# namespace CWAgent, keyed only by AutoScalingGroupName.
GPU_METRICS_NAMESPACE = "CWAgent"
GPU_UTIL_METRIC = "nvidia_smi_utilization_gpu"

# Publish injected samples with a large Count so their Average dominates the real
# (idle, ~0%) values the CloudWatch agent emits into the same series. The policy
# uses the Average statistic, so a high-count injection deterministically drives it.
INJECT_SAMPLE_COUNT = 1000.0


def _put_gpu_util(cloudwatch_client, asg_name: str, value: float) -> None:
    """
    Publish a GPU-utilization datapoint into the aggregated policy series.

    :param cloudwatch_client: Boto3 CloudWatch client.
    :param asg_name: AutoScalingGroupName dimension value.
    :param value: GPU utilization percentage to publish.
    """
    cloudwatch_client.put_metric_data(
        Namespace=GPU_METRICS_NAMESPACE,
        MetricData=[
            {
                "MetricName": GPU_UTIL_METRIC,
                "Dimensions": [{"Name": "AutoScalingGroupName", "Value": asg_name}],
                "Values": [float(value)],
                "Counts": [INJECT_SAMPLE_COUNT],
                "Unit": "Percent",
            }
        ],
    )


def _get_desired_count(ecs_client, cluster_name: str, service_name: str) -> int:
    """
    Return the ECS service's current desiredCount (the lever the policy moves).

    :param ecs_client: Boto3 ECS client.
    :param cluster_name: ECS cluster name.
    :param service_name: ECS service name.
    :return: Current desiredCount of the service.
    """
    services = ecs_client.describe_services(
        cluster=cluster_name, services=[service_name]
    )["services"]
    assert services, f"Service {service_name} not found in cluster {cluster_name}"
    return services[0]["desiredCount"]


def _drive_until_desired(
    ecs_client,
    cloudwatch_client,
    cluster_name: str,
    service_name: str,
    asg_name: str,
    inject_value: float,
    predicate: Callable[[int], bool],
    timeout_s: int,
    phase: str,
) -> int:
    """
    Continuously inject a GPU-utilization value and wait for desiredCount to satisfy
    ``predicate``. Injecting on every poll keeps a fresh datapoint in each 60s period
    so the target-tracking alarm can accumulate breaching periods.

    :param ecs_client: Boto3 ECS client.
    :param cloudwatch_client: Boto3 CloudWatch client.
    :param cluster_name: ECS cluster name.
    :param service_name: ECS service name.
    :param asg_name: AutoScalingGroupName dimension value.
    :param inject_value: GPU utilization percentage to keep publishing.
    :param predicate: Returns True once desiredCount is where we want it.
    :param timeout_s: Maximum seconds to wait.
    :param phase: Human-readable phase name for log/error messages.
    :return: The desiredCount that satisfied the predicate.
    :raises AssertionError: If the predicate is not satisfied within the timeout.
    """
    last = None
    try:
        with timeout(timeout_s):
            while True:
                _put_gpu_util(cloudwatch_client, asg_name, inject_value)
                last = _get_desired_count(ecs_client, cluster_name, service_name)
                if predicate(last):
                    LOG.info("%s: desiredCount=%d (satisfied)", phase, last)
                    return last
                LOG.info(
                    "%s: desiredCount=%d, injecting GPU util=%.0f%%",
                    phase,
                    last,
                    inject_value,
                )
                time.sleep(30)
    except TimeoutError as err:
        raise AssertionError(
            f"{phase}: desiredCount stayed at {last} within {timeout_s}s "
            f"(injecting GPU util={inject_value}% into {GPU_METRICS_NAMESPACE}/"
            f"{GPU_UTIL_METRIC} for AutoScalingGroupName={asg_name})"
        ) from err


@pytest.mark.autoscaling
@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
def test_gpu_autoscaling_policy(
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
    Verify the GPU target-tracking policy scales the ECS service on GPU utilization.

    Stands up a GPU stack with headroom (task_max_count = 2, asg_max_size = 2) and a
    single task, then drives the policy directly via CloudWatch PutMetricData rather
    than by loading a real GPU: it injects a high nvidia_smi_utilization_gpu into the
    aggregated (AutoScalingGroupName) series the policy tracks and asserts the service
    scales out, then injects a low value and asserts it scales back in. This isolates
    the policy wiring (metric name / namespace / dimension / target) from any real
    GPU workload, so it is deterministic and does not need a model.

    Not run in CI (requires GPU capacity and incurs cost). Run with
    ``make test-gpu-autoscaling`` (add ``KEEP_AFTER=1`` to keep the resources).

    :param service_network: Fixture providing VPC subnet IDs.
    :param keep_after: If True, do not destroy infrastructure after the test.
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

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "test_gpu_autoscaling")
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
        cluster_name = tf_output["cluster_name"]["value"]
        asg_name = tf_output["asg_name"]["value"]
        cleanup_ecs_task_definitions(service_name)

        ecs_client = boto3_session.client("ecs", region_name=aws_region)
        cloudwatch_client = boto3_session.client("cloudwatch", region_name=aws_region)

        # The service starts pinned at one task (task_desired_count = 1). Application
        # Auto Scaling will only move it when the GPU policy's alarm fires.
        initial_desired = _get_desired_count(ecs_client, cluster_name, service_name)
        assert (
            initial_desired == 1
        ), f"Expected initial desiredCount 1, got {initial_desired}"
        LOG.info("Initial desiredCount=%d", initial_desired)

        # Scale-out: high GPU utilization must raise desiredCount to the max (2).
        # Target-tracking scale-out needs ~3 breaching 60s periods plus the scaling
        # action, so allow generous time.
        scaled_out = _drive_until_desired(
            ecs_client,
            cloudwatch_client,
            cluster_name,
            service_name,
            asg_name,
            inject_value=100,
            predicate=lambda desired: desired >= 2,
            timeout_s=720,
            phase="scale-out",
        )
        assert (
            scaled_out == 2
        ), f"Expected scale-out to desiredCount 2, got {scaled_out}"
        LOG.info("GPU policy scaled the service out to desiredCount=%d", scaled_out)

        # Scale-in: low GPU utilization must return desiredCount to the min (1). ECS
        # target-tracking scale-in is intentionally slow (a longer alarm window plus
        # the scale_in_cooldown), so allow substantially more time than scale-out.
        scaled_in = _drive_until_desired(
            ecs_client,
            cloudwatch_client,
            cluster_name,
            service_name,
            asg_name,
            inject_value=0,
            predicate=lambda desired: desired <= 1,
            timeout_s=1500,
            phase="scale-in",
        )
        assert scaled_in == 1, f"Expected scale-in to desiredCount 1, got {scaled_in}"
        LOG.info("GPU policy scaled the service back in to desiredCount=%d", scaled_in)
