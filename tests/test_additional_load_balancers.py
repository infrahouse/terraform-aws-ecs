import json
from os import path as osp
from textwrap import dedent

import pytest

from tests.conftest import (
    LOG,
    TERRAFORM_ROOT_DIR,
    update_terraform_tf,
    cleanup_dot_terraform,
)


@pytest.mark.parametrize(
    "aws_provider_version",
    ["~> 5.56", "~> 6.0"],
    ids=["aws-5", "aws-6"],
)
def test_additional_load_balancers_validate(
    service_network,
    keep_after,
    test_role_arn,
    aws_region,
    subzone,
    aws_provider_version,
):
    """Test that the module accepts the additional_load_balancers variable.

    This is a validation-only test — it runs ``terraform validate``
    to confirm the configuration is syntactically and semantically
    correct without creating any real infrastructure.
    """
    subnet_public_ids = service_network["subnet_public_ids"]["value"]
    subnet_private_ids = service_network["subnet_private_ids"]["value"]
    zone_id = subzone["subzone_id"]["value"]

    terraform_module_dir = osp.join(
        TERRAFORM_ROOT_DIR, "httpd_additional_lb"
    )
    cleanup_dot_terraform(terraform_module_dir)
    update_terraform_tf(terraform_module_dir, aws_provider_version)
    with open(
        osp.join(terraform_module_dir, "terraform.tfvars"), "w"
    ) as fp:
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
                    """
                )
            )

    import subprocess

    # terraform init
    result = subprocess.run(
        ["terraform", "init", "-backend=false"],
        cwd=terraform_module_dir,
        capture_output=True,
        text=True,
        timeout=120,
    )
    LOG.info("terraform init stdout:\n%s", result.stdout)
    if result.returncode != 0:
        LOG.error(
            "terraform init stderr:\n%s", result.stderr
        )
    assert result.returncode == 0, (
        f"terraform init failed: {result.stderr}"
    )

    # terraform validate
    result = subprocess.run(
        ["terraform", "validate", "-json"],
        cwd=terraform_module_dir,
        capture_output=True,
        text=True,
        timeout=60,
    )
    LOG.info("terraform validate stdout:\n%s", result.stdout)
    validate_output = json.loads(result.stdout)
    assert validate_output["valid"], (
        f"terraform validate failed: "
        f"{json.dumps(validate_output, indent=2)}"
    )
    LOG.info(
        "✓ additional_load_balancers configuration "
        "validated successfully"
    )
