import boto3
import os
from datetime import datetime, timezone
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

    # Renomme le fichier (horodatage) en plus de la conversion en PDF.
    src_path = Path(src_key)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    dest_key = str(src_path.with_name(f"{src_path.stem}-{timestamp}.pdf"))

    buf = BytesIO()
    img.save(buf, format="PDF")
    buf.seek(0)

    s3.put_object(
        Bucket=DEST_BUCKET,
        Key=dest_key,
        Body=buf,
        ContentType="application/pdf",
    )

    return {"source_key": src_key, "dest_key": dest_key}
