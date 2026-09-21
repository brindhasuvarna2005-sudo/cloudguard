"""
CloudGuard - Dashboard API Lambda (Phase 7)

Read-only endpoint that scans the audit_log DynamoDB table and returns
recent findings as JSON, for the static dashboard to display.
"""

import json
import os
import boto3
from boto3.dynamodb.conditions import Attr

AUDIT_TABLE = os.environ["AUDIT_TABLE"]

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(AUDIT_TABLE)

CORS_HEADERS = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
    "Content-Type": "application/json",
}


def lambda_handler(event, context):
    try:
        resp = table.scan()
        items = resp.get("Items", [])

        # Sort newest first
        items.sort(key=lambda x: x.get("timestamp", ""), reverse=True)

        return {
            "statusCode": 200,
            "headers": CORS_HEADERS,
            "body": json.dumps({"findings": items[:100]}),
        }
    except Exception as e:
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": str(e)}),
        }