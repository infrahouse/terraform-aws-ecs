import shutil
import time
import logging
from os import path as osp, remove
from textwrap import dedent

from infrahouse_core.logging import setup_logging
from requests import get
from requests.exceptions import RequestException

DEFAULT_PROGRESS_INTERVAL = 10

LOG = logging.getLogger(__name__)
TERRAFORM_ROOT_DIR = "test_data"

setup_logging(LOG, debug=True)


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
        fp.write(
            dedent(
                f"""
                terraform {{
                  required_providers {{
                    aws = {{
                      source  = "hashicorp/aws"
                      version = "{aws_provider_version}"
                    }}
                  }}
                }}
                """
            )
        )


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
