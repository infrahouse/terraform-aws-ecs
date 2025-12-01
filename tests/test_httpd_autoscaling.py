import json
from os import path as osp, remove
from textwrap import dedent

import pytest
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
    wait_for_success,
    update_terraform_tf,
    cleanup_dot_terraform,
)


@pytest.mark.parametrize(
    "aws_provider_version", ["~> 5.56", "~> 6.0"], ids=["aws-5", "aws-6"]
)
@pytest.mark.parametrize(
    "autoscaling_metric, autoscaling_target",
    [
        ("ALBRequestCountPerTarget", 100),
        ("ECSServiceAverageMemoryUtilization", 1024 * 1024 * 1024),
        ("ECSServiceAverageCPUUtilization", 70),
    ],
)
def test_module(
    autoscaling_metric,
    autoscaling_target,
    service_network,
    keep_after,
    test_zone_name,
    test_role_arn,
    aws_region,
    aws_provider_version,
    cleanup_ecs_task_definitions,
):
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]

    # Create ECS with httpd container
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "httpd_autoscaling")
    cleanup_dot_terraform(terraform_module_dir)
    update_terraform_tf(terraform_module_dir, aws_provider_version)
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                test_zone     = "{test_zone_name}"
                region        = "{aws_region}"

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
                    task_role_arn = "{test_role_arn}"
                    """
                )
            )
        fp.write(
            dedent(
                f"""
                autoscaling_metric = "{autoscaling_metric}"
                autoscaling_target = {autoscaling_target}
                """
            )
        )

    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
        json_output=True,
    ) as tf_httpd_output:
        LOG.info(json.dumps(tf_httpd_output, indent=4))
        cleanup_ecs_task_definitions(tf_httpd_output["service_name"]["value"])
        for url in [f"https://www.{test_zone_name}", f"https://{test_zone_name}"]:
            wait_for_success(url)
