import shutil
import time
import logging
from os import path as osp, remove
from textwrap import dedent

import pytest
from boto3 import Session
from botocore.exceptions import ClientError
from infrahouse_core.logging import setup_logging
from infrahouse_core.timeout import timeout
from requests import get
from requests.exceptions import RequestException

DEFAULT_PROGRESS_INTERVAL = 10

LOG = logging.getLogger(__name__)
TERRAFORM_ROOT_DIR = "test_data"

setup_logging(LOG, debug=True)
# setup_logging only attaches handlers to the logger it is given, so pytest-infrahouse
# helpers (e.g. wait_for_instance_refresh) log to a handler-less logger and stay silent.
# Configure their package logger too so their progress is visible during the run.
setup_logging(logging.getLogger("pytest_infrahouse"), debug=True)


def wait_for_success(url, wait_time=300, request_timeout=10):
    """
    Wait for a URL to return a successful response.

    :param url: URL to poll
    :param wait_time: Maximum time to wait in seconds (default: 300)
    :param request_timeout: Timeout for each HTTP request in seconds (default: 10)
    """
    end_of_wait = time.time() + wait_time
    attempt = 0
    LOG.info("Waiting for %s to become healthy (timeout: %ds)", url, wait_time)

    while time.time() < end_of_wait:
        attempt += 1
        remaining = int(end_of_wait - time.time())
        try:
            response = get(url, timeout=request_timeout)
            assert (
                response.status_code == 200
            ), f"Expected 200, got {response.status_code}"
            assert (
                response.text == "<html><body><h1>It works!</h1></body></html>\n"
            ), f"Unexpected response body"
            LOG.info("URL %s is healthy after %d attempts", url, attempt)
            return

        except RequestException as err:
            # Connection errors, timeouts, etc. - retry
            LOG.debug(
                "Attempt %d: Connection error: %s (%ds remaining)",
                attempt,
                type(err).__name__,
                remaining,
            )
            time.sleep(1)

        except AssertionError as err:
            # Got a response but not the expected one - retry
            LOG.debug("Attempt %d: %s (%ds remaining)", attempt, err, remaining)
            time.sleep(1)

        # Log progress every 30 seconds
        if attempt % 30 == 0:
            LOG.info(
                "Still waiting for %s (%ds remaining, %d attempts)",
                url,
                remaining,
                attempt,
            )

    raise RuntimeError(
        f"{url} didn't become healthy after {wait_time} seconds ({attempt} attempts)"
    )


def update_terraform_tf(terraform_module_dir, aws_provider_version):
    terraform_tf_path = osp.join(terraform_module_dir, "terraform.tf")
    with open(terraform_tf_path, "w") as fp:
        fp.write(dedent(f"""
                terraform {{
                  required_providers {{
                    aws = {{
                      source  = "hashicorp/aws"
                      version = "{aws_provider_version}"
                    }}
                  }}
                }}
                """))


def cleanup_dot_terraform(terraform_module_dir):
    state_files = [
        osp.join(terraform_module_dir, ".terraform"),
        osp.join(terraform_module_dir, ".terraform.lock.hcl"),
    ]

    for state_file in state_files:
        try:
            if osp.isdir(state_file):
                shutil.rmtree(state_file)
            elif osp.isfile(state_file):
                remove(state_file)
        except FileNotFoundError:
            # File was already removed by another process
            pass


# Tag that the service_network fixture (and all InfraHouse fixtures) stamp on
# every resource they create, via provider default_tags. Resources lacking it
# were injected by AWS (e.g. GuardDuty), not by Terraform.
FIXTURE_TAG_KEY = "created_by_fixture"


def _is_aws_injected(resource: dict) -> bool:
    """
    Return True if an AWS resource was created by AWS rather than the fixture.

    Fixture-created resources carry the ``created_by_fixture`` tag (set via the
    provider's default_tags). AWS-injected resources (e.g. GuardDuty runtime
    monitoring) do not.

    :param resource: A describe_* entry that has a ``Tags`` list (VPC endpoint,
        security group, ...).
    :return: True if the resource is not fixture-owned.
    """
    return not any(tag["Key"] == FIXTURE_TAG_KEY for tag in resource.get("Tags", []))


