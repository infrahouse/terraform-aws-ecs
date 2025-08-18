import time
import logging

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
