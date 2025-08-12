terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# Use existing hosted zone for root domain
data "aws_route53_zone" "primary" {
  name         = var.root_domain
  private_zone = false
}

# S3 bucket for subdomain site
resource "aws_s3_bucket" "site" {
  bucket        = local.full_domain
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${local.full_domain}"
}

# Fixed S3 bucket policy for OAI
resource "aws_s3_bucket_policy" "site_policy" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOAI"
        Effect = "Allow"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.oai.iam_arn
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.site.arn}/*"
      }
    ]
  })
}

# ACM certificate in us-east-1 for the subdomain with email validation
resource "aws_acm_certificate" "cert" {
  domain_name               = var.root_domain  # Request cert for root domain
  subject_alternative_names = [local.full_domain]  # Add subdomain as SAN
  validation_method         = "EMAIL"

  validation_option {
    domain_name       = var.root_domain
    validation_domain = var.root_domain
  }

  lifecycle {
    create_before_destroy = true
  }
}

# CloudFront distribution for subdomain
resource "aws_cloudfront_distribution" "cdn" {
  enabled = true
  aliases = []  # We'll add the alias after certificate validation

  origin {
    origin_id   = "s3-${aws_s3_bucket.site.bucket}"
    domain_name = aws_s3_bucket.site.bucket_regional_domain_name

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.site.bucket}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  viewer_certificate {
    cloudfront_default_certificate = true  # Use default cert initially
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}