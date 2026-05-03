#!/usr/bin/env python3
"""
ec2_monitor.py - AWS EC2 CPU Utilization Monitor
Queries EC2 instances and CloudWatch metrics, generates JSON report.

Usage:
    python ec2_monitor.py --region us-east-1 --threshold 80 --output report.json
    python ec2_monitor.py --region us-east-1 --config config.json
"""

import argparse
import json
import logging
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

import boto3
from botocore.exceptions import BotoCoreError, ClientError, NoCredentialsError


# ─── Logging setup ────────────────────────────────────────────────────────────

def setup_logging(level: str = "INFO") -> logging.Logger:
    """Configure structured logging with timestamps."""
    logging.basicConfig(
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
        level=getattr(logging, level.upper(), logging.INFO),
        stream=sys.stderr,
    )
    return logging.getLogger("ec2_monitor")


logger = setup_logging()


# ─── AWS helpers ──────────────────────────────────────────────────────────────

def get_ec2_client(region: str) -> Any:
    """Create a boto3 EC2 client for the given region."""
    try:
        return boto3.client("ec2", region_name=region)
    except (BotoCoreError, NoCredentialsError) as exc:
        logger.error("Failed to create EC2 client for region %s: %s", region, exc)
        raise


def get_cloudwatch_client(region: str) -> Any:
    """Create a boto3 CloudWatch client for the given region."""
    try:
        return boto3.client("cloudwatch", region_name=region)
    except (BotoCoreError, NoCredentialsError) as exc:
        logger.error("Failed to create CloudWatch client for region %s: %s", region, exc)
        raise


# ─── EC2 instance listing ──────────────────────────────────────────────────────

def get_running_instances(ec2_client: Any, tag_filters: list[dict] | None = None) -> list[dict]:
    """
    Return all running EC2 instances in the account/region.
    Optionally filter by tags from config.
    """
    filters: list[dict] = [{"Name": "instance-state-name", "Values": ["running"]}]

    if tag_filters:
        for tag in tag_filters:
            filters.append({
                "Name": f"tag:{tag['key']}",
                "Values": tag["values"],
            })

    instances: list[dict] = []

    try:
        paginator = ec2_client.get_paginator("describe_instances")
        for page in paginator.paginate(Filters=filters):
            for reservation in page["Reservations"]:
                for inst in reservation["Instances"]:
                    # Extract the Name tag value (falls back to empty string)
                    name = next(
                        (t["Value"] for t in inst.get("Tags", []) if t["Key"] == "Name"),
                        "",
                    )
                    instances.append({
                        "instance_id": inst["InstanceId"],
                        "name": name,
                        "instance_type": inst["InstanceType"],
                        "private_ip": inst.get("PrivateIpAddress", "N/A"),
                        "public_ip": inst.get("PublicIpAddress", "N/A"),
                        "launch_time": inst["LaunchTime"].isoformat(),
                        "availability_zone": inst["Placement"]["AvailabilityZone"],
                        "tags": {t["Key"]: t["Value"] for t in inst.get("Tags", [])},
                    })

        logger.info("Found %d running instances in region", len(instances))
        return instances

    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        logger.error("EC2 API error [%s]: %s", error_code, exc.response["Error"]["Message"])
        raise


# ─── CloudWatch metrics ────────────────────────────────────────────────────────

