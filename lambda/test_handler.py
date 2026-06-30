import os
import re
from io import BytesIO
from unittest.mock import MagicMock, patch

os.environ["DEST_BUCKET"] = "test-dest-bucket"


def _make_image(fmt="JPEG"):
    from PIL import Image
    img = Image.new("RGB", (10, 10), color="red")
    buf = BytesIO()
    img.save(buf, format=fmt)
    return buf.getvalue()


def _event(bucket, key):
    return {"Records": [{"s3": {"bucket": {"name": bucket}, "object": {"key": key}}}]}


@patch("handler.s3")
def test_jpeg_converted_and_renamed_to_pdf(mock_s3):
    mock_s3.get_object.return_value = {"Body": MagicMock(read=lambda: _make_image("JPEG"))}

    from handler import lambda_handler
    result = lambda_handler(_event("src-bucket", "photo.jpg"), None)

    mock_s3.put_object.assert_called_once()
    kwargs = mock_s3.put_object.call_args.kwargs
    assert kwargs["Bucket"] == "test-dest-bucket"
    assert kwargs["ContentType"] == "application/pdf"
    # renommé avec horodatage : photo-YYYYMMDD-HHMMSS.pdf
    assert re.fullmatch(r"photo-\d{8}-\d{6}\.pdf", kwargs["Key"])
    assert result["dest_key"] == kwargs["Key"]
    assert result["source_key"] == "photo.jpg"


@patch("handler.s3")
def test_png_rgba_converted_and_renamed_to_pdf(mock_s3):
    from PIL import Image
    img = Image.new("RGBA", (10, 10), color=(255, 0, 0, 128))
    buf = BytesIO()
    img.save(buf, format="PNG")
    mock_s3.get_object.return_value = {"Body": MagicMock(read=lambda: buf.getvalue())}

    from handler import lambda_handler
    lambda_handler(_event("src-bucket", "image.png"), None)

    kwargs = mock_s3.put_object.call_args.kwargs
    assert re.fullmatch(r"image-\d{8}-\d{6}\.pdf", kwargs["Key"])


@patch("handler.s3")
def test_rename_preserves_source_folder(mock_s3):
    mock_s3.get_object.return_value = {"Body": MagicMock(read=lambda: _make_image())}

    from handler import lambda_handler
    lambda_handler(_event("src-bucket", "folder/shot.jpeg"), None)

    kwargs = mock_s3.put_object.call_args.kwargs
    assert re.fullmatch(r"folder/shot-\d{8}-\d{6}\.pdf", kwargs["Key"])
