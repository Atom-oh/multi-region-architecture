FROM amazonlinux:2023

# postgresql16 provides pg_dump/pg_restore. mongodb-database-tools (mongodump/
# mongorestore) isn't in the default amazonlinux repos, so pull it from
# MongoDB's own RPM repo.
RUN cat <<'EOF' > /etc/yum.repos.d/mongodb-org.repo
[mongodb-org]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2023/mongodb-org/8.0/$basearch/
gpgcheck=1
gpgkey=https://pgp.mongodb.com/server-8.0.asc
enabled=1
EOF

RUN yum install -y \
    postgresql16 \
    mongodb-database-tools \
    awscli \
    tar gzip findutils \
    --quiet && \
    yum clean all

# AWS CA bundle so mongodump/mongorestore can verify DocumentDB TLS
# (replaces --tlsInsecure, which disabled cert verification entirely)
ADD https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem /etc/ssl/certs/rds-global-bundle.pem
RUN chmod 0644 /etc/ssl/certs/rds-global-bundle.pem

WORKDIR /backup-restore
COPY backup.sh restore.sh /backup-restore/
RUN chmod +x *.sh

CMD ["bash", "backup.sh"]
