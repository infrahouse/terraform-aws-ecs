import json
from os import path as osp
from pprint import pformat
from textwrap import dedent

import pytest
from infrahouse_toolkit.terraform import terraform_apply

from tests.conftest import (
    LOG,
    TRACE_TERRAFORM,
    DESTROY_AFTER,
    TEST_ZONE,
    TEST_ROLE_ARN,
    REGION,
)


@pytest.mark.flaky(reruns=0, reruns_delay=30)
@pytest.mark.timeout(1800)
def test_module(ec2_client, route53_client):
    terraform_dir = "test_data/test_module"

    with open(osp.join(terraform_dir, "terraform.tfvars"), "w") as fp:
        fp.write(
            dedent(
                f"""
                role_arn = "{TEST_ROLE_ARN}"
                task_role_arn = "{TEST_ROLE_ARN}"
                test_zone = "{TEST_ZONE}"
                region = "{REGION}"
                """
            )
        )

    with terraform_apply(
        terraform_dir,
        destroy_after=DESTROY_AFTER,
        json_output=True,
        enable_trace=TRACE_TERRAFORM,
    ) as tf_output:
        LOG.info(json.dumps(tf_output, indent=4))
