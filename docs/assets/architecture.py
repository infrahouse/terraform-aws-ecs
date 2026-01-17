#!/usr/bin/env python3
"""
Generate architecture diagram for terraform-aws-ecs module.

This diagram is generated from analysis of the actual Terraform code.

Requirements:
    pip install diagrams

Usage:
    python architecture.py

Output:
    architecture.png (in current directory)
"""

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import ECS, EC2
from diagrams.aws.network import ALB, Route53
from diagrams.aws.management import Cloudwatch
from diagrams.aws.security import ACM
from diagrams.aws.general import Users

fontsize = "16"

# Match MkDocs Material theme fonts (Roboto)
# Increase sizes for better readability
graph_attr = {
    "splines": "spline",
    "nodesep": "1.5",
    "ranksep": "1.5",
    "fontsize": fontsize,
    "fontname": "Roboto",
    "dpi": "200",
}

node_attr = {
    "fontname": "Roboto",
    "fontsize": fontsize,
}

edge_attr = {
    "fontname": "Roboto",
    "fontsize": fontsize,
}

with Diagram(
    "ECS Architecture",
    filename="architecture",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
    node_attr=node_attr,
    edge_attr=edge_attr,
    outformat="png",
):
    users = Users("\nUsers")
    dns = Route53("\nRoute 53\nDNS")
    cert = ACM("\nACM\nCertificate")

    with Cluster("VPC"):
        with Cluster("Public Subnets"):
            # Note: ALB can be NLB for generic TCP services (lb_type = "nlb")
            lb = ALB("\nLoad Balancer\n(ALB or NLB)")

        with Cluster("Private Subnets"):
            with Cluster("Auto Scaling Group"):
                ec2_instances = [
                    EC2("\nEC2 Instance\n(ECS Agent)"),
                    EC2("\nEC2 Instance\n(ECS Agent)"),
                ]

            with Cluster("ECS Cluster"):
                ecs_tasks = ECS("\nECS Tasks\n(Containers)")

    cloudwatch = Cloudwatch("\nCloudWatch\nLogs & Metrics\n(ISO 27001)")

    # ============ CONNECTIONS ============

    # User traffic flow
    users >> dns >> lb
    cert - Edge(style="dashed") - lb
    lb >> ec2_instances
    ec2_instances[0] - ecs_tasks
    ec2_instances[1] - ecs_tasks

    # CloudWatch connections (dashed for monitoring)
    ecs_tasks >> Edge(style="dashed", label="logs") >> cloudwatch
    ec2_instances[0] >> Edge(style="dashed", label="metrics") >> cloudwatch