"""Generate synthetic 837P-shaped claims, matching the DataDissect schema.

Same columns and filename convention as the local project, so the Azure pipeline
reads an identical shape. All data is fake — no PHI, ever.

    python scripts/generate_sample_claims.py --rows 5000
"""
import argparse
import csv
import random
from datetime import date, timedelta
from pathlib import Path

CPT = ["99213", "99214", "99215", "99203", "99204", "71046", "80053", "93000"]
ICD10 = ["Z00.00", "J06.9", "E11.9", "I10", "M54.5", "R51", "J02.9", "E78.5"]
PAYERS = ["BCBS001", "AETNA001", "UHC001", "CIGNA001"]
POS = ["11", "21", "22", "23", "81"]


def generate(rows: int, client: str, seed: int) -> list[dict]:
    rng = random.Random(seed)
    start = date(2026, 3, 1)
    out = []
    for i in range(1, rows + 1):
        out.append({
            "claim_id": f"CLM{i:06d}",
            "member_id": f"MBR{rng.randint(100000, 999999)}",
            "payer_id": rng.choice(PAYERS),
            "provider_npi": f"NPI{rng.randint(1000000000, 9999999999)}",
            "cpt_code": rng.choice(CPT),
            "icd10_code": rng.choice(ICD10),
            "service_date": (start + timedelta(days=rng.randint(0, 27))).isoformat(),
            "billed_amount": f"{rng.uniform(50, 5000):.2f}",
            "place_of_service": rng.choice(POS),
        })
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", type=int, default=5000)
    ap.add_argument("--client", default="BCBS001")
    ap.add_argument("--env", default="PROD")
    ap.add_argument("--date", default="20260312")
    ap.add_argument("--sequence", default="001")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    # Same self-describing convention as DataDissect:
    # {CLIENT}_{FILE_TYPE}_{ENV}_{DATE}_{SEQ}.csv
    name = f"{args.client}_837P_{args.env}_{args.date}_{args.sequence}.csv"
    dest = Path(__file__).resolve().parent.parent / "data" / name
    dest.parent.mkdir(parents=True, exist_ok=True)

    rowset = generate(args.rows, args.client, args.seed)
    with dest.open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rowset[0].keys()))
        writer.writeheader()
        writer.writerows(rowset)

    print(f"wrote {len(rowset):,} rows -> {dest}")


if __name__ == "__main__":
    main()
