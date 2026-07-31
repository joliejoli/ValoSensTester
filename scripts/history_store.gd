extends RefCounted
# 测试历史存储（Phase 5.4）：JSON 格式 user://history.json
# 记录结构：
# { "ts": unix秒, "type": "PSA"/"CONSISTENCY", "sens": float, "dpi": int, "edpi": int,
#   "score_mean/low/high": float, "mode_label": String, "rounds": int,
#   "metrics": {accuracy, median_hit, median_correct, wasted, score},
#   "round_results": Array（完整每轮数据）}

const HISTORY_PATH := "user://history.json"
const MAX_RECORDS := 100

static func load_records(path: String = HISTORY_PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary and data.get("records") is Array:
		return data["records"]
	return []

static func save_record(rec: Dictionary, path: String = HISTORY_PATH) -> void:
	var records := load_records(path)
	records.push_front(rec)
	while records.size() > MAX_RECORDS:
		records.pop_back()
	_write(path, records)

static func delete_record(ts: int, path: String = HISTORY_PATH) -> void:
	var records := load_records(path)
	for i in records.size():
		if int(records[i].get("ts", 0)) == ts:
			records.remove_at(i)
			break
	_write(path, records)

static func clear_all(path: String = HISTORY_PATH) -> void:
	_write(path, [])

static func _write(path: String, records: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("无法写入历史文件: " + path)
		return
	f.store_string(JSON.stringify({"version": 1, "records": records}))

static func format_date(ts: int) -> String:
	var dt := Time.get_datetime_string_from_unix_time(ts, true)
	return dt.replace("T", " ").substr(0, 16)
