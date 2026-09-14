import json
from ipaddress import IPv4Address
from os import path as osp
from textwrap import dedent
from typing import Callable

import pytest
from boto3 import Session
from pytest_infrahouse import terraform_apply
from requests import get

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
    update_terraform_tf,
    cleanup_dot_terraform,
    wait_for_success,
)

# Ports must match test_data/httpd_tcp_extra_tg/main.tf.
CONTAINER_PORT = 80
EXTRA_PORT = 8080


def runner_public_ip() -> str:
    """
    Return the public IPv4 address this test runner uses to reach the internet.

    :return: IPv4 address, e.g. ``"203.0.113.10"``.
    :raise requests.HTTPError: If checkip.amazonaws.com returns an error.
    :raise ValueError: If the response is not an IPv4 address.
    """
    response = get("https://checkip.amazonaws.com", timeout=10)
    response.raise_for_status()
    return str(IPv4Address(response.text.strip()))


@pytest.mark.parametrize("aws_provider_version", ["~> 6.0"], ids=["aws-6"])
def test_nlb_extra_target_group(
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
    Test an NLB service with one extra target group and a non-default ``ingress_cidr_blocks``.

    Validates:

    - The extra target group uses TCP.
    - A TCP listener on the extra port forwards to the extra target group.
    - The NLB security group allows exactly ``ingress_cidr_blocks`` on the primary and the extra listener ports.
    - The ECS service is registered with the primary and the extra target group.
    - httpd responds through the NLB on the primary and the extra listener ports.

    ``ingress_cidr_blocks`` is the runner's public IP plus ``10.0.0.0/8``: non-default, with more than one entry,
    and still open to the runner so the test can send requests through the NLB.

    :param service_network: Fixture providing the test VPC outputs.
    :param keep_after: If True, keep the infrastructure after the test.
    :param test_role_arn: IAM role for Terraform to assume.
    :param aws_region: AWS region under test.
    :param subzone: Fixture providing the test Route53 zone.
    :param aws_provider_version: AWS provider version constraint.
    :param cleanup_ecs_task_definitions: Registers a task family for cleanup.
    :param boto3_session: Boto3 session for AWS API calls.
    """
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    zone_id = subzone["subzone_id"]["value"]
    ingress_cidr_blocks = [f"{runner_public_ip()}/32", "10.0.0.0/8"]
    LOG.info("ingress_cidr_blocks: %s", ingress_cidr_blocks)

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "httpd_tcp_extra_tg")
    cleanup_dot_terraform(terraform_module_dir)
    update_terraform_tf(terraform_module_dir, aws_provider_version)
    with open(
        osp.join(terraform_module_dir, "terraform.tfvars"), "w", encoding="utf-8"
    ) as fp:
        fp.write(dedent(f"""
                zone_id = "{zone_id}"
                region  = "{aws_region}"

                subnet_public_ids   = {json.dumps(subnet_public_ids)}
                subnet_private_ids  = {json.dumps(subnet_private_ids)}
                ingress_cidr_blocks = {json.dumps(ingress_cidr_blocks)}
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
        cleanup_ecs_task_definitions(service_name)

        elbv2_client = boto3_session.client("elbv2", region_name=aws_region)
        ec2_client = boto3_session.client("ec2", region_name=aws_region)
        ecs_client = boto3_session.client("ecs", region_name=aws_region)

        # The extra target group uses TCP
        extra_tg_arns = tf_output["extra_target_group_arns"]["value"]
        assert list(extra_tg_arns) == [
            "extra"
        ], f"Expected only the 'extra' key in extra_target_group_arns, got {list(extra_tg_arns)}"
        extra_tg_arn = extra_tg_arns["extra"]
        extra_tg = elbv2_client.describe_target_groups(TargetGroupArns=[extra_tg_arn])[
            "TargetGroups"
        ][0]
        LOG.info("Extra target group: %s", json.dumps(extra_tg, indent=2, default=str))
        assert extra_tg["Protocol"] == "TCP"
        assert extra_tg["HealthCheckProtocol"] == "TCP"

        # A TCP listener on the extra port forwards to the extra target group
        listeners = elbv2_client.describe_listeners(
            LoadBalancerArn=tf_output["load_balancer_arn"]["value"]
        )["Listeners"]
        LOG.info("NLB listeners: %s", json.dumps(listeners, indent=2, default=str))
        extra_listeners = [
            listener for listener in listeners if listener["Port"] == EXTRA_PORT
        ]
        assert (
            len(extra_listeners) == 1
        ), f"Expected one listener on port {EXTRA_PORT}, got {len(extra_listeners)}"
        assert extra_listeners[0]["Protocol"] == "TCP"
        assert extra_listeners[0]["DefaultActions"][0]["TargetGroupArn"] == extra_tg_arn

        # The NLB security group allows exactly ingress_cidr_blocks on both listener ports
        nlb_security_groups = tf_output["load_balancer_security_groups"]["value"]
        assert (
            len(nlb_security_groups) == 1
        ), f"Expected one NLB security group, got {nlb_security_groups}"
        rules = ec2_client.describe_security_group_rules(
            Filters=[{"Name": "group-id", "Values": nlb_security_groups}]
        )["SecurityGroupRules"]
        LOG.info("NLB security group rules: %s", json.dumps(rules, indent=2))
        for port in (CONTAINER_PORT, EXTRA_PORT):
            sources = {
                rule.get("CidrIpv4")
                for rule in rules
                if not rule["IsEgress"]
                and rule["IpProtocol"] == "tcp"
                and rule["FromPort"] == port
                and rule["ToPort"] == port
            }
            assert sources == set(
                ingress_cidr_blocks
            ), f"Port {port}: expected sources {sorted(ingress_cidr_blocks)}, got {sources}"

        # The ECS service is registered with the primary and the extra target group
        services = ecs_client.describe_services(
            cluster=service_name,
            services=[service_name],
        )["services"]
        assert len(services) == 1
        load_balancers = services[0]["loadBalancers"]
        LOG.info("ECS service load balancers: %s", json.dumps(load_balancers, indent=2))
        registrations = {
            (lb["targetGroupArn"], lb["containerPort"]) for lb in load_balancers
        }
        assert registrations == {
            (tf_output["target_group_arn"]["value"], CONTAINER_PORT),
            (extra_tg_arn, EXTRA_PORT),
        }, f"Unexpected ECS service load balancers: {registrations}"

        # httpd responds through the NLB on both listener ports. A response on the extra port
        # proves the SG rule, the TCP listener, the target group, and the container port mapping.
        load_balancer_dns_name = tf_output["load_balancer_dns_name"]["value"]
        for port in (CONTAINER_PORT, EXTRA_PORT):
            wait_for_success(f"http://{load_balancer_dns_name}:{port}/")
