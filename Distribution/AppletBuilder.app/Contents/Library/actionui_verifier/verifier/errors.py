class ValidationIssue:
    def __init__(self, severity: str, path: str, message: str):
        self.severity = severity  # "error" or "warning"
        self.path = path
        self.message = message

    def __str__(self):
        return f"[{self.severity.upper()}] {self.path}: {self.message}"
