output "key_arns" {
  description = "Map of key alias names to their ARNs"
  value = {
    for alias, key in aws_kms_key.keys : alias => key.arn
  }
}

output "key_ids" {
  description = "Map of key alias names to their IDs"
  value = {
    for alias, key in aws_kms_key.keys : alias => key.key_id
  }
}
