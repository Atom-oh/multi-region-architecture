"""Configuration management using Pydantic settings."""

from pydantic_settings import BaseSettings


class ServiceConfig(BaseSettings):
    service_name: str = "unknown"
    port: int = 8080
    aws_region: str = "us-east-1"
    region_role: str = "PRIMARY"  # PRIMARY or SECONDARY
    primary_host: str = ""
    db_host: str = "localhost"
    db_port: int = 27017
    db_name: str = ""
    db_user: str = "mall"
    db_password: str = ""
    cache_host: str = "localhost"
    cache_port: int = 6379
    kafka_brokers: str = "localhost:9092"
    opensearch_endpoint: str = "http://localhost:9200"
    documentdb_host: str = "localhost"
    documentdb_port: int = 27017
    s3_bucket: str = ""
    log_level: str = "info"

    class Config:
        env_prefix = ""
        case_sensitive = False

    @property
    def is_primary(self) -> bool:
        return self.region_role.upper() == "PRIMARY"

    @property
    def documentdb_uri(self) -> str:
        if self.db_password:
            return (
                f"mongodb://{self.db_user}:{self.db_password}"
                f"@{self.documentdb_host}:{self.documentdb_port}"
                f"/{self.db_name}?tls=true&tlsAllowInvalidCertificates=true&retryWrites=false"
            )
        return f"mongodb://{self.documentdb_host}:{self.documentdb_port}/{self.db_name}"

    @property
    def aurora_dsn(self) -> str:
        return (
            f"postgresql://{self.db_user}:{self.db_password}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )
