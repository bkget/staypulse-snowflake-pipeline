"""Log in as each pipeline role and print who and where we are. Fails fast with a clear message."""
import sys

from session import make_session

CHECKS = [("SP_LOADER", "LOAD_WH"), ("SP_TRANSFORMER", "TRANSFORM_WH")]


def main() -> int:
    for role, warehouse in CHECKS:
        session = make_session(role, warehouse, "check:connection")
        user, current_role, wh, region, version = session.sql(
            "SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(), CURRENT_REGION(), CURRENT_VERSION()"
        ).collect()[0]
        print(f"OK  user={user} role={current_role} warehouse={wh} region={region} snowflake={version}")
        session.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
