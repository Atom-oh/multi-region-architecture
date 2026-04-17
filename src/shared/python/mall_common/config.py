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
    documentdb_write_host: str = ""
    documentdb_port: int = 27017
    s3_bucket: str = ""
    log_level: str = "info"
    db_write_host: str = ""
    db_read_host_local: str = ""
    kafka_brokers_local: str = ""
    client_rack: str = ""
    prefer_replica_az: str = ""
    availability_zone: str = ""

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
                f"&readPreference=secondaryPreferred"
            )
        return f"mongodb://{self.documentdb_host}:{self.documentdb_port}/{self.db_name}"

    @property
    def documentdb_write_uri(self) -> str:
        host = self.documentdb_write_host or self.documentdb_host
        if self.db_password:
            return (
                f"mongodb://{self.db_user}:{self.db_password}"
                f"@{host}:{self.documentdb_port}"
                f"/{self.db_name}?tls=true&tlsAllowInvalidCertificates=true&retryWrites=false"
                f"&directConnection=true"
            )
        return f"mongodb://{host}:{self.documentdb_port}/{self.db_name}"

    @property
    def aurora_dsn(self) -> str:
        return (
            f"postgresql://{self.db_user}:{self.db_password}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )

    @property
    def aurora_writer_dsn(self) -> str:
        host = self.db_write_host or self.db_host
        return (
            f"postgresql://{self.db_user}:{self.db_password}"
            f"@{host}:{self.db_port}/{self.db_name}"
        )

    @property
    def aurora_reader_dsn(self) -> str:
        host = self.db_read_host_local or self.db_host
        return (
            f"postgresql://{self.db_user}:{self.db_password}"
            f"@{host}:{self.db_port}/{self.db_name}"
        )

    @property
    def kafka_brokers_effective(self) -> str:
        return self.kafka_brokers_local or self.kafka_brokers
