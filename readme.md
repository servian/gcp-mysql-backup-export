# Periodic MySQL db backup export to bucket

Minimalistic code to create a database and provision GCP native resources sufficient to periodically export database backups to a bucket. Further information on this repository can be found in the article [GCP - Periodic export of MySQL backups to a bucket with Terraform](https://medium.com/@wade.francis_46436/gcp-periodic-export-of-mysql-backups-to-a-bucket-with-terraform-aa8854db35)

## Directory contents

### main.tf
Terraform code to provison the infra structure required for demonstration:
 - vanilla MySQL database
 - GCP App engine application
 - bucket for backups and Cloud Function source code
 - zip archive of Cloud Function source code
 - Cloud Function to invoke the MySQL REST API
 - Cloud Scheduler to periodically invoke the Cloud Function

### test.tfvars
Contains the GCP project id in which the resources are to be provisioned

### /app/export_database.js
NodeJS code to invoke the [MySQL REST API](https://cloud.google.com/sql/docs/mysql/admin-api/v1beta4/instances/export) endpoint to export a database backup to a bucket

### /app/package.json
Package file used by Cloud Functions to determine dependencies
