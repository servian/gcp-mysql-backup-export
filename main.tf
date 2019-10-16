variable "project_id" {
  description = "The project ID to manage the Cloud SQL resources"
}

variable "db_name" {
  description = "The name of the Cloud SQL resources"
  default = "testdb1"
}

variable "create_database" {
  description = "Create a datbase"
  default     = 1
}

variable "create_export_function" {
  description = "Create an export function and bucket to allow exporting database backups"
  default     = 1
}

terraform {
  required_version = "~> 0.11.14"
}

provider "google" {
  version = "~> 2.7.0"
  region  = "australia-southeast1"
}

provider "google-beta" {
  version = "~> 2.14.0"
  region  = "australia-southeast1"
}

# Create a vanilla database instance
resource "google_sql_database_instance" "default" {
  count            = "${var.create_database}"
  project          = "${var.project_id}"
  name             = "${var.db_name}"
  database_version = "MYSQL_5_7"
  region           = "australia-southeast1"

  settings {
    tier = "db-f1-micro"
  }
}

# https://www.terraform.io/docs/providers/google/r/app_engine_application.html
# App Engine applications cannot be deleted once they're created; 
# you have to delete the entire project to delete the application.
# Terraform will report the application has been successfully deleted;
# this is a limitation of Terraform, and will go away in the future.
# Terraform is not able to delete App Engine applications.
#
# If this resource is marked as deleted by terraform, re-import it with:
# terraform import "google_app_engine_application.db_export_scheduler_app" "[project_id]"

resource "google_app_engine_application" "db_export_scheduler_app" {
  # count       = "${var.create_export_function}"
  # See comment above - this resource can only be created and never destroyed
  project = "${var.project_id}"
  location_id = "australia-southeast1"
}

resource "random_id" "db_bucket_suffix" {
  count       = "${var.create_export_function}"
  byte_length = 2

  keepers = {
    project_id = "${var.project_id}"
  }
}

resource "google_storage_bucket" "db_backup_bucket" {
  count    = "${var.create_export_function}"
  name     = "${var.db_name}-db-backup-${random_id.db_bucket_suffix.hex}"
  project  = "${var.project_id}"
  location = "australia-southeast1"

  versioning = {
    enabled = "false"
  }

  storage_class = "REGIONAL"

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }

    condition {
      age = 7
    }
  }

  lifecycle_rule {
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }

    condition {
      age = 30
    }
  }
}

resource "google_storage_bucket_iam_member" "db_service_account-roles_storage-objectAdmin" {
  count  = "${var.create_export_function}"
  bucket = "${google_storage_bucket.db_backup_bucket.name}"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_sql_database_instance.default.service_account_email_address}"
}

# create local zip of code
data "archive_file" "function_dist" {
  count       = "${var.create_export_function}"
  output_path = "./dist/export_function_source.zip"
  source_dir  = "./app/"
  type        = "zip"
}

# upload the file_md5 to GCP bucket
resource "google_storage_bucket_object" "cloudfunction_source_code" {
  count      = "${var.create_export_function}"
  depends_on = ["data.archive_file.function_dist"]

  name   = "code/export_database-${lower(replace(base64encode(md5(file("./app/export_database.js"))), "=", ""))}.zip"
  bucket = "${google_storage_bucket.db_backup_bucket.name}"
  source = "./dist/export_function_source.zip"
}

# create function using the file_md5 as the source
resource "google_cloudfunctions_function" "export_database_to_bucket" {
  count                 = "${var.create_export_function}"
  depends_on            = ["google_storage_bucket_object.cloudfunction_source_code"]
  project               = "${var.project_id}"
  region                = "asia-northeast1"
  name                  = "export_database_to_bucket"
  description           = "[Managed by Terraform] This function exports the main database instance to the backup bucket"
  available_memory_mb   = 128
  source_archive_bucket = "${google_storage_bucket.db_backup_bucket.name}"
  source_archive_object = "code/export_database-${lower(replace(base64encode(md5(file("./app/export_database.js"))), "=", ""))}.zip"
  runtime               = "nodejs8"
  entry_point           = "exportDatabase"
  trigger_http          = "true"
}

data "google_compute_default_service_account" "default" {
  project = "${var.project_id}"
}

data "template_file" "cloudfunction_params" {
  count = "${var.create_export_function}"

  template = <<EOF
{
    "project_name": "${var.project_id}",
    "mysql_instance_name": "${google_sql_database_instance.default.name}",
    "bucket_name": "${google_storage_bucket.db_backup_bucket.name}"
}
EOF
}

resource "google_cloud_scheduler_job" "db_export_trigger" {
  provider    = "google-beta"
  count       = "${var.create_export_function}"
  depends_on  = ["google_storage_bucket_object.cloudfunction_source_code"]
  project     = "${var.project_id}"
  name        = "db-export-scheduler-job"
  schedule    = "0 8,18 * * *"
  description = "Exports the database at 8am and 6pm"
  time_zone   = "Australia/Melbourne"

  http_target = {
    uri         = "${google_cloudfunctions_function.export_database_to_bucket.*.https_trigger_url[0]}"
    http_method = "POST"

    body = "${base64encode(data.template_file.cloudfunction_params.rendered)}"

    oidc_token = {
      service_account_email = "${data.google_compute_default_service_account.default.email}"
    }
  }
}
