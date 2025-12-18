resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "media" {
  bucket = "wordpress-media-bucket-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "wordpress-media-bucket"
  }
}

resource "aws_s3_bucket_ownership_controls" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "media" {
  depends_on = [aws_s3_bucket_ownership_controls.media]

  bucket = aws_s3_bucket.media.id
  acl    = "private"
}
