import json
from os import path as osp
from textwrap import dedent

from infrahouse_toolkit.terraform import terraform_apply

from tests.conftest import (
    LOG,
    TRACE_TERRAFORM,
    DESTROY_AFTER,
    TEST_ZONE,
    TEST_ROLE_ARN,
    REGION,
    TERRAFORM_ROOT_DIR,
    wait_for_success,
    wait_for_success_tcp,
)


def test_module(service_network, jumphost, ec2_client, route53_client):
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    internet_gateway_id = service_network["internet_gateway_id"]["value"]

    # Create ECS with httpd container
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "httpd_tcp")
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                role_arn      = "{TEST_ROLE_ARN}"
                task_role_arn = "{TEST_ROLE_ARN}"
                test_zone     = "{TEST_ZONE}"
                region        = "{REGION}"

                subnet_public_ids   = {json.dumps(subnet_public_ids)}
                subnet_private_ids  = {json.dumps(subnet_private_ids)}
                internet_gateway_id = "{internet_gateway_id}"
                """
            )
        )

    with terraform_apply(
        terraform_module_dir,
        destroy_after=DESTROY_AFTER,
        json_output=True,
        enable_trace=TRACE_TERRAFORM,
    ) as tf_httpd_output:
        LOG.info(json.dumps(tf_httpd_output, indent=4))
        # for url in [f"https://www.{TEST_ZONE}", f"https://{TEST_ZONE}"]:
        #    wait_for_success_tcp(url)
