#!/usr/bin/env python3
"""Build a compact local USDA nutrition SQLite database for Meal Scan V2.

Input can be a simplified JSON array or CSV exported from a FoodData Central
subset. The importer expects per-100g nutrient columns when available and keeps
only fields used by CycleBalance's local nutrition lookup path.
"""

from __future__ import annotations

import argparse
import csv
import json
import sqlite3
from pathlib import Path
from typing import Any, Iterable


FIELDS = [
    "id",
    "display_name",
    "canonical_name",
    "source",
    "category",
    "serving_description",
    "serving_grams",
    "calories_per_100g",
    "protein_per_100g",
    "carbs_per_100g",
    "fat_per_100g",
    "fiber_per_100g",
    "sugar_per_100g",
    "sodium_mg_per_100g",
    "saturated_fat_per_100g",
    "cholesterol_mg_per_100g",
    "potassium_mg_per_100g",
    "calcium_mg_per_100g",
    "iron_mg_per_100g",
    "aliases",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import a USDA subset into MealNutrition.sqlite")
    parser.add_argument("input", type=Path, help="Input CSV or JSON file")
    parser.add_argument("output", type=Path, help="Output SQLite database path")
    return parser.parse_args()


def load_rows(path: Path) -> list[dict[str, Any]]:
    if path.suffix.lower() == ".json":
        raw = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(raw, list):
            raise ValueError("JSON input must be an array of food records")
        return [normalize_record(item) for item in raw]

    with path.open(newline="", encoding="utf-8") as handle:
        return [normalize_record(row) for row in csv.DictReader(handle)]


def normalize_record(record: dict[str, Any]) -> dict[str, Any]:
    source_id = value(record, "id", "fdc_id", "fdcId")
    display_name = value(record, "display_name", "description", "displayName", "food")
    canonical_name = value(record, "canonical_name", "canonicalName") or display_name
    aliases = value(record, "aliases", "alias") or ""
    if isinstance(aliases, list):
        aliases = ",".join(str(alias) for alias in aliases)

    normalized = {
        "id": str(source_id or "").strip(),
        "display_name": str(display_name or "").strip(),
        "canonical_name": str(canonical_name or "").strip(),
        "source": str(value(record, "source") or "usda").strip(),
        "category": value(record, "category", "food_category"),
        "serving_description": value(record, "serving_description", "servingDescription"),
        "serving_grams": number(value(record, "serving_grams", "servingGrams")),
        "calories_per_100g": number(value(record, "calories_per_100g", "caloriesPer100g", "energy_kcal")),
        "protein_per_100g": number(value(record, "protein_per_100g", "proteinPer100g", "protein")),
        "carbs_per_100g": number(value(record, "carbs_per_100g", "carbsPer100g", "carbohydrate")),
        "fat_per_100g": number(value(record, "fat_per_100g", "fatPer100g", "fat")),
        "fiber_per_100g": number(value(record, "fiber_per_100g", "fiberPer100g", "fiber")),
        "sugar_per_100g": number(value(record, "sugar_per_100g", "sugarPer100g", "sugars")),
        "sodium_mg_per_100g": number(value(record, "sodium_mg_per_100g", "sodiumMgPer100g", "sodium")),
        "saturated_fat_per_100g": number(value(record, "saturated_fat_per_100g", "saturatedFatPer100g")),
        "cholesterol_mg_per_100g": number(value(record, "cholesterol_mg_per_100g", "cholesterolMgPer100g")),
        "potassium_mg_per_100g": number(value(record, "potassium_mg_per_100g", "potassiumMgPer100g")),
        "calcium_mg_per_100g": number(value(record, "calcium_mg_per_100g", "calciumMgPer100g")),
        "iron_mg_per_100g": number(value(record, "iron_mg_per_100g", "ironMgPer100g")),
        "aliases": str(aliases).strip(),
    }
    if not normalized["id"] or not normalized["display_name"]:
        raise ValueError(f"Food record is missing id/display name: {record!r}")
    return normalized


def value(record: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in record and record[key] not in ("", None):
            return record[key]
    return None


def number(raw: Any) -> float | None:
    if raw in ("", None):
        return None
    try:
        return float(raw)
    except (TypeError, ValueError):
        return None


def build_database(rows: Iterable[dict[str, Any]], output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()

    connection = sqlite3.connect(output)
    with connection:
        connection.execute(
            """
            CREATE TABLE foods (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                canonical_name TEXT NOT NULL,
                source TEXT NOT NULL,
                category TEXT,
                serving_description TEXT,
                serving_grams REAL,
                calories_per_100g REAL,
                protein_per_100g REAL,
                carbs_per_100g REAL,
                fat_per_100g REAL,
                fiber_per_100g REAL,
                sugar_per_100g REAL,
                sodium_mg_per_100g REAL,
                saturated_fat_per_100g REAL,
                cholesterol_mg_per_100g REAL,
                potassium_mg_per_100g REAL,
                calcium_mg_per_100g REAL,
                iron_mg_per_100g REAL,
                aliases TEXT
            )
            """
        )
        connection.execute(
            "CREATE VIRTUAL TABLE food_search USING fts5(id UNINDEXED, display_name, canonical_name, aliases)"
        )
        placeholders = ",".join(["?"] * len(FIELDS))
        connection.executemany(
            f"INSERT INTO foods ({','.join(FIELDS)}) VALUES ({placeholders})",
            ([row.get(field) for field in FIELDS] for row in rows),
        )
        connection.execute(
            """
            INSERT INTO food_search(id, display_name, canonical_name, aliases)
            SELECT id, display_name, canonical_name, COALESCE(aliases, '') FROM foods
            """
        )
        connection.execute("CREATE INDEX foods_canonical_name_idx ON foods(canonical_name)")


def main() -> None:
    args = parse_args()
    rows = load_rows(args.input)
    build_database(rows, args.output)
    print(f"Wrote {len(rows)} foods to {args.output}")


if __name__ == "__main__":
    main()
