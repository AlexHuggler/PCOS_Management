#!/usr/bin/env python3

import argparse
import csv
from decimal import Decimal, InvalidOperation
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
from urllib.parse import urlparse
from urllib.request import Request, urlopen


REPOSITORY_URL = "https://github.com/google-research-datasets/Nutrition5k"
BUCKET_ROOT = "https://storage.googleapis.com/nutrition5k_dataset/nutrition5k_dataset"
STORAGE_HOST = "storage.googleapis.com"
SELECTION_POLICY = "cyclebalance-nutrition5k-depth-test-v1"
RECORD_COUNT = 40
MAX_SOURCE_BYTES = 5_000_000
MAX_IMAGE_BYTES = 5_000_000
MAX_IMAGE_DIMENSION = 12_000
MAX_IMAGE_PIXELS = 50_000_000
DISH_ID_PATTERN = re.compile(r"^dish_[0-9]{10}$")
PINNED_SOURCES = {
    "split": {
        "path": "dish_ids/splits/depth_test_ids.txt",
        "sha256": "6e43a5334a72bd06fa9c0d4b3bc86e2f57e5342b0b260d3fa003a76f7e39eca2",
    },
    "cafe1": {
        "path": "metadata/dish_metadata_cafe1.csv",
        "sha256": "881df31f27c2343d0ce219964527e0796f6ddadd60701ce6840fa801e8c2a960",
    },
    "cafe2": {
        "path": "metadata/dish_metadata_cafe2.csv",
        "sha256": "ef9f800d7b9c2e7e9a9e7cda5cbb4cfe51c760a8c1af4c05786ccf051bf5d77d",
    },
}
NUTRIENT_BOUNDS = {
    "calories": Decimal("10000"),
    "fat": Decimal("1000"),
    "carbs": Decimal("1000"),
    "protein": Decimal("1000"),
}


def fail(message):
    raise ValueError(message)


def verify_digest(data, expected_sha256, label):
    if hashlib.sha256(data).hexdigest().lower() != expected_sha256.lower():
        fail(f"Nutrition5k {label} digest did not match the pinned release")


def fetch_bounded_object(url, maximum_bytes, label):
    parsed = urlparse(url)
    if parsed.scheme != "https" or (parsed.hostname or "").lower() != STORAGE_HOST:
        fail("Nutrition5k source URL is not allowlisted")
    request = Request(url, headers={"User-Agent": "CycleBalance-public-quality-evaluation/1.0"})
    try:
        with urlopen(request, timeout=30) as response:
            final = urlparse(response.geturl())
            if final.scheme != "https" or (final.hostname or "").lower() != STORAGE_HOST:
                fail("Nutrition5k download redirected to an unexpected host")
            content_length = response.headers.get("Content-Length")
            if content_length is not None and int(content_length) > maximum_bytes:
                fail(f"Nutrition5k {label} exceeded its size limit")
            data = response.read(maximum_bytes + 1)
    except ValueError:
        raise
    except Exception:
        raise RuntimeError(f"Nutrition5k {label} request failed") from None
    if len(data) > maximum_bytes:
        fail(f"Nutrition5k {label} exceeded its size limit")
    return data


def fetch_pinned_sources():
    documents = {}
    for name, source in PINNED_SOURCES.items():
        data = fetch_bounded_object(f"{BUCKET_ROOT}/{source['path']}", MAX_SOURCE_BYTES, name)
        verify_digest(data, source["sha256"], name)
        try:
            documents[name] = data.decode("utf-8-sig")
        except UnicodeDecodeError:
            fail(f"Nutrition5k {name} was not valid UTF-8")
    return documents


def bounded_decimal(value, maximum):
    try:
        parsed = Decimal(str(value).strip())
    except (InvalidOperation, TypeError, ValueError):
        return None
    if not parsed.is_finite() or parsed < 0 or parsed > maximum:
        return None
    return parsed


def parse_metadata(documents):
    metadata = {}
    seen_dish_ids = set()
    for source_name in ("cafe1", "cafe2"):
        text = documents.get(source_name)
        if not isinstance(text, str):
            fail("Nutrition5k metadata documents are incomplete")
        for row in csv.reader(io.StringIO(text)):
            if len(row) < 6 or not DISH_ID_PATTERN.fullmatch(row[0]):
                fail("Nutrition5k metadata row is invalid")
            if row[0] in seen_dish_ids:
                fail("Nutrition5k metadata contains a duplicate dish ID")
            seen_dish_ids.add(row[0])
            values = {
                "calories": bounded_decimal(row[1], NUTRIENT_BOUNDS["calories"]),
                "fat": bounded_decimal(row[3], NUTRIENT_BOUNDS["fat"]),
                "carbs": bounded_decimal(row[4], NUTRIENT_BOUNDS["carbs"]),
                "protein": bounded_decimal(row[5], NUTRIENT_BOUNDS["protein"]),
            }
            metadata[row[0]] = None if (
                any(value is None for value in values.values()) or values["calories"] <= 0
            ) else {
                nutrient: round(float(value), 6)
                for nutrient, value in values.items()
            }
    return metadata


def parse_split(text):
    if not isinstance(text, str):
        fail("Nutrition5k split document is missing")
    dish_ids = [line.strip() for line in text.splitlines() if line.strip()]
    if not dish_ids or len(set(dish_ids)) != len(dish_ids) or any(not DISH_ID_PATTERN.fullmatch(item) for item in dish_ids):
        fail("Nutrition5k depth test split is invalid")
    return dish_ids


