import json
import time
from textwrap import dedent
import socket

import boto3
import pytest
import logging
from os import path as osp

from infrahouse_toolkit.logging import setup_logging
from infrahouse_toolkit.terraform import terraform_apply
from requests import get

# "303467602807" is our test account
TEST_ACCOUNT = "303467602807"
TEST_ROLE_ARN = "arn:aws:iam::303467602807:role/ecs-tester"
DEFAULT_PROGRESS_INTERVAL = 10
TRACE_TERRAFORM = False
DESTROY_AFTER = True
UBUNTU_CODENAME = "jammy"

LOG = logging.getLogger(__name__)
REGION = "us-east-2"
TEST_ZONE = "ci-cd.infrahouse.com"
TERRAFORM_ROOT_DIR = "test_data"

setup_logging(LOG, debug=True)


def wait_for_success(url, wait_time=300):
    end_of_wait = time.time() + wait_time
    while time.time() < end_of_wait:
        try:
            response = get(url)
            assert response.status_code == 200
            assert response.text == "<html><body><h1>It works!</h1></body></html>\n"
            return

        except AssertionError as err:
            LOG.warning(err)
            LOG.debug("Waiting %d more seconds", end_of_wait - time.time())
            time.sleep(1)

    raise RuntimeError(f"{url} didn't become healthy after {wait_time} seconds")


def wait_for_success_tcp(host, port, wait_time=300):
    end_of_wait = time.time() + wait_time
    try:
        client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        client.settimeout(wait_time)
        client.connect((host, port))
        assert True
        client.close()
        return

    except AssertionError as err:
        LOG.warning(err)
        LOG.debug("Waiting more than %d seconds", wait_time)
        time.sleep(1)
    raise RuntimeError(f"{url} didn't become healthy after {wait_time} seconds")


@pytest.fixture(scope="session")
def aws_iam_role():
    sts = boto3.client("sts")
    return sts.assume_role(
        RoleArn=TEST_ROLE_ARN, RoleSessionName=TEST_ROLE_ARN.split("/")[1]
    )


@pytest.fixture(scope="session")
def boto3_session(aws_iam_role):
    return boto3.Session(
        aws_access_key_id=aws_iam_role["Credentials"]["AccessKeyId"],
        aws_secret_access_key=aws_iam_role["Credentials"]["SecretAccessKey"],
        aws_session_token=aws_iam_role["Credentials"]["SessionToken"],
    )


@pytest.fixture(scope="session")
def ec2_client(boto3_session):
    assert boto3_session.client("sts").get_caller_identity()["Account"] == TEST_ACCOUNT
    return boto3_session.client("ec2", region_name=REGION)


@pytest.fixture(scope="session")
def ec2_client_map(ec2_client, boto3_session):
    regions = [reg["RegionName"] for reg in ec2_client.describe_regions()["Regions"]]
    ec2_map = {reg: boto3_session.client("ec2", region_name=reg) for reg in regions}

    return ec2_map


@pytest.fixture()
def route53_client(boto3_session):
    return boto3_session.client("route53", region_name=REGION)


@pytest.fixture()
def elbv2_client(boto3_session):
    return boto3_session.client("elbv2", region_name=REGION)


@pytest.fixture(scope="session")
def service_network(boto3_session):
    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "service-network")
    # Create service network
    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                role_arn = "{TEST_ROLE_ARN}"
                region   = "{REGION}"
                """
            )
        )
    with terraform_apply(
        terraform_module_dir,
        destroy_after=DESTROY_AFTER,
        json_output=True,
        enable_trace=TRACE_TERRAFORM,
    ) as tf_service_network_output:
        yield tf_service_network_output


@pytest.fixture(scope="session")
def jumphost(boto3_session, service_network):
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]

    terraform_module_dir = osp.join(TERRAFORM_ROOT_DIR, "jumphost")

    with open(osp.join(terraform_module_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                role_arn  = "{TEST_ROLE_ARN}"
                region    = "{REGION}"
                test_zone = "{TEST_ZONE}"

                subnet_public_ids  = {json.dumps(subnet_public_ids)}
                subnet_private_ids = {json.dumps(subnet_private_ids)}
                """
            )
        )
    with terraform_apply(
        terraform_module_dir,
        destroy_after=DESTROY_AFTER,
        json_output=True,
        enable_trace=TRACE_TERRAFORM,
    ) as tf_output:
        yield tf_output
