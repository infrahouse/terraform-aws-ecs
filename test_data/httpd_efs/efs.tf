resource "aws_efs_file_system" "volume1" {
  creation_token = "volume1"
  tags = {
    Name = "volume1"
  }
}

resource "aws_efs_mount_target" "volume1" {
  for_each       = toset(var.subnet_private_ids)
  file_system_id = aws_efs_file_system.volume1.id
  subnet_id      = each.key
}


resource "aws_efs_file_system" "volume2" {
  creation_token = "volume2"
  tags = {
    Name = "volume2"
  }
}

resource "aws_efs_mount_target" "volume2" {
  for_each       = toset(var.subnet_private_ids)
  file_system_id = aws_efs_file_system.volume2.id
  subnet_id      = each.key
}