def select_candidates(documents, count=RECORD_COUNT):
    if not isinstance(documents, dict) or set(documents) != {"split", "cafe1", "cafe2"}:
        fail("Nutrition5k source documents are invalid")
    if count is not None and (not isinstance(count, int) or count < 1):
        fail("Nutrition5k selection count is invalid")
    metadata = parse_metadata(documents)
    candidates = []
    for dish_id in parse_split(documents["split"]):
        if dish_id not in metadata:
            fail("Nutrition5k test dish is missing metadata")
        ground_truth = metadata[dish_id]
        if ground_truth is None:
            continue
        rank = hashlib.sha256(f"{SELECTION_POLICY}:{dish_id}".encode("utf-8")).hexdigest()
        candidates.append({
            "id": "nutrition5k_" + hashlib.sha256(dish_id.encode("utf-8")).hexdigest()[:16],
            "dishId": dish_id,
            "groundTruth": ground_truth,
            "rank": rank,
        })
    ranked = sorted(candidates, key=lambda item: (item["rank"], item["id"]))
    required_count = RECORD_COUNT if count is None else count
    if len(ranked) < required_count:
        fail("Nutrition5k did not contain enough complete depth-test dishes")
    return ranked if count is None else ranked[:count]


def image_url(dish_id):
    if not isinstance(dish_id, str) or not DISH_ID_PATTERN.fullmatch(dish_id):
        fail("Nutrition5k dish ID is invalid")
    return f"{BUCKET_ROOT}/imagery/realsense_overhead/{dish_id}/rgb.png"


def validate_png(data):
    if (
        len(data) < 24
        or not data.startswith(b"\x89PNG\r\n\x1a\n")
        or data[12:16] != b"IHDR"
    ):
        fail("Nutrition5k image was not a valid PNG")
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    if (
        width < 1
        or height < 1
        or width > MAX_IMAGE_DIMENSION
        or height > MAX_IMAGE_DIMENSION
        or width * height > MAX_IMAGE_PIXELS
    ):
        fail("Nutrition5k image dimensions exceeded the evaluation bound")


def fetch_image(dish_id):
    url = image_url(dish_id)
    data = fetch_bounded_object(url, MAX_IMAGE_BYTES, "image")
    validate_png(data)
    return data, url


def write_private_file(path, data):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "wb", closefd=False) as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
    finally:
        os.close(descriptor)
    os.chmod(path, 0o600)


def write_private_json(path, value):
    write_private_file(path, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8"))


def record_from_candidate(candidate, image_path):
    return {
        "id": candidate["id"],
        "source": "Nutrition5k",
        "sourceUrl": REPOSITORY_URL,
        "license": "CC BY 4.0",
        "sourceImagePath": str(image_path.resolve()),
        "groundTruth": candidate["groundTruth"],
        "referenceType": "Nutrition5k weighed dish metadata",
        "samplingReason": "Deterministic official overhead RGB depth-test sample selected before model execution",
        "mealType": "lunch",
        "locale": "en_US",
    }


def acquire_nutrition5k(output_directory, source_fetcher=fetch_pinned_sources, image_fetcher=fetch_image):
    if not Path(output_directory).is_absolute():
        fail("Nutrition5k output directory must be absolute")
    output_directory = Path(output_directory).resolve()
    if output_directory.exists():
        fail("Nutrition5k output directory already exists")

    output_directory.mkdir(mode=0o700)
    image_directory = output_directory / "images"
    image_directory.mkdir(mode=0o700)
    try:
        candidates = select_candidates(source_fetcher(), count=None)
        records = []
        image_provenance = []
        for candidate in candidates:
            if len(records) == RECORD_COUNT:
                break
            try:
                image_bytes, source_url = image_fetcher(candidate["dishId"])
                validate_png(image_bytes)
            except (RuntimeError, ValueError):
                continue
            image_path = image_directory / f"{candidate['id']}.png"
            write_private_file(image_path, image_bytes)
            records.append(record_from_candidate(candidate, image_path))
            image_provenance.append({
                "id": candidate["id"],
                "dishId": candidate["dishId"],
                "sourceUrl": source_url,
                "sha256": hashlib.sha256(image_bytes).hexdigest(),
                "bytes": len(image_bytes),
            })

        if len(records) != RECORD_COUNT:
            fail("Nutrition5k acquisition could not find 40 usable official images")

        write_private_json(output_directory / "source-index-fragment.json", {
            "version": 1,
            "records": records,
        })
        write_private_json(output_directory / "provenance.json", {
            "source": "Nutrition5k",
            "repositoryUrl": REPOSITORY_URL,
            "bucketRoot": BUCKET_ROOT,
            "license": "CC BY 4.0",
            "selectionPolicy": SELECTION_POLICY,
            "recordCount": len(records),
            "sourceDocuments": {
                name: {
                    "url": f"{BUCKET_ROOT}/{source['path']}",
                    "sha256": source["sha256"],
                }
                for name, source in PINNED_SOURCES.items()
            },
            "images": image_provenance,
        })
        return len(records)
    except Exception:
        shutil.rmtree(output_directory, ignore_errors=True)
        raise


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Acquire 40 deterministic Nutrition5k overhead RGB test images without the full archive."
    )
    parser.add_argument("--output-dir", required=True, type=Path)
    arguments = parser.parse_args()
    if not arguments.output_dir.is_absolute():
        parser.error("--output-dir must be absolute")
    return arguments


def main():
    arguments = parse_arguments()
    record_count = acquire_nutrition5k(arguments.output_dir)
    print(f"Prepared {record_count} public Nutrition5k records in {arguments.output_dir}.")


if __name__ == "__main__":
    main()
