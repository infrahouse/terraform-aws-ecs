import json
from os import path as osp
from textwrap import dedent

from infrahouse_toolkit.terraform import terraform_apply
from requests import get

from tests.conftest import (
    LOG,
    TRACE_TERRAFORM,
    DESTROY_AFTER,
    TEST_ZONE,
    TEST_ROLE_ARN,
    REGION,
)


def test_module(ec2_client, route53_client):
    terraform_root_dir = "test_data/"

    terraform_module_dir = osp.join(terraform_root_dir, "service-network")
    # Create service network
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                role_arn = "{TEST_ROLE_ARN}"
                region = "{REGION}"
                """
            )
        )
    with terraform_apply(
        terraform_module_dir,
        destroy_after=DESTROY_AFTER,
        json_output=True,
        enable_trace=TRACE_TERRAFORM,
    ) as tf_service_network_output:
        LOG.info(json.dumps(tf_service_network_output, indent=4))

        subnet_public_ids = tf_service_network_output["subnet_public_ids"]["value"]
        subnet_private_ids = tf_service_network_output["subnet_private_ids"]["value"]
        internet_gateway_id = tf_service_network_output["internet_gateway_id"]["value"]

        # Create ECS with httpd container
        terraform_module_dir = osp.join(terraform_root_dir, "httpd")
        with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
            fp.write(
                dedent(
                    f"""
                    role_arn = "{TEST_ROLE_ARN}"
                    task_role_arn = "{TEST_ROLE_ARN}"
                    test_zone = "{TEST_ZONE}"
                    region = "{REGION}"

                    subnet_public_ids = {json.dumps(subnet_public_ids)}
                    subnet_private_ids = {json.dumps(subnet_private_ids)}
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
            for url in [f"https://www.{TEST_ZONE}", f"https://{TEST_ZONE}"]:
                response = get(url)
                assert response.status_code == 200
                assert response.text == "<html><body><h1>It works!</h1></body></html>\n"