def get_cpu_metrics(
    cw_client: Any,
    instance_id: str,
    hours: int = 1,
    period_seconds: int = 300,
) -> dict[str, float | None]:
    """
    Fetch CPUUtilization from CloudWatch for the last `hours` hours.
    Returns avg, min, max CPU utilization (or None if no data).
    """
    end_time = datetime.now(timezone.utc)
    start_time = end_time - timedelta(hours=hours)

    try:
        response = cw_client.get_metric_statistics(
            Namespace="AWS/EC2",
            MetricName="CPUUtilization",
            Dimensions=[{"Name": "InstanceId", "Value": instance_id}],
            StartTime=start_time,
            EndTime=end_time,
            Period=period_seconds,
            Statistics=["Average", "Minimum", "Maximum"],
            Unit="Percent",
        )

        datapoints = response.get("Datapoints", [])

        if not datapoints:
            logger.warning("No CloudWatch CPU datapoints for instance %s", instance_id)
            return {"avg_cpu": None, "min_cpu": None, "max_cpu": None, "datapoint_count": 0}

        avg_values = [dp["Average"] for dp in datapoints]
        min_values = [dp["Minimum"] for dp in datapoints]
        max_values = [dp["Maximum"] for dp in datapoints]

        return {
            "avg_cpu": round(sum(avg_values) / len(avg_values), 2),
            "min_cpu": round(min(min_values), 2),
            "max_cpu": round(max(max_values), 2),
            "datapoint_count": len(datapoints),
        }

    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]
        logger.error(
            "CloudWatch error for instance %s [%s]: %s",
            instance_id,
            error_code,
            exc.response["Error"]["Message"],
        )
        return {"avg_cpu": None, "min_cpu": None, "max_cpu": None, "datapoint_count": 0}


# ─── Config loading ────────────────────────────────────────────────────────────

def load_config(config_path: str) -> dict:
    """Load and validate the JSON config file."""
    path = Path(config_path)

    if not path.exists():
        logger.error("Config file not found: %s", config_path)
        raise FileNotFoundError(f"Config file not found: {config_path}")

    try:
        with path.open() as fh:
            config = json.load(fh)
        logger.info("Loaded config from %s", config_path)
        return config
    except json.JSONDecodeError as exc:
        logger.error("Invalid JSON in config file %s: %s", config_path, exc)
        raise


# ─── Report generation ─────────────────────────────────────────────────────────

def build_report(
    region: str,
    instances: list[dict],
    metrics_map: dict[str, dict],
    threshold: float,
) -> dict:
    """Assemble the final JSON report structure."""
    instance_reports = []
    high_cpu_count = 0

    for inst in instances:
        iid = inst["instance_id"]
        metrics = metrics_map.get(iid, {})
        avg_cpu = metrics.get("avg_cpu")
        is_high_cpu = avg_cpu is not None and avg_cpu > threshold

        if is_high_cpu:
            high_cpu_count += 1
            logger.warning(
                "HIGH CPU ALERT: Instance %s (%s) avg CPU %.1f%% exceeds threshold %.1f%%",
                iid, inst["name"], avg_cpu, threshold,
            )

        instance_reports.append({
            "instance_id": iid,
            "name": inst["name"],
            "instance_type": inst["instance_type"],
            "availability_zone": inst["availability_zone"],
            "private_ip": inst["private_ip"],
            "public_ip": inst["public_ip"],
            "launch_time": inst["launch_time"],
            "cpu_utilization": {
                "avg_percent": avg_cpu,
                "min_percent": metrics.get("min_cpu"),
                "max_percent": metrics.get("max_cpu"),
                "datapoints_collected": metrics.get("datapoint_count", 0),
                "lookback_hours": 1,
                "period_seconds": 300,
            },
            "alert": {
                "high_cpu": is_high_cpu,
                "threshold_percent": threshold,
            },
            "tags": inst.get("tags", {}),
        })

    return {
        "report_metadata": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "region": region,
            "threshold_percent": threshold,
            "total_instances": len(instances),
            "high_cpu_instances": high_cpu_count,
        },
        "instances": instance_reports,
    }


def write_report(report: dict, output_path: str) -> None:
    """Write the JSON report to disk."""
    path = Path(output_path)
    path.parent.mkdir(parents=True, exist_ok=True)

    with path.open("w") as fh:
        json.dump(report, fh, indent=2, default=str)

    logger.info("Report written to %s", output_path)


