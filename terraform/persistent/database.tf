locals {
  atlas_names = {
    for env in var.environments : env => {
      cluster = env == "prod" ? var.legacy_name_prefix : "${var.project}-${env}"
      user    = env == "prod" ? "${var.legacy_name_prefix}-app" : "${var.project}-${env}-app"
    }
  }
}

resource "mongodbatlas_project" "env" {
  for_each = local.environments

  name   = "${var.project}-${each.key}"
  org_id = var.mongodbatlas_org_id
}

resource "mongodbatlas_advanced_cluster" "env" {
  for_each = local.environments

  project_id   = mongodbatlas_project.env[each.key].id
  name         = local.atlas_names[each.key].cluster
  cluster_type = "REPLICASET"

  replication_specs {
    region_configs {
      provider_name         = "TENANT"
      backing_provider_name = "AWS"
      region_name           = var.atlas_region
      priority              = 7

      electable_specs {
        instance_size = "M0"
      }
    }
  }

  lifecycle {
    ignore_changes = [replication_specs]
  }
}

resource "random_password" "mongodb" {
  for_each = local.environments

  length  = 32
  special = false

  lifecycle {
    ignore_changes = all
  }
}

resource "mongodbatlas_database_user" "app" {
  for_each = local.environments

  project_id         = mongodbatlas_project.env[each.key].id
  username           = local.atlas_names[each.key].user
  password           = random_password.mongodb[each.key].result
  auth_database_name = "admin"

  dynamic "roles" {
    for_each = toset(compact(distinct([
      each.value.db_name,
      each.key == "prod" ? var.mongodb_db_name : "",
    ])))

    content {
      role_name     = "readWrite"
      database_name = roles.value
    }
  }
}

resource "mongodbatlas_project_ip_access_list" "anywhere" {
  for_each = local.environments

  project_id = mongodbatlas_project.env[each.key].id
  cidr_block = "0.0.0.0/0"
  comment    = "Serverless compute has no stable egress IP"
}

locals {
  mongodb_srv = {
    for env in var.environments : env => replace(
      mongodbatlas_advanced_cluster.env[env].connection_strings[0].standard_srv,
      "mongodb+srv://",
      "mongodb+srv://${mongodbatlas_database_user.app[env].username}:${random_password.mongodb[env].result}@"
    )
  }
}
