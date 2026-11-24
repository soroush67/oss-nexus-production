# OSS Nexus — Production Stack

Nexus Repository Manager OSS 3.80 + PostgreSQL 18 + Nginx 1.30, با سه docker-compose جداگانه.

## معماری

```
Internet → Nginx (443/80/8082) → Nexus App (8081) → PostgreSQL (5432)
                                        ↕
                                  nexus_data volume
```

شبکه داخلی `nexus_infra_net` (bridge) بین سه compose مشترک است.

## پیش‌نیازها

- Docker Engine ≥ 26
- Docker Compose plugin ≥ 2.27
- OpenSSL (برای generate-secrets)
- RAM: حداقل ۴ گیگابایت آزاد

## راه‌اندازی اولیه

```bash
# ۱. تولید secrets و self-signed cert
./scripts/generate-secrets.sh

# ۲. deploy کامل
./scripts/deploy.sh
```

## دسترسی

| سرویس | آدرس |
|-------|------|
| Nexus UI | https://localhost |
| Docker registry | https://localhost:8082 |

رمز admin اولیه:
```bash
docker exec nexus_app cat /nexus-data/admin.password
```

## Deploy روی سرور ریموت

```bash
# پیش‌نیاز: sshpass نصب باشد
# sudo apt install sshpass

REMOTE_PASS=<password> ./scripts/remote-deploy.sh
```

متغیرهای قابل تنظیم:

| متغیر | پیش‌فرض | توضیح |
|-------|---------|-------|
| `REMOTE_HOST` | `192.168.11.67` | IP سرور هدف |
| `REMOTE_USER` | `devops` | کاربر SSH |
| `REMOTE_PASS` | — | رمز SSH (اجباری) |
| `REMOTE_DIR` | `/home/devops/containerd/nexus` | مسیر نصب روی سرور |

اسکریپت به‌ترتیب انجام می‌دهد:
1. بررسی اتصال SSH
2. نصب docker compose plugin روی سرور
3. ذخیره و انتقال Docker images (~600MB)
4. انتقال فایل‌های پروژه با rsync
5. کپی secrets و SSL cert
6. ایجاد network و volume
7. اجرای `deploy.sh` روی سرور

**نکته:** RustFS و backup cron به‌صورت پیش‌فرض اجرا نمی‌شوند. بعد از deploy:
```bash
REMOTE_PASS=<password> ssh devops@192.168.11.67 \
  "cd /home/devops/containerd/nexus && DEPLOY_RUSTFS=true DEPLOY_BACKUP=true bash scripts/deploy.sh"
```

## مدیریت روزانه

```bash
# خاموش کردن
./scripts/down.sh

# بکاپ گرفتن (PG dump + volume snapshot)
./scripts/backup.sh

# دیدن لاگ nexus
docker logs -f nexus_app

# دیدن لاگ postgres
docker logs -f nexus_postgres
```

## ساختار فایل‌ها

```
.
├── docker-compose/
│   ├── postgres/
│   │   ├── docker-compose.yml
│   │   ├── config/postgresql.conf
│   │   └── init/01-init.sh
│   ├── nexus/
│   │   ├── docker-compose.yml
│   │   └── config/nexus/nexus.properties
│   │                    nexus-store.properties
│   │            logback/logback.xml
│   └── nginx/
│       ├── docker-compose.yml
│       ├── conf.d/nexus.conf
│       └── ssl/              ← gitignored
├── secrets/                  ← gitignored
├── scripts/
│   ├── generate-secrets.sh
│   ├── deploy.sh
│   ├── down.sh
│   └── backup.sh
└── backups/                  ← gitignored
```

## نکات Production

- **TLS**: cert خود-امضا را با Let's Encrypt یا CA داخلی جایگزین کنید
- **Backup**: `backup.sh` را با cron روزانه اجرا کنید
- **PostgreSQL**: پشتیبانی از PostgreSQL در Nexus OSS از نسخه 3.70+ اضافه شده؛ اگر خطای datastore داشتید، `nexus.datastore.enabled=false` کنید تا با H2 کار کند
- **حافظه**: JVM heap روی ۲.۷ گیگ تنظیم است؛ اگر host بیشتر دارد، `INSTALL4J_ADD_VM_PARAMS` را در nexus compose تنظیم کنید

## Images

| Image | نسخه |
|-------|------|
| sonatype/nexus3 | 3.80.0 |
| postgres | 18-alpine |
| nginx | 1.30.7-alpine |
| alpine | 3.21 |
