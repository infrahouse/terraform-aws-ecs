import time
import logging
from os import path as osp
from textwrap import dedent

from infrahouse_core.logging import setup_logging
from requests import get

DEFAULT_PROGRESS_INTERVAL = 10

LOG = logging.getLogger(__name__)
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


def update_terraform_tf(terraform_module_dir, aws_provider_version):
    terraform_tf_path = osp.join(terraform_module_dir, "terraform.tf")
    with open(terraform_tf_path, "w") as fp:
        fp.write(
            dedent(
                f"""terraform {{
  //noinspection HILUnresolvedReference
  required_providers {{
    aws = {{
      source  = "hashicorp/aws"
      version = "{aws_provider_version}"
    }}
    cloudinit = {{
      source  = "hashicorp/cloudinit"
      version = "~> 2.3"
    }}
  }}
}}
"""
            )
        )
