import csv
import gzip
import random
from datetime import date, datetime, time, timedelta
from pathlib import Path


def _price(text) -> float:
    try:
        return float(text.replace("$", "").replace(",", "")) or 150.0
    except (AttributeError, ValueError):
        return 150.0


def generate(listings_gz: Path, out_dir: Path, end: date, n_bookings: int = 5000, seed: int = 42):
    """Seeded bookings and payments anchored to real listing ids.

    Plants three exact duplicates and five late status revisions for the dedupe and MERGE tests.
    """
    rng = random.Random(seed)
    with gzip.open(listings_gz, "rt", encoding="utf-8", newline="") as f:
        listings = [(r["id"], _price(r.get("price", ""))) for r in csv.DictReader(f) if r.get("id")]
    listings = rng.sample(listings, min(600, len(listings)))  # dense enough per listing to matter
    start = end - timedelta(days=150)  # booking dates run start .. end-1, so no edge spike
    cutoff = datetime.combine(end, time.min)
    weekday_weight = [0.7, 0.75, 0.8, 0.9, 1.0, 1.0, 0.85]  # Mon..Sun: a weekly pattern for FORECAST to learn
    busy, bookings, payments, attempts = {}, [], [], 0
    while len(bookings) < n_bookings and attempts < n_bookings * 40:
        attempts += 1
        booked_day = start + timedelta(days=rng.randint(0, 149))
        if rng.random() > weekday_weight[booked_day.weekday()]:
            continue
        lid, nightly = rng.choice(listings)
        nights = rng.randint(1, 7)
        checkin = booked_day + timedelta(days=rng.randint(1, 60))
        checkout = checkin + timedelta(days=nights)
        if any(checkin < b_out and b_in < checkout for b_in, b_out in busy.get(lid, [])):
            continue  # no overlapping stays
        busy.setdefault(lid, []).append((checkin, checkout))
        n = len(bookings) + 1
        booked_at = datetime.combine(booked_day, time.min) + timedelta(hours=rng.randint(0, 23))
        cancelled = rng.random() < 0.12
        status = "cancelled" if cancelled else ("completed" if checkout <= end else "confirmed")
        updated_at = min(booked_at + timedelta(days=rng.randint(1, 20)), cutoff) if cancelled else booked_at
        total = round(nightly * nights * 1.1, 2)
        bid = f"B{n:06d}"
        bookings.append([bid, lid, f"G{rng.randint(1, 2500):05d}", checkin, checkout, nights, total,
                         status, booked_at.isoformat(sep=" "), updated_at.isoformat(sep=" ")])
        paid = round(total * 0.2, 2) if cancelled else total
        payments.append([f"P{n:06d}", bid, paid, "USD",
                         (booked_at + timedelta(minutes=5)).isoformat(sep=" "),
                         rng.choice(["card", "card", "paypal", "bank"])])

    for row in rng.sample(bookings, 3):  # defect 1: exact duplicates
        bookings.append(list(row))
    for row in rng.sample([b for b in bookings if b[7] == "confirmed"], 5):  # defect 2: late revisions
        late = list(row)
        late[7] = "cancelled"
        late[9] = (datetime.fromisoformat(row[9]) + timedelta(days=2)).isoformat(sep=" ")
        bookings.append(late)

    out_dir.mkdir(parents=True, exist_ok=True)
    files = [
        ("bookings.csv", ["booking_id", "listing_id", "guest_id", "checkin_date", "checkout_date", "nights",
                          "total_amount", "status", "booked_at", "updated_at"], bookings),
        ("payments.csv", ["payment_id", "booking_id", "amount", "currency", "paid_at", "method"], payments),
    ]
    for name, header, rows in files:
        with open(out_dir / name, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(header)
            writer.writerows(rows)
    return out_dir / "bookings.csv", out_dir / "payments.csv"
