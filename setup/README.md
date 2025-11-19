# Setup Helpers

This directory contains helper scripts that bootstrap the SAGE platform.

## Docker-based stack

`run-docker-stack.sh` spins up every published Docker Hub image (`comnyang/sage-*`) behind the expected ports.

1. Make sure Docker and Docker Compose are installed.
2. Run `./setup/run-docker-stack.sh`.
   - The script fetches your public IP with `curl ifconfig.me` (you can override with `SAGE_HOST_IP=...`), writes `.sage-stack.env`, and then executes `docker compose up -d`.
   - API-to-API environment variables (`MAPPING_BASE_URL`, `COLLECTOR_BASE_URL`, etc.) are generated automatically so that Compliance APIs know how to talk to each other.
3. To stop the stack: `docker compose --env-file .sage-stack.env -f docker-compose.marketplace.yml down`.

Ports (host → container defaults):

| Service              | Image                          | Port |
|----------------------|--------------------------------|------|
| Frontend             | `comnyang/sage-front`          | 8200 → 8080 |
| Analyzer             | `comnyang/sage-analyzer`       | 9000 → 9000 |
| Data Collector       | `comnyang/sage-collector`      | 8000 → 8000 |
| Compliance-show API  | `comnyang/sage-com-show`       | 8003 → 8003 |
| Compliance-audit API | `comnyang/sage-com-audit`      | 8103 → 8103 |
| Lineage API          | `comnyang/sage-lineage`        | 8300 → 8300 |
| OSS Runner           | `comnyang/sage-oss`            | 8800 → 8800 |

Set `AWS_REGION`, `FRONT_PORT`, etc. before running the script if you need to override defaults. All resolved values end up in `.sage-stack.env`, which is already ignored by git.
