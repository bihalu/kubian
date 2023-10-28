# Backup with velero
The Velero CLI has already been installed with Kubian.  
All you have to do is adjust the Velero configuration.

## 1. Customize Velero Install
You need an S3-compatible object storage provider to hold your backup.  
In this example i am using MinIO.  
Please note you have to create the bucket beforhand.  
Change the following values in your configuration:  
* aws_access_key_id = <your_aws_access_key_id>
* aws_secret_access_key = <your_aws_secret_access_key>
* --bucket <your_minio_bucket>
* s3Url=<your_s3_endpoint>

```bash
tee ~/.credentials-velero <<EOL_VELERO
[default]
aws_access_key_id = admin
aws_secret_access_key = topsecret
EOL_VELERO

velero install \
  --use-node-agent \
  --default-volumes-to-fs-backup \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.8.0 \
  --bucket velero \
  --secret-file ~/.credentials-velero \
  --use-volume-snapshots=false \
  --backup-location-config region=minio,s3ForcePathStyle=true,s3Url=http://192.168.178.61:30002
```

## 2. Create backup
I highly recommend installing each application in its own namespace.  
Creating a backup is then easy.
```bash
velero backup create wordpress-backup-20231002 --include-namespaces wordpress
```

### 2.1. Create backup schedule
You can also create a schedule for a daily backup at 1:00 a.m.
```bash
velero schedule create wordpress-backup --schedule="0 1 * * *" --include-namespaces wordpress

velero schedule get
NAME               STATUS    CREATED                          SCHEDULE    BACKUP TTL   LAST BACKUP   SELECTOR   PAUSED
wordpress-backup   Enabled   2023-10-02 13:18:02 +0200 CEST   0 1 * * *   0s           n/a           <none>     false
```

## 3. Restore backup
Please note that the namespace will be deleted before restore.  
These are full backups that cannot be restored incrementally.  
```bash
velero get backups
NAME                        STATUS      ERRORS   WARNINGS   CREATED                          EXPIRES   STORAGE LOCATION   SELECTOR
wordpress-backup-20231002   Completed   0        0          2023-10-02 12:42:00 +0200 CEST   29d       default            <none>

kubectl delete namespace wordpress

velero restore create --from-backup wordpress-backup-20231002
```
