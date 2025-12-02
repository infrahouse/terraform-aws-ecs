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
def test_module(
    service_network,
    keep_after,
    subzone,
    test_role_arn,
    aws_region,
    aws_provider_version,
    cleanup_ecs_task_definitions,
):
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    zone_id = subzone["subzone_id"]["value"]

    # Create ECS with httpd container
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "httpd_tcp")
    # Clean up any existing Terraform state to ensure clean test
    cleanup_dot_terraform(terraform_module_dir)
    update_terraform_tf(terraform_module_dir, aws_provider_version)
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                zone_id       = "{zone_id}"
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
    with terraform_apply(
        terraform_module_dir,
        destroy_after=not keep_after,
        json_output=True,
    ) as tf_httpd_output:
        LOG.info(json.dumps(tf_httpd_output, indent=4))
        cleanup_ecs_task_definitions(tf_httpd_output["service_name"]["value"])
        load_balancer_dns_name = tf_httpd_output["load_balancer_dns_name"]["value"]
        wait_for_success(f"http://{load_balancer_dns_name}/")

        # Use dns_hostnames from output instead of constructing URLs
        dns_hostnames = tf_httpd_output["dns_hostnames"]["value"]
        for hostname in dns_hostnames:
            url = f"http://{hostname}/"
            wait_for_success(url)
