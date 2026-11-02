#!/bin/bash
set -euo pipefail

readonly source_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
readonly install_root="/opt/courier/data-node"
readonly library_root="/usr/local/lib/courier"

test "$(id -u)" -eq 0

"${source_root}/scripts/install-compose.sh"

install --directory --owner root --group root --mode 0755 "${install_root}" "${library_root}"
cp --recursive "${source_root}/." "${install_root}/"

install --owner root --group root --mode 0755 \
  "${install_root}/scripts/hydrate-data-env.sh" "${library_root}/hydrate-data-env.sh"
install --owner root --group root --mode 0755 \
  "${install_root}/scripts/backup-postgres.sh" "${library_root}/backup-postgres.sh"
install --owner root --group root --mode 0755 \
  "${install_root}/scripts/initialize-kafka-topics.sh" "${library_root}/initialize-kafka-topics.sh"
install --owner root --group root --mode 0644 \
  "${install_root}/systemd/courier-data.service" /etc/systemd/system/courier-data.service
install --owner root --group root --mode 0644 \
  "${install_root}/systemd/courier-postgres-backup.service" /etc/systemd/system/courier-postgres-backup.service
install --owner root --group root --mode 0644 \
  "${install_root}/systemd/courier-postgres-backup.timer" /etc/systemd/system/courier-postgres-backup.timer

install --directory --owner 70 --group 70 --mode 0700 /data/postgres
install --directory --owner 999 --group 999 --mode 0750 /data/redis
install --directory --owner 1000 --group 1000 --mode 0750 /data/kafka /data/qdrant
install --directory --owner root --group root --mode 0700 /data/backups

systemctl daemon-reload
systemctl enable courier-data.service courier-postgres-backup.timer

if [[ "${1:-}" == "--start" ]]; then
  systemctl restart courier-data.service
  systemctl start courier-postgres-backup.timer
fi
