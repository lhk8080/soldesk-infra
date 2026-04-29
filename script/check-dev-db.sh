#!/usr/bin/env bash
# dev DB 마이그레이션 검증용 일회성 mysql pod 실행
set -euo pipefail
REGION="${AWS_REGION:-ap-northeast-2}"

H=$(aws ssm get-parameter --region "$REGION" --name /ticketing/dev/DB_WRITER_HOST --query Parameter.Value --output text)
U=$(aws ssm get-parameter --region "$REGION" --name /ticketing/dev/DB_USER --query Parameter.Value --output text)
P=$(aws ssm get-parameter --region "$REGION" --name /ticketing/dev/DB_PASSWORD --with-decryption --query Parameter.Value --output text)

kubectl run mysql-check --rm -i --restart=Never --image=mysql:8.0 \
  --env="H=$H" --env="U=$U" --env="P=$P" -- \
  bash -c '
M="mysql -h $H -u $U -p$P ticketing_dev -t"
echo "=== 접근 가능한 DB ==="
mysql -h $H -u $U -p$P -e "SHOW DATABASES;"
echo
echo "=== ticketing_dev 테이블 ==="
$M -e "SHOW TABLES;"
echo
echo "=== schema_migrations ==="
$M -e "SELECT * FROM schema_migrations ORDER BY version;"
echo
echo "=== movies 갯수 ==="
$M -e "SELECT COUNT(*) AS movies FROM movies;"
'
