# Conftest 정책 — terraform show -json tfplan 출력에 적용한다.
#   terraform plan -out tfplan && terraform show -json tfplan > tfplan.json
#   conftest test tfplan.json -p policy
#
# 정적 스캐너가 보지 못하는 "변수가 해석된 최종 값" 기준으로 조직 규칙을 강제한다.

package main

import rego.v1

# plan 에서 생성/변경되는 리소스만 대상으로 한다 (삭제·no-op 제외)
changed contains rc if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update"}
}

# ── 네트워크 ────────────────────────────────────────────────────────────────
# 관리 포트(22, 3389)를 전세계에 개방하는 인그레스 규칙 금지
deny contains msg if {
	some rc in changed
	rc.type == "aws_vpc_security_group_ingress_rule"
	after := rc.change.after
	after.cidr_ipv4 == "0.0.0.0/0"
	some port in {22, 3389}
	after.from_port <= port
	after.to_port >= port
	msg := sprintf("%s: 관리 포트 %d 를 0.0.0.0/0 에 개방할 수 없습니다", [rc.address, port])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_vpc_security_group_ingress_rule"
	after := rc.change.after
	after.cidr_ipv4 == "0.0.0.0/0"
	after.ip_protocol == "-1"
	msg := sprintf("%s: 모든 프로토콜을 0.0.0.0/0 에 개방할 수 없습니다", [rc.address])
}

# ── 스토리지 ────────────────────────────────────────────────────────────────
# S3 퍼블릭 차단은 4개 옵션 모두 true
deny contains msg if {
	some rc in changed
	rc.type == "aws_s3_bucket_public_access_block"
	after := rc.change.after
	some flag in {"block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"}
	after[flag] != true
	msg := sprintf("%s: %s 는 true 여야 합니다", [rc.address, flag])
}

# 퍼블릭 ACL 금지
deny contains msg if {
	some rc in changed
	rc.type == "aws_s3_bucket_acl"
	startswith(rc.change.after.acl, "public")
	msg := sprintf("%s: 퍼블릭 ACL(%s) 은 허용되지 않습니다", [rc.address, rc.change.after.acl])
}

# ── 데이터베이스 ────────────────────────────────────────────────────────────
deny contains msg if {
	some rc in changed
	rc.type == "aws_db_instance"
	rc.change.after.storage_encrypted != true
	msg := sprintf("%s: storage_encrypted 는 true 여야 합니다", [rc.address])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_db_instance"
	rc.change.after.publicly_accessible == true
	msg := sprintf("%s: RDS 는 publicly_accessible = false 여야 합니다", [rc.address])
}

deny contains msg if {
	some rc in changed
	rc.type == "aws_db_instance"
	rc.change.after.deletion_protection != true
	msg := sprintf("%s: deletion_protection 은 true 여야 합니다", [rc.address])
}

# ── 컴퓨트 ──────────────────────────────────────────────────────────────────
# IMDSv2 강제
deny contains msg if {
	some rc in changed
	rc.type == "aws_instance"
	some mo in rc.change.after.metadata_options
	mo.http_tokens != "required"
	msg := sprintf("%s: metadata_options.http_tokens 는 required 여야 합니다 (IMDSv2)", [rc.address])
}

# 루트 볼륨 암호화
deny contains msg if {
	some rc in changed
	rc.type == "aws_instance"
	some rbd in rc.change.after.root_block_device
	rbd.encrypted != true
	msg := sprintf("%s: root_block_device.encrypted 는 true 여야 합니다", [rc.address])
}

# ── IAM ─────────────────────────────────────────────────────────────────────
# Action "*" + Resource "*" 정책 금지
deny contains msg if {
	some rc in changed
	rc.type in {"aws_iam_policy", "aws_iam_role_policy"}
	doc := json.unmarshal(rc.change.after.policy)
	some stmt in doc.Statement
	stmt.Effect == "Allow"
	wildcard_action(stmt.Action)
	wildcard_resource(stmt.Resource)
	msg := sprintf("%s: Action '*' + Resource '*' 정책은 허용되지 않습니다", [rc.address])
}

wildcard_action(a) if a == "*"

wildcard_action(a) if {
	is_array(a)
	"*" in a
}

wildcard_resource(r) if r == "*"

wildcard_resource(r) if {
	is_array(r)
	"*" in r
}
