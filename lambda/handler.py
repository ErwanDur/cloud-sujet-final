import boto3
import os
from PIL import Image
from io import BytesIO
from pathlib import Path

s3 = boto3.client("s3")
DEST_BUCKET = os.environ["DEST_BUCKET"]


def lambda_handler(event, context):
    record = event["Records"][0]
    src_bucket = record["s3"]["bucket"]["name"]
    src_key = record["s3"]["object"]["key"]

    obj = s3.get_object(Bucket=src_bucket, Key=src_key)
    img = Image.open(BytesIO(obj["Body"].read())).convert("RGB")

    pdf_key = str(Path(src_key).with_suffix(".pdf"))
    buf = BytesIO()
    img.save(buf, format="PDF")
    buf.seek(0)

    s3.put_object(
        Bucket=DEST_BUCKET,
        Key=pdf_key,
        Body=buf,
        ContentType="application/pdf",
    )