@pytest.fixture(scope="session", autouse=True)
def purge_aws_injected_vpc_resources(
    service_network: dict,
    boto3_session: Session,
    aws_region: str,
    keep_after: bool,
):
    """
    Delete AWS-injected resources that Terraform does not own before the
    service_network VPC is torn down.

    AWS GuardDuty runtime monitoring instruments the test VPC by auto-creating
    BOTH an interface endpoint (``com.amazonaws.<region>.guardduty-data``) AND a
    managed security group (``GuardDutyManagedSecurityGroup-<vpc>``). Terraform
    has no knowledge of either, so the session-scoped ``service_network``
    fixture's ``terraform destroy`` hangs/fails: the endpoint's ENIs block
    subnet deletion, and the leftover non-default security group blocks
    ``DeleteVpc`` -- both with ``DependencyViolation``.

    These are identified by the absence of the ``created_by_fixture`` tag the
    fixture stamps on everything it creates. This fixture depends on
    ``service_network``, so its finalizer runs *before* that destroy. It removes
    the endpoint first (waiting for its ENIs to clear), then the security group
    (which the ENIs referenced). It is a no-op in accounts where no such
    resources exist (e.g. the CI account).

    :param service_network: Fixture providing the test VPC outputs.
    :param boto3_session: Boto3 session for AWS API calls.
    :param aws_region: AWS region under test.
    :param keep_after: If True, infrastructure is kept, so do nothing.
    """
    yield

    if keep_after:
        return

    vpc_id = service_network["vpc_id"]["value"]
    ec2_client = boto3_session.client("ec2", region_name=aws_region)
    vpc_filter = [{"Name": "vpc-id", "Values": [vpc_id]}]

    # 1. Endpoints. Their ENIs must clear before the security group can go.
    injected_endpoints = [
        endpoint["VpcEndpointId"]
        for endpoint in ec2_client.describe_vpc_endpoints(Filters=vpc_filter)[
            "VpcEndpoints"
        ]
        if _is_aws_injected(endpoint)
    ]
    if injected_endpoints:
        LOG.info("Deleting AWS-injected VPC endpoints: %s", injected_endpoints)
        ec2_client.delete_vpc_endpoints(VpcEndpointIds=injected_endpoints)
        try:
            with timeout(300):
                while any(
                    _is_aws_injected(endpoint) and endpoint["State"] != "deleted"
                    for endpoint in ec2_client.describe_vpc_endpoints(
                        Filters=vpc_filter
                    )["VpcEndpoints"]
                ):
                    time.sleep(5)
            LOG.info("AWS-injected VPC endpoints removed")
        except TimeoutError:
            LOG.warning(
                "Timed out waiting for VPC endpoints to delete: %s",
                injected_endpoints,
            )

    # 2. Non-default security groups (e.g. GuardDutyManagedSecurityGroup). A
    #    leftover non-default SG makes DeleteVpc fail with DependencyViolation.
    injected_sgs = [
        group["GroupId"]
        for group in ec2_client.describe_security_groups(Filters=vpc_filter)[
            "SecurityGroups"
        ]
        if group["GroupName"] != "default" and _is_aws_injected(group)
    ]
    for group_id in injected_sgs:
        LOG.info("Deleting AWS-injected security group: %s", group_id)
        try:
            with timeout(120):
                while True:
                    try:
                        ec2_client.delete_security_group(GroupId=group_id)
                        break
                    except ClientError as err:
                        # ENIs from the just-deleted endpoint may still be
                        # detaching and referencing this group; retry until gone.
                        if err.response["Error"]["Code"] == "DependencyViolation":
                            time.sleep(5)
                            continue
                        raise
        except TimeoutError:
            LOG.warning("Timed out deleting security group: %s", group_id)
