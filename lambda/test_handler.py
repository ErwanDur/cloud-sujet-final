import os
from io import BytesIO
from unittest.mock import MagicMock, patch

import pytest

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
def test_jpeg_converted_to_pdf(mock_s3):
    mock_s3.get_object.return_value = {"Body": MagicMock(read=lambda: _make_image("JPEG"))}

    from handler import lambda_handler
    lambda_handler(_event("src-bucket", "photo.jpg"), None)

    mock_s3.put_object.assert_called_once()
    kwargs = mock_s3.put_object.call_args.kwargs
    assert kwargs["Bucket"] == "test-dest-bucket"
    assert kwargs["Key"] == "photo.pdf"
    assert kwargs["ContentType"] == "application/pdf"


@patch("handler.s3")
def test_png_rgba_converted_to_pdf(mock_s3):
    from PIL import Image
    img = Image.new("RGBA", (10, 10), color=(255, 0, 0, 128))
    buf = BytesIO()
    img.save(buf, format="PNG")
    mock_s3.get_object.return_value = {"Body": MagicMock(read=lambda: buf.getvalue())}

    from handler import lambda_handler
    lambda_handler(_event("src-bucket", "image.png"), None)

    kwargs = mock_s3.put_object.call_args.kwargs
    assert kwargs["Key"] == "image.pdf"


@patch("handler.s3")
def test_output_key_strips_extension(mock_s3):
    mock_s3.get_object.return_value = {"Body": MagicMock(read=lambda: _make_image())}

    from handler import lambda_handler
    lambda_handler(_event("src-bucket", "folder/shot.jpeg"), None)

    kwargs = mock_s3.put_object.call_args.kwargs
    assert kwargs["Key"] == "folder/shot.pdf"
