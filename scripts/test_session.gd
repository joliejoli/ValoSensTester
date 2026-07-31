extends Node

enum TestType { PSA_BINARY, CONSISTENCY }
enum TargetType { STATIC, MOVING }
enum TargetSize { SMALL, MEDIUM, LARGE }
enum TestMode { STANDARD, PRESSURE, TRACKING }

var test_type: int = TestType.PSA_BINARY
var sens_min: float = 20.0
var sens_max: float = 80.0
var rounds: int = 3
var target_type: int = TargetType.STATIC
var target_size: int = TargetSize.MEDIUM
var test_mode: int = TestMode.STANDARD
