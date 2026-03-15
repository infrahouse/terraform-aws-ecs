"""
Lambda function that tags deployed ECR images after ECS reaches steady state.

Triggered by EventBridge SERVICE_STEADY_STATE events. For each container
image in the active task definition that comes from ECR, it adds a
``deployed-at-<timestamp>`` tag. This lets ECR lifecycle policies retain
recently deployed images as rollback candidates.
"""

import logging
import os
import re
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError
from infrahouse_core.logging import setup_logging

LOG = logging.getLogger(__name__)
setup_logging(LOG, debug=os.environ.get("LOG_LEVEL", "INFO").upper() == "DEBUG")

# Pattern: ACCOUNT.dkr.ecr.REGION.amazonaws.com/REPO:TAG
# or:      ACCOUNT.dkr.ecr.REGION.amazonaws.com/REPO@sha256:DIGEST
ECR_IMAGE_PATTERN = re.compile(
    r"^(?P<account>\d+)\.dkr\.ecr\.(?P<region>[a-z0-9-]+)"
    r"\.amazonaws\.com/(?P<repo>[^:@]+)"
    r"(?::(?P<tag>[^@]+)|@(?P<digest>sha256:[a-f0-9]+))$"
)


def lambda_handler(event: dict, context) -> dict:
    """Handle EventBridge ECS Service Action events.

    :param event: EventBridge event payload.
    :param context: Lambda context (unused).
    :return: Summary of tagged images.
    """
    LOG.debug("Received event: %s", event)

    cluster_name = os.environ["ECS_CLUSTER_NAME"]
    service_name = os.environ["ECS_SERVICE_NAME"]
    tag_prefix = os.environ.get("DEPLOYED_TAG_PREFIX", "deployed-at-")

    # Verify this event is for our cluster
    event_cluster_arn = event.get("detail", {}).get("clusterArn", "")
    cluster_match = f":cluster/{cluster_name}" in event_cluster_arn
    if not cluster_match:
        LOG.info(
            "Event cluster does not match %s, skipping.",
            cluster_name,
        )
        return {"tagged": []}

    ecs_client = boto3.client("ecs")

    # Get the active task definition from the service
    svc_response = ecs_client.describe_services(
        cluster=cluster_name,
        services=[service_name],
    )
    services = svc_response.get("services", [])
    if not services:
        LOG.error("Service %s not found in cluster %s", service_name, cluster_name)
        return {"tagged": []}

    task_def_arn = services[0]["taskDefinition"]
    LOG.info("Active task definition: %s", task_def_arn)

    # Get container images from the task definition
    td_response = ecs_client.describe_task_definition(taskDefinition=task_def_arn)
    container_defs = td_response["taskDefinition"]["containerDefinitions"]

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    deployed_tag = f"{tag_prefix}{timestamp}"
    tagged = []

    for container in container_defs:
        image_uri = container["image"]
        LOG.info(
            "Container %s uses image %s",
            container["name"],
            image_uri,
        )

        match = ECR_IMAGE_PATTERN.match(image_uri)
        if not match:
            LOG.info("Not an ECR image, skipping: %s", image_uri)
            continue

        result = _tag_ecr_image(match, deployed_tag)
        if result:
            tagged.append(result)

    LOG.info("Tagged %d image(s): %s", len(tagged), tagged)
    return {"tagged": tagged}


def _tag_ecr_image(match: re.Match, deployed_tag: str) -> str:
    """Tag a single ECR image with the deployed tag.

    :param match: Regex match object with account, region, repo,
        tag, and digest groups.
    :param deployed_tag: Tag string to apply.
    :return: The full image URI that was tagged, or empty string
        on failure.
    """
    account = match.group("account")
    region = match.group("region")
    repo_name = match.group("repo")
    image_tag = match.group("tag")
    image_digest = match.group("digest")

    if not image_tag and not image_digest:
        LOG.warning("No tag or digest found for %s/%s", account, repo_name)
        return ""

    ecr_client = boto3.client("ecr", region_name=region)

    try:
        image_id = {}
        if image_digest:
            image_id["imageDigest"] = image_digest
        else:
            image_id["imageTag"] = image_tag

        batch_response = ecr_client.batch_get_image(
            repositoryName=repo_name,
            imageIds=[image_id],
        )
        images = batch_response.get("images", [])
        if not images:
            LOG.warning("Image manifest not found in %s", repo_name)
            return ""

        manifest = images[0]["imageManifest"]
        manifest_media_type = images[0].get("imageManifestMediaType", "")

        # Apply the deployed-at tag
        put_kwargs = {
            "repositoryName": repo_name,
            "imageManifest": manifest,
            "imageTag": deployed_tag,
        }
        if manifest_media_type:
            put_kwargs["imageManifestMediaType"] = manifest_media_type

        ecr_client.put_image(**put_kwargs)

        tagged_uri = (
            f"{account}.dkr.ecr.{region}.amazonaws.com/{repo_name}:{deployed_tag}"
        )
        LOG.info("Tagged image: %s", tagged_uri)
        return tagged_uri

    except ClientError as err:
        if err.response["Error"]["Code"] == "ImageAlreadyExistsException":
            LOG.info(
                "Tag %s already exists on %s, skipping.",
                deployed_tag,
                repo_name,
            )
            return (
                f"{account}.dkr.ecr.{region}.amazonaws.com/{repo_name}:{deployed_tag}"
            )
        LOG.warning(
            "Failed to tag image in %s/%s: %s",
            account,
            repo_name,
            err,
        )
        return ""
