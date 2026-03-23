#!/bin/bash
# DSQL IAM token entrypoint wrapper for Java services
# Generates DSQL auth token if DB_HOST is a DSQL endpoint

if [[ "${DB_HOST}" == *".dsql."* ]]; then
  echo "Generating DSQL IAM auth token for ${DB_HOST}..."
  export DB_PASSWORD=$(aws dsql generate-db-connect-admin-auth-token \
    --hostname "${DB_HOST}" --region "${AWS_REGION:-us-east-1}" 2>/dev/null)
  if [ -z "$DB_PASSWORD" ]; then
    echo "WARNING: Failed to generate DSQL token, proceeding without DB"
  else
    echo "DSQL token generated successfully"
  fi
  export DB_USER="admin"
  export DB_NAME="postgres"
fi

exec java -jar /app/app.jar "$@"
