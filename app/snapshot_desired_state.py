"""
Phase 3 - Desired-state snapshot
"""

import json
import subprocess
import sys
import boto3

STATE_BUCKET = "cloudguard-tfstate-042186225776"
STATE_KEY = "cloudguard/app/desired_state.json"
REGION = "ap-south-1"


def get_terraform_state():
    result = subprocess.run(
        ["terraform", "show", "-json"],
        capture_output=True,
        text=True,
        check=True,
    )
    return json.loads(result.stdout)


def extract_desired_state(tf_state):
    desired = {}
    resources = tf_state.get("values", {}).get("root_module", {}).get("resources", [])

    for res in resources:
        values = res["values"]
        rtype = res["type"]

        if rtype == "aws_s3_bucket":
            desired["s3_bucket"] = {
                "name": values.get("bucket"),
                "tags": values.get("tags", {}),
            }
        elif rtype == "aws_dynamodb_table":
            desired["dynamodb_table"] = {
                "name": values.get("name"),
                "billing_mode": values.get("billing_mode"),
                "hash_key": values.get("hash_key"),
                "tags": values.get("tags", {}),
            }
        elif rtype == "aws_iam_role":
            desired["iam_role"] = {
                "name": values.get("name"),
                "tags": values.get("tags", {}),
            }
        elif rtype == "aws_security_group":
            def normalize_rules(rules):
                normalized = []
                for r in rules or []:
                    normalized.append({
                        "from_port": r.get("from_port"),
                        "to_port": r.get("to_port"),
                        "protocol": r.get("protocol"),
                        "cidr_blocks": sorted(r.get("cidr_blocks", [])),
                    })
                return normalized

            desired["security_group"] = {
                "name": values.get("name"),
                "ingress": normalize_rules(values.get("ingress")),
                "egress": normalize_rules(values.get("egress")),
                "tags": values.get("tags", {}),
            }

    return desired


def upload_to_s3(data):
    s3 = boto3.client("s3", region_name=REGION)
    body = json.dumps(data, indent=2)
    s3.put_object(
        Bucket=STATE_BUCKET,
        Key=STATE_KEY,
        Body=body.encode("utf-8"),
        ContentType="application/json",
    )
    print(f"Uploaded desired_state.json to s3://{STATE_BUCKET}/{STATE_KEY}")


def main():
    print("Reading Terraform state (terraform show -json)...")
    try:
        tf_state = get_terraform_state()
    except subprocess.CalledProcessError as e:
        print("ERROR: terraform show failed.")
        print(e.stderr)
        sys.exit(1)

    print("Extracting fields relevant to drift detection...")
    desired = extract_desired_state(tf_state)
    print(json.dumps(desired, indent=2))

    print("Uploading to S3...")
    upload_to_s3(desired)
    print("Done.")


if __name__ == "__main__":
    main()