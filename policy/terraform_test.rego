# conftest verify -p policy
package main

import rego.v1

# ── 헬퍼 ────────────────────────────────────────────────────────────────────
plan_with(rc) := {"resource_changes": [rc]}

create(type, address, after) := {
	"address": address,
	"type": type,
	"change": {"actions": ["create"], "after": after},
}

# ── 네트워크 ────────────────────────────────────────────────────────────────
test_ssh_open_to_world_denied if {
	rc := create("aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_ingress_rule.ssh", {
		"cidr_ipv4": "0.0.0.0/0", "from_port": 22, "to_port": 22, "ip_protocol": "tcp",
	})
	count(deny) == 1 with input as plan_with(rc)
}

test_ssh_from_admin_cidr_allowed if {
	rc := create("aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_ingress_rule.ssh", {
		"cidr_ipv4": "10.10.0.0/16", "from_port": 22, "to_port": 22, "ip_protocol": "tcp",
	})
	count(deny) == 0 with input as plan_with(rc)
}

test_https_open_to_world_allowed if {
	rc := create("aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_ingress_rule.https", {
		"cidr_ipv4": "0.0.0.0/0", "from_port": 443, "to_port": 443, "ip_protocol": "tcp",
	})
	count(deny) == 0 with input as plan_with(rc)
}

test_port_range_covering_ssh_denied if {
	rc := create("aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_ingress_rule.wide", {
		"cidr_ipv4": "0.0.0.0/0", "from_port": 0, "to_port": 65535, "ip_protocol": "tcp",
	})
	count(deny) >= 1 with input as plan_with(rc)
}

test_all_protocols_open_denied if {
	rc := create("aws_vpc_security_group_ingress_rule", "aws_vpc_security_group_ingress_rule.all", {
		"cidr_ipv4": "0.0.0.0/0", "from_port": -1, "to_port": -1, "ip_protocol": "-1",
	})
	count(deny) >= 1 with input as plan_with(rc)
}

# ── 스토리지 ────────────────────────────────────────────────────────────────
test_public_access_block_partial_denied if {
	rc := create("aws_s3_bucket_public_access_block", "module.b.aws_s3_bucket_public_access_block.this", {
		"block_public_acls": true, "block_public_policy": false,
		"ignore_public_acls": true, "restrict_public_buckets": true,
	})
	count(deny) == 1 with input as plan_with(rc)
}

test_public_acl_denied if {
	rc := create("aws_s3_bucket_acl", "aws_s3_bucket_acl.b", {"acl": "public-read"})
	count(deny) == 1 with input as plan_with(rc)
}

# ── 데이터베이스 ────────────────────────────────────────────────────────────
test_unencrypted_public_db_denied if {
	rc := create("aws_db_instance", "aws_db_instance.db", {
		"storage_encrypted": false, "publicly_accessible": true, "deletion_protection": false,
	})
	count(deny) == 3 with input as plan_with(rc)
}

test_hardened_db_allowed if {
	rc := create("aws_db_instance", "aws_db_instance.db", {
		"storage_encrypted": true, "publicly_accessible": false, "deletion_protection": true,
	})
	count(deny) == 0 with input as plan_with(rc)
}

# ── 컴퓨트 ──────────────────────────────────────────────────────────────────
test_imdsv1_denied if {
	rc := create("aws_instance", "aws_instance.web", {
		"metadata_options": [{"http_tokens": "optional"}],
		"root_block_device": [{"encrypted": true}],
	})
	count(deny) == 1 with input as plan_with(rc)
}

test_unencrypted_root_denied if {
	rc := create("aws_instance", "aws_instance.web", {
		"metadata_options": [{"http_tokens": "required"}],
		"root_block_device": [{"encrypted": false}],
	})
	count(deny) == 1 with input as plan_with(rc)
}

# ── IAM ─────────────────────────────────────────────────────────────────────
test_admin_wildcard_policy_denied if {
	policy := json.marshal({"Version": "2012-10-17", "Statement": [{"Effect": "Allow", "Action": "*", "Resource": "*"}]})
	rc := create("aws_iam_policy", "aws_iam_policy.admin", {"policy": policy})
	count(deny) == 1 with input as plan_with(rc)
}

test_scoped_policy_allowed if {
	policy := json.marshal({"Version": "2012-10-17", "Statement": [{
		"Effect": "Allow", "Action": ["s3:GetObject"], "Resource": ["arn:aws:s3:::b/*"],
	}]})
	rc := create("aws_iam_policy", "aws_iam_policy.app", {"policy": policy})
	count(deny) == 0 with input as plan_with(rc)
}

# ── 삭제는 대상 아님 ────────────────────────────────────────────────────────
test_delete_action_ignored if {
	rc := {
		"address": "aws_db_instance.old", "type": "aws_db_instance",
		"change": {"actions": ["delete"], "after": null},
	}
	count(deny) == 0 with input as plan_with(rc)
}
