import json
from os import path as osp
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


@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
def test_extra_target_groups(
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

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "httpd_extra_tg")
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
    ) as tf_output:
        LOG.info(json.dumps(tf_output, indent=4))
        cleanup_ecs_task_definitions(tf_output["service_name"]["value"])

        # Verify the primary service works via DNS
        dns_hostnames = tf_output["dns_hostnames"]["value"]
        for hostname in dns_hostnames:
            url = f"https://{hostname}"
            wait_for_success(url)

        # Verify both target groups are present in the ECS service
        ecs_client = boto3_session.client("ecs", region_name=aws_region)
        service_name = tf_output["service_name"]["value"]

        services = ecs_client.describe_services(
            cluster=service_name,
            services=[service_name],
        )
        assert len(services["services"]) == 1
        svc = services["services"][0]

        load_balancers = svc["loadBalancers"]
        LOG.info(
            "ECS service load balancers: %s",
            json.dumps(load_balancers, indent=2),
        )
        assert (
            len(load_balancers) == 2
        ), f"Expected 2 load balancer registrations, got {len(load_balancers)}"

        # Verify the primary target group (port 80)
        primary_tg_arn = tf_output["target_group_arn"]["value"]
        primary_lb = [
            lb for lb in load_balancers if lb["targetGroupArn"] == primary_tg_arn
        ]
        assert len(primary_lb) == 1, "Primary target group not found in ECS service"
        assert primary_lb[0]["containerPort"] == 80

        # Verify an extra target group exists (port 8081)
        extra_lbs = [
            lb for lb in load_balancers if lb["targetGroupArn"] != primary_tg_arn
        ]
        assert len(extra_lbs) == 1, "Extra target group not found in ECS service"
        assert extra_lbs[0]["containerPort"] == 8081

        # Verify the task definition has both port mappings
        task_def_arn = svc["taskDefinition"]
        task_def = ecs_client.describe_task_definition(
            taskDefinition=task_def_arn,
        )
        container_def = task_def["taskDefinition"]["containerDefinitions"][0]
        port_mappings = container_def["portMappings"]
        LOG.info(
            "Task definition port mappings: %s",
            json.dumps(port_mappings, indent=2, default=str),
        )
        container_ports = {pm["containerPort"] for pm in port_mappings}
        assert 80 in container_ports, "Primary port 80 not in port mappings"
        assert 8081 in container_ports, "Extra port 8081 not in port mappings"
