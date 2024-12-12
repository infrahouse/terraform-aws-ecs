import json
from os import path as osp
from textwrap import dedent

import pytest
from infrahouse_toolkit.terraform import terraform_apply

from tests.conftest import (
    LOG,
    TRACE_TERRAFORM,
    TEST_ZONE,
    TERRAFORM_ROOT_DIR,
    wait_for_success,
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
):
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    internet_gateway_id = service_network["internet_gateway_id"]["value"]

    # Create ECS with httpd container
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "httpd_autoscaling")
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                test_zone     = "{test_zone_name}"
                region        = "{aws_region}"

                subnet_public_ids   = {json.dumps(subnet_public_ids)}
                subnet_private_ids  = {json.dumps(subnet_private_ids)}
                internet_gateway_id = "{internet_gateway_id}"
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
        enable_trace=TRACE_TERRAFORM,
    ) as tf_httpd_output:
        LOG.info(json.dumps(tf_httpd_output, indent=4))
        for url in [f"https://www.{TEST_ZONE}", f"https://{TEST_ZONE}"]:
            wait_for_success(url)
