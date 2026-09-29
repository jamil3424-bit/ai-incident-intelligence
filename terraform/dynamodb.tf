resource "aws_dynamodb_table" "incident_records" {
  name         = "ai-incident-records"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "incident_id"

  attribute {
    name = "incident_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }
}
