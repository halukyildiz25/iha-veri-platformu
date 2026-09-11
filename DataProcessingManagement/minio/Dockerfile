# Air-gapped: sürüm sabit tutulur ki hazırlık ve hedef makine aynı MinIO'yu alsın.
FROM minio/minio:RELEASE.2025-09-07T16-13-09Z

EXPOSE 9000 9001

VOLUME ["/data"]

CMD ["server", "/data", "--console-address", ":9001"]
