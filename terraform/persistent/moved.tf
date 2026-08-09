moved {
  from = mongodbatlas_project.main
  to   = mongodbatlas_project.env["prod"]
}

moved {
  from = mongodbatlas_advanced_cluster.main
  to   = mongodbatlas_advanced_cluster.env["prod"]
}

moved {
  from = random_password.mongodb
  to   = random_password.mongodb["prod"]
}

moved {
  from = mongodbatlas_database_user.app
  to   = mongodbatlas_database_user.app["prod"]
}

moved {
  from = mongodbatlas_project_ip_access_list.anywhere
  to   = mongodbatlas_project_ip_access_list.anywhere["prod"]
}

moved {
  from = aws_cognito_user_pool_client.console
  to   = aws_cognito_user_pool_client.app["prod"]
}