# ─── CLI ──────────────────────────────────────────────────────────────────────

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Monitor EC2 CPU utilization via CloudWatch and generate a JSON report.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Single region with defaults:
  python ec2_monitor.py --region us-east-1

  # Custom threshold and output file:
  python ec2_monitor.py --region ap-south-1 --threshold 70 --output /tmp/report.json

  # Load regions and threshold from config:
  python ec2_monitor.py --config config.json

  # Verbose logging:
  python ec2_monitor.py --region us-east-1 --log-level DEBUG
        """,
    )

    parser.add_argument(
        "--region",
        type=str,
        default="us-east-1",
        help="AWS region to query (default: us-east-1). Overridden by --config regions[0].",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=80.0,
        help="CPU %% threshold for HIGH CPU alert (default: 80.0)",
    )
    parser.add_argument(
        "--output",
        type=str,
        default="ec2_cpu_report.json",
        help="Output JSON file path (default: ec2_cpu_report.json)",
    )
    parser.add_argument(
        "--config",
        type=str,
        default=None,
        help="Path to config.json (overrides --region and --threshold if present)",
    )
    parser.add_argument(
        "--log-level",
        type=str,
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging verbosity (default: INFO)",
    )

    return parser.parse_args()


# ─── Main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    args = parse_args()

    # Reconfigure logging with user-requested level
    logging.getLogger().setLevel(getattr(logging, args.log_level))

    # Load config file if provided
    config: dict = {}
    if args.config:
        try:
            config = load_config(args.config)
        except (FileNotFoundError, json.JSONDecodeError) as exc:
            logger.error("Cannot load config: %s", exc)
            return 1

    # Config values override CLI defaults when present
    regions: list[str] = config.get("regions", [args.region])
    threshold: float = float(config.get("alert_threshold", args.threshold))
    output_path: str = args.output

    logger.info(
        "Starting EC2 CPU monitor | regions=%s threshold=%.1f%% output=%s",
        regions, threshold, output_path,
    )

    all_instance_reports: list[dict] = []

    for region in regions:
        logger.info("Processing region: %s", region)

        try:
            ec2 = get_ec2_client(region)
            cw = get_cloudwatch_client(region)
        except (BotoCoreError, NoCredentialsError) as exc:
            logger.error("Skipping region %s — cannot create clients: %s", region, exc)
            continue

        try:
            instances = get_running_instances(ec2)
        except ClientError as exc:
            logger.error("Skipping region %s — EC2 list failed: %s", region, exc)
            continue

        # Fetch CloudWatch metrics for every instance
        metrics_map: dict[str, dict] = {}
        for inst in instances:
            iid = inst["instance_id"]
            logger.debug("Fetching CPU metrics for %s (%s)", iid, inst["name"])
            metrics_map[iid] = get_cpu_metrics(cw, iid)

        region_report = build_report(region, instances, metrics_map, threshold)
        all_instance_reports.extend(region_report["instances"])

        # Log region summary
        meta = region_report["report_metadata"]
        logger.info(
            "Region %s: %d instances, %d high CPU alerts",
            region, meta["total_instances"], meta["high_cpu_instances"],
        )

    # Build combined multi-region report
    final_report = {
        "report_metadata": {
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "regions_queried": regions,
            "threshold_percent": threshold,
            "total_instances": len(all_instance_reports),
            "high_cpu_instances": sum(
                1 for i in all_instance_reports if i["alert"]["high_cpu"]
            ),
        },
        "instances": all_instance_reports,
    }

    try:
        write_report(final_report, output_path)
    except OSError as exc:
        logger.error("Failed to write report to %s: %s", output_path, exc)
        return 1

    # Exit code 2 if any instances exceeded threshold (useful for alerting pipelines)
    high_cpu = final_report["report_metadata"]["high_cpu_instances"]
    if high_cpu > 0:
        logger.warning("%d instance(s) exceeded CPU threshold of %.1f%%", high_cpu, threshold)
        return 2

    logger.info("All instances within CPU threshold. Report complete.")
    return 0


if __name__ == "__main__":
    sys.exit(main())