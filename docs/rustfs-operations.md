# RustFS — راهنمای عملیات

RustFS یک object storage سازگار با S3 است که روی port 9000 (S3 API) و port 9001 اجرا می‌شود.

> **نکته:** RustFS رایگان (1.0.1) **web console ندارد**. مدیریت از طریق S3 API یا ابزار `aws cli` و `boto3` انجام می‌شود. `RustFS Connect` یک سرویس تجاری جداست.

---

## اطلاعات اتصال

| پارامتر | مقدار |
|---------|-------|
| Endpoint | `http://localhost:9000` |
| Region | `us-east-1` |
| Addressing style | path-style (نه virtual-hosted) |
| Health check | `GET http://localhost:9000/minio/health/live` |

Credentials در `secrets/rustfs_user.txt` و `secrets/rustfs_password.txt` هستند.

---

## Health check

```bash
curl -s http://localhost:9000/minio/health/live
# خروجی: {"status":"ok","service":"rustfs-endpoint",...}
```

---

## مدیریت با boto3 (Python)

### نصب محیط مجازی

```bash
python3 -m venv /tmp/s3venv --system-site-packages
/tmp/s3venv/bin/pip install boto3 -q
```

### اتصال به RustFS

```python
import boto3
from botocore.client import Config

RUSTFS_USER = open('secrets/rustfs_user.txt').read().strip()
RUSTFS_PASS = open('secrets/rustfs_password.txt').read().strip()

s3 = boto3.client(
    's3',
    endpoint_url='http://localhost:9000',
    aws_access_key_id=RUSTFS_USER,
    aws_secret_access_key=RUSTFS_PASS,
    region_name='us-east-1',
    config=Config(signature_version='s3v4', s3={'addressing_style': 'path'})
)
```

### ساخت bucket

```bash
/tmp/s3venv/bin/python3 - <<'EOF'
import boto3
from botocore.client import Config

RUSTFS_USER = open('secrets/rustfs_user.txt').read().strip()
RUSTFS_PASS = open('secrets/rustfs_password.txt').read().strip()

s3 = boto3.client('s3',
    endpoint_url='http://localhost:9000',
    aws_access_key_id=RUSTFS_USER,
    aws_secret_access_key=RUSTFS_PASS,
    region_name='us-east-1',
    config=Config(signature_version='s3v4', s3={'addressing_style': 'path'})
)

s3.create_bucket(Bucket='nexus-backups')
print('bucket nexus-backups created')
EOF
```

**خروجی تأیید شده:**
```
bucket nexus-backups created
```

### لیست buckets

```bash
/tmp/s3venv/bin/python3 - <<'EOF'
import boto3
from botocore.client import Config

RUSTFS_USER = open('secrets/rustfs_user.txt').read().strip()
RUSTFS_PASS = open('secrets/rustfs_password.txt').read().strip()

s3 = boto3.client('s3',
    endpoint_url='http://localhost:9000',
    aws_access_key_id=RUSTFS_USER,
    aws_secret_access_key=RUSTFS_PASS,
    region_name='us-east-1',
    config=Config(signature_version='s3v4', s3={'addressing_style': 'path'})
)

resp = s3.list_buckets()
for b in resp.get('Buckets', []):
    print(f"  {b['Name']}  created: {b['CreationDate']}")
EOF
```

**خروجی تأیید شده:**
```
  nexus-backups  created: 2026-11-24 14:08:11.697000+00:00
```

### آپلود فایل

```bash
/tmp/s3venv/bin/python3 - <<'EOF'
import boto3
from botocore.client import Config

RUSTFS_USER = open('secrets/rustfs_user.txt').read().strip()
RUSTFS_PASS = open('secrets/rustfs_password.txt').read().strip()

s3 = boto3.client('s3',
    endpoint_url='http://localhost:9000',
    aws_access_key_id=RUSTFS_USER,
    aws_secret_access_key=RUSTFS_PASS,
    region_name='us-east-1',
    config=Config(signature_version='s3v4', s3={'addressing_style': 'path'})
)

# آپلود یک فایل محلی
s3.upload_file('backups/nexus_pg_20261124_135923.dump', 'nexus-backups', 'pg/nexus_pg_20261124_135923.dump')
print('uploaded successfully')

# لیست objects
resp = s3.list_objects_v2(Bucket='nexus-backups')
for obj in resp.get('Contents', []):
    print(f"  {obj['Key']}  size: {obj['Size']}")
EOF
```

### دانلود فایل

```bash
/tmp/s3venv/bin/python3 - <<'EOF'
import boto3
from botocore.client import Config

RUSTFS_USER = open('secrets/rustfs_user.txt').read().strip()
RUSTFS_PASS = open('secrets/rustfs_password.txt').read().strip()

s3 = boto3.client('s3',
    endpoint_url='http://localhost:9000',
    aws_access_key_id=RUSTFS_USER,
    aws_secret_access_key=RUSTFS_PASS,
    region_name='us-east-1',
    config=Config(signature_version='s3v4', s3={'addressing_style': 'path'})
)

s3.download_file('nexus-backups', 'pg/nexus_pg_20261124_135923.dump', '/tmp/restore.dump')
print('downloaded to /tmp/restore.dump')
EOF
```

---

## فعال‌سازی آپلود backup به RustFS

در `docker-compose/backup/.env` (کپی از `.env.example`):

```env
RUSTFS_ENABLED=true
RUSTFS_ENDPOINT=http://nexus_rustfs:9000
RUSTFS_BUCKET=nexus-backups
```

سپس backup cron را restart کن:

```bash
docker compose -f docker-compose/backup/docker-compose.yml up -d --force-recreate
```

---

## وضعیت نهایی تأیید شده

```
تاریخ تست: 2026-11-24

✅ nexus_rustfs Up (healthy)
✅ bucket nexus-backups ساخته شد
✅ آپلود object: nexus-backups/test/ping.txt (14 bytes)
✅ لیست objects کار می‌کند
✅ S3 API روی port 9000 با signature_version=s3v4 و path-style addressing
```

---

## نکات مهم

- **Signature version:** باید `s3v4` باشد — نه `s3` (Signature V2 کار نمی‌کند)
- **Addressing style:** باید `path` باشد — نه `virtual` (hostname-based routing ندارد)
- **Region:** هر مقداری قبول می‌کند؛ `us-east-1` استاندارد است
- **mc client:** URL رسمی دانلود (`dl.min.io`) در حال حاضر 410 Gone برمی‌گرداند — از boto3 یا aws cli استفاده کن
- **Port 9001:** در نسخه رایگان فقط یک endpoint S3 ثانویه است، نه web console
