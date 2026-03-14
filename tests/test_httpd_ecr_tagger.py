import json
import time
from os import path as osp
from textwrap import dedent

import pytest
from infrahouse_core.aws import ECRRepository
from infrahouse_core.timeout import timeout
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    wait_for_success,
    TERRAFORM_ROOT_DIR,
    update_terraform_tf,
    cleanup_dot_terraform,
)


@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
def test_ecr_image_tagging(
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

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "httpd_ecr_tagger")
    cleanup_dot_terraform(terraform_module_dir)
    update_terraform_tf(terraform_module_dir, aws_provider_version)
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                zone_id = "{zone_id}"
                region  = "{aws_region}"

                subnet_public_ids  = {json.dumps(subnet_public_ids)}
                subnet_private_ids = {json.dumps(subnet_private_ids)}
                """
            )
        )
        if test_role_arn:
            fp.write(
                dedent(
                    f"""
                    role_arn = "{test_role_arn}"
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

        # Wait for ECS service to become healthy
        dns_hostnames = tf_output["dns_hostnames"]["value"]
        for hostname in dns_hostnames:
            url = f"https://{hostname}"
            wait_for_success(url)

        # Force a new deployment so EventBridge fires SERVICE_STEADY_STATE
        # *after* the rule and Lambda exist. The initial steady state event
        # likely fired during terraform apply before the rule was created.
        cluster_name = tf_output["cluster_name"]["value"]
        service_name = tf_output["service_name"]["value"]
        ecs_client = boto3_session.client("ecs", region_name=aws_region)
        LOG.info("Forcing new ECS deployment to trigger SERVICE_STEADY_STATE...")
        ecs_client.update_service(
            cluster=cluster_name,
            service=service_name,
            forceNewDeployment=True,
        )

        # Wait for the new deployment to reach steady state
        LOG.info("Waiting for new deployment to stabilize...")
        waiter = ecs_client.get_waiter("services_stable")
        waiter.wait(
            cluster=cluster_name,
            services=[service_name],
            WaiterConfig={"Delay": 15, "MaxAttempts": 40},
        )
        LOG.info("Service is stable after forced deployment.")

        # Poll ECR for the deployed-at- tag
        # EventBridge -> Lambda is async, may take a minute
        ecr_repo_name = tf_output["ecr_repo_name"]["value"]
        LOG.info("Checking ECR repo %s for deployed-at- tag...", ecr_repo_name)

        repo = ECRRepository(
            ecr_repo_name,
            session=boto3_session,
            region=aws_region,
        )
        assert repo.exists, f"ECR repository {ecr_repo_name} does not exist"

        image = repo.get_image(tag="latest")
        assert image.exists, "Image latest does not exist in ECR repo"

        deployed_tag = None
        with timeout(300):
            while True:
                tags = image.tags
                LOG.info("Current image tags: %s", tags)
                for tag in tags:
                    if tag.startswith("deployed-at-"):
                        deployed_tag = tag
                        break
                if deployed_tag:
                    break
                LOG.info("No deployed-at- tag yet, retrying in 10s...")
                time.sleep(10)

        assert deployed_tag is not None, (
            "ECR image was not tagged with deployed-at-* "
            "within 5 minutes of steady state"
        )
        LOG.info("ECR image tagged successfully: %s", deployed_tag)
