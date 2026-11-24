import snowflake.snowpark.functions as F
from snowflake.snowpark import Session, Window

from session import make_session


def prepare_reviews(session: Session, sample_size: int = 300) -> int:
    """Clean, dedupe and sample reviews. Everything stays a lazy DataFrame, so it compiles to SQL in Snowflake."""
    reviews = session.table("STAYPULSE.STAGING.STG_REVIEWS")  # reviewer names already dropped in staging
    cleaned = (
        reviews
        .with_column("COMMENT_CLEAN", F.trim(F.regexp_replace(
            F.regexp_replace(F.col("COMMENT_TEXT"), "<[^>]*>", " "), r"\s+", " ")))
        .filter(F.length("COMMENT_CLEAN") >= 60)
    )
    dedupe = Window.partition_by("LISTING_ID", "COMMENT_CLEAN").order_by("REVIEW_ID")
    prepared = (
        cleaned
        .with_column("RN", F.row_number().over(dedupe)).filter(F.col("RN") == 1)
        .sort(F.hash(F.col("REVIEW_ID")))  # deterministic pseudo-random sample
        .limit(sample_size)
        .select("REVIEW_ID", "LISTING_ID", "REVIEW_DATE", "COMMENT_CLEAN")
    )
    prepared.write.mode("overwrite").save_as_table("STAYPULSE.INTERMEDIATE.REVIEWS_PREPARED")
    return session.table("STAYPULSE.INTERMEDIATE.REVIEWS_PREPARED").count()  # no to_pandas()


if __name__ == "__main__":
    s = make_session("SP_TRANSFORMER", "TRANSFORM_WH", "script:prepare_reviews", schema="INTERMEDIATE")
    print(prepare_reviews(s))
    s.close()
