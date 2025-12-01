import json
from os import path as osp, remove
from textwrap import dedent

import pytest
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    wait_for_success,
    TERRAFORM_ROOT_DIR,
    update_terraform_tf,
    cleanup_dot_terraform,
)


@pytest.mark.parametrize(
    "aws_provider_version", ["~> 5.56", "~> 6.0"], ids=["aws-5", "aws-6"]
)
def test_module(
    service_network,
    keep_after,
    test_role_arn,
    aws_region,
    subzone,
    aws_provider_version,
    cleanup_ecs_task_definitions,
    boto3_session,
):
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    zone_id = subzone["subzone_id"]["value"]

    # Create ECS with httpd container
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "httpd")
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

        # Use dns_hostnames from output instead of constructing URLs
        dns_hostnames = tf_httpd_output["dns_hostnames"]["value"]
        for hostname in dns_hostnames:
            url = f"https://{hostname}"
            wait_for_success(url)

        # Validate CloudWatch log group encryption
        LOG.info("Validating CloudWatch log group encryption...")
        cloudwatch_log_group_names = tf_httpd_output["cloudwatch_log_group_names"][
            "value"
        ]
        assert (
            len(cloudwatch_log_group_names) == 3
        ), "Expected 3 CloudWatch log groups (ecs, syslog, dmesg)"
        assert "ecs" in cloudwatch_log_group_names, "Missing 'ecs' log group"
        assert "syslog" in cloudwatch_log_group_names, "Missing 'syslog' log group"
        assert "dmesg" in cloudwatch_log_group_names, "Missing 'dmesg' log group"

        cloudwatch_client = boto3_session.client("logs", region_name=aws_region)

        for log_type, log_group_name in cloudwatch_log_group_names.items():
            LOG.info(f"Checking {log_type} log group: {log_group_name}")
            response = cloudwatch_client.describe_log_groups(
                logGroupNamePrefix=log_group_name, limit=1
            )

            assert (
                len(response["logGroups"]) == 1
            ), f"Log group {log_group_name} not found"
            log_group = response["logGroups"][0]

            # Log the encryption status
            kms_key_id = log_group.get("kmsKeyId")
            if kms_key_id:
                LOG.info(
                    f"✓ {log_type} log group is encrypted with KMS key: {kms_key_id}"
                )
            else:
                LOG.info(
                    f"⚠ {log_type} log group is using AWS managed encryption (no custom KMS key)"
                )

            # For now we just log the encryption status
            # In the future, when KMS key is provided via tfvars, we can assert kms_key_id is not None
