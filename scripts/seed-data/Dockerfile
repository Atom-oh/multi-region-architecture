FROM amazonlinux:2023

# Install all required tools
RUN yum install -y \
    postgresql16 \
    nodejs npm \
    redis6 \
    python3 python3-pip \
    openssl jq bc \
    awscli \
    --quiet && \
    yum clean all

# Download DocumentDB CA bundle
RUN curl -sS -o /tmp/global-bundle.pem \
    https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

WORKDIR /seed-data
COPY . /seed-data/

# Install Node.js MongoDB driver for DocumentDB seeding (local to WORKDIR)
RUN npm install mongodb@6

RUN chmod +x *.sh

CMD ["bash", "run-seed.sh"]
