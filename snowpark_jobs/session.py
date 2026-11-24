import os
from pathlib import Path

from snowflake.snowpark import Session

REPO_ROOT = Path(__file__).resolve().parent.parent


def _key_path() -> str:
    # Relative paths in SNOWFLAKE_KEY_FILE are resolved against the repo root, so the working directory does not matter
    path = Path(os.environ["SNOWFLAKE_KEY_FILE"]).expanduser()
    return str(path if path.is_absolute() else REPO_ROOT / path)


def make_session(role: str, warehouse: str, tag: str, schema: str = "RAW") -> Session:
    session = Session.builder.configs({
        "account": os.environ["SNOWFLAKE_ACCOUNT"],
        "user": os.environ.get("SNOWFLAKE_USER", "SVC_PIPELINE"),
        "private_key_file": _key_path(),
        "private_key_file_pwd": os.environ["SNOWFLAKE_KEY_PASSPHRASE"],
        "role": role,
        "warehouse": warehouse,
        "database": "STAYPULSE",
        "schema": schema,
    }).create()
    session.query_tag = tag  # every credit traces back to a task
    return session
