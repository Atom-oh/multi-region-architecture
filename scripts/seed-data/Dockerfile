FROM amazonlinux:2023

# Install all required tools
RUN yum install -y \
    postgresql16 \
    nodejs npm \
    redis6 \
    python3 python3-pip \
    openssl curl jq bc \
    --quiet && \
    yum clean all

# Download DocumentDB CA bundle
RUN curl -sS -o /tmp/global-bundle.pem \
    https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem

# Install Node.js MongoDB driver for DocumentDB seeding
RUN npm install -g mongodb@6

WORKDIR /seed-data
COPY . /seed-data/

RUN chmod +x *.sh

CMD ["bash", "run-seed.sh"]
