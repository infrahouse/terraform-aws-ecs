import json
from os import path as osp
from textwrap import dedent

import pytest
from pytest_infrahouse import terraform_apply

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
    update_terraform_tf,
    cleanup_dot_terraform,
)


@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
def test_tempo_grpc_target_group(
    service_network,
    keep_after,
    test_role_arn,
    aws_region,
    subzone,
    aws_provider_version,
    cleanup_ecs_task_definitions,
    boto3_session,
):
    """Test that Tempo deploys with a gRPC extra target group.

    Validates:
    - The extra gRPC target group has ProtocolVersion = "gRPC"
    - The ECS service has two load_balancer registrations
    - Port mappings include both 3200 (HTTP) and 4317 (gRPC)
    """
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    zone_id = subzone["subzone_id"]["value"]

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "tempo_grpc")
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
        service_name = tf_output["service_name"]["value"]
        cleanup_ecs_task_definitions(service_name)

        # Verify the gRPC target group has ProtocolVersion = "gRPC"
        elbv2_client = boto3_session.client("elbv2", region_name=aws_region)
        extra_tg_arns = tf_output["extra_target_group_arns"]["value"]
        assert (
            "otlp_grpc" in extra_tg_arns
        ), "Expected 'otlp_grpc' key in extra_target_group_arns"

        grpc_tg_arn = extra_tg_arns["otlp_grpc"]
        tg_response = elbv2_client.describe_target_groups(TargetGroupArns=[grpc_tg_arn])
        assert len(tg_response["TargetGroups"]) == 1
        grpc_tg = tg_response["TargetGroups"][0]

        LOG.info(
            "gRPC target group details: %s",
            json.dumps(grpc_tg, indent=2, default=str),
        )
        assert grpc_tg["ProtocolVersion"] == "GRPC", (
            f"Expected ProtocolVersion 'GRPC', " f"got '{grpc_tg['ProtocolVersion']}'"
        )

        # Verify ECS service has both load_balancer registrations
        ecs_client = boto3_session.client("ecs", region_name=aws_region)
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
        assert len(load_balancers) == 2, (
            f"Expected 2 load balancer registrations, " f"got {len(load_balancers)}"
        )

        # Verify primary target group (port 3200)
        primary_tg_arn = tf_output["target_group_arn"]["value"]
        primary_lb = [
            lb for lb in load_balancers if lb["targetGroupArn"] == primary_tg_arn
        ]
        assert len(primary_lb) == 1, "Primary target group not found in ECS service"
        assert primary_lb[0]["containerPort"] == 3200

        # Verify extra gRPC target group (port 4317)
        extra_lbs = [
            lb for lb in load_balancers if lb["targetGroupArn"] != primary_tg_arn
        ]
        assert len(extra_lbs) == 1, "Extra gRPC target group not found in ECS service"
        assert extra_lbs[0]["containerPort"] == 4317

        # Verify the task definition has both port mappings
        task_def_arn = svc["taskDefinition"]
        task_def = ecs_client.describe_task_definition(
            taskDefinition=task_def_arn,
        )
        container_defs = task_def["taskDefinition"]["containerDefinitions"]
        # Find the main container (not the CloudWatch agent sidecar)
        main_container = [c for c in container_defs if c["name"] == service_name]
        assert len(main_container) == 1, "Main container not found in task definition"

        port_mappings = main_container[0]["portMappings"]
        LOG.info(
            "Task definition port mappings: %s",
            json.dumps(port_mappings, indent=2, default=str),
        )
        container_ports = {pm["containerPort"] for pm in port_mappings}
        assert 3200 in container_ports, "Primary port 3200 not in port mappings"
        assert 4317 in container_ports, "gRPC port 4317 not in port mappings"
