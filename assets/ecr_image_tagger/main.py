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

from infrahouse_core.aws import ECRRepository, ECSService, ECSTaskDefinition
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
    tag_prefix = os.environ["DEPLOYED_TAG_PREFIX"]

    # Verify this event is for our cluster
    event_cluster_arn = event["detail"]["clusterArn"]
    cluster_match = f":cluster/{cluster_name}" in event_cluster_arn
    if not cluster_match:
        LOG.info(
            "Event cluster does not match %s, skipping.",
            cluster_name,
        )
        return {"tagged": []}

    service = ECSService(cluster_name, service_name)
    task_def_arn = service.task_definition_arn
    LOG.info("Active task definition: %s", task_def_arn)

    task_def = ECSTaskDefinition(task_def_arn)

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    deployed_tag = f"{tag_prefix}{timestamp}"
    tagged = []

    for image_uri in task_def.container_images:
        LOG.info("Processing image %s", image_uri)

        match = ECR_IMAGE_PATTERN.match(image_uri)
        if not match:
            LOG.info("Not an ECR image, skipping: %s", image_uri)
            continue

        result = _tag_ecr_image(match, deployed_tag, tag_prefix)
        if result:
            tagged.append(result)

    LOG.info("Tagged %d image(s): %s", len(tagged), tagged)
    return {"tagged": tagged}


def _tag_ecr_image(
    match: re.Match, deployed_tag: str, tag_prefix: str
) -> str | None:
    """Tag a single ECR image with the deployed tag.

    Skips tagging if the image already has a tag with the given prefix —
    this prevents duplicate tags from periodic SERVICE_STEADY_STATE events
    that fire without an actual deployment.

    :param match: Regex match object with account, region, repo,
        tag, and digest groups.
    :param deployed_tag: Tag string to apply.
    :param tag_prefix: Prefix to check for existing deployed tags.
    :return: The full image URI that was tagged, or None if skipped.
    :raises ValueError: If the image has neither tag nor digest,
        or if the image does not exist in the repository.
    """
    account = match.group("account")
    region = match.group("region")
    repo_name = match.group("repo")
    image_tag = match.group("tag")
    image_digest = match.group("digest")

    if not image_tag and not image_digest:
        raise ValueError(
            f"No tag or digest found for {account}/{repo_name}"
        )

    repo = ECRRepository(repo_name, region=region)
    ecr_image = repo.get_image(tag=image_tag, digest=image_digest)

    if not ecr_image.exists:
        raise ValueError(
            f"Image not found in {repo_name}: "
            f"{image_tag or image_digest}"
        )

    # Skip if image already has a deployed-at- tag
    for existing_tag in ecr_image.tags:
        if existing_tag.startswith(tag_prefix):
            LOG.info(
                "Image %s/%s already has tag %s, skipping.",
                repo_name,
                image_tag or image_digest,
                existing_tag,
            )
            return None

    ecr_image.tag_image(deployed_tag)

    tagged_uri = (
        f"{account}.dkr.ecr.{region}.amazonaws.com"
        f"/{repo_name}:{deployed_tag}"
    )
    LOG.info("Tagged image: %s", tagged_uri)
    return tagged_uri
