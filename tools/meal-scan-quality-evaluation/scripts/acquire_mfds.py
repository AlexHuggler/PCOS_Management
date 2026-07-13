#!/usr/bin/env python3

import argparse
from decimal import Decimal, InvalidOperation
import getpass
import hashlib
import json
import os
from pathlib import Path
import posixpath
import re
import shutil
from urllib.parse import quote, urlparse, urlunparse
from urllib.request import Request, urlopen


SERVICE_ID = "COOKRCP01"
DATASET_URL = "https://www.foodsafetykorea.go.kr/api/newDatasetDetail.do?svc_no=COOKRCP01"
API_HOST = "openapi.foodsafetykorea.go.kr"
IMAGE_HOST = "www.foodsafetykorea.go.kr"
LICENSE_NAME = "Korea Open Government License Type 1 (Attribution)"
SELECTION_POLICY = "cyclebalance-mfds-public-v1"
RECORD_COUNT = 10
PAGE_SIZE = 1_000
MAX_TOTAL_RECORDS = 20_000
MAX_API_RESPONSE_BYTES = 25_000_000
MAX_IMAGE_BYTES = 20_000_000
MAX_IMAGE_DIMENSION = 12_000
MAX_IMAGE_PIXELS = 50_000_000
API_KEY_PATTERN = re.compile(r"^[A-Za-z0-9_-]{8,128}$")
RECIPE_ID_PATTERN = re.compile(r"^[1-9][0-9]{0,11}$")
IMAGE_PATH_PREFIX = "/uploadimg/"
NUTRIENT_FIELDS = {
    "calories": ("INFO_ENG", Decimal("10000")),
    "protein": ("INFO_PRO", Decimal("1000")),
    "carbs": ("INFO_CAR", Decimal("1000")),
    "fat": ("INFO_FAT", Decimal("1000")),
}


def fail(message):
    raise ValueError(message)


def validate_api_key(api_key):
    if not isinstance(api_key, str) or not API_KEY_PATTERN.fullmatch(api_key):
        fail("MFDS API key format is invalid")
    return api_key


def bounded_decimal(value, maximum):
    try:
        parsed = Decimal(str(value).strip())
    except (InvalidOperation, TypeError, ValueError):
        return None
    if not parsed.is_finite() or parsed < 0 or parsed > maximum:
        return None
    return parsed


def normalize_image_url(value):
    if not isinstance(value, str) or not value:
        return None
    parsed = urlparse(value)
    try:
        invalid_authority = (
            (parsed.hostname or "").lower() != IMAGE_HOST
            or parsed.port is not None
            or parsed.username is not None
            or parsed.password is not None
        )
    except ValueError:
        return None
    if (
        parsed.scheme not in {"http", "https"}
        or invalid_authority
        or parsed.query
        or parsed.fragment
        or "\\" in parsed.path
        or "%" in parsed.path
    ):
        return None
    normalized_path = posixpath.normpath(parsed.path)
    if normalized_path != parsed.path or not normalized_path.startswith(IMAGE_PATH_PREFIX):
        return None
    return urlunparse(("https", IMAGE_HOST, normalized_path, "", "", ""))


def jpeg_dimensions(data):
    index = 2
    start_of_frame_markers = {
        0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
        0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF,
    }
    while index + 3 < len(data):
        if data[index] != 0xFF:
            return None
        while index < len(data) and data[index] == 0xFF:
            index += 1
        if index >= len(data):
            return None
        marker = data[index]
        index += 1
        if marker in {0x01, *range(0xD0, 0xD9)}:
            continue
        if marker in {0xD9, 0xDA} or index + 2 > len(data):
            return None
        segment_length = int.from_bytes(data[index:index + 2], "big")
        if segment_length < 2 or index + segment_length > len(data):
            return None
        if marker in start_of_frame_markers:
            if segment_length < 7:
                return None
            height = int.from_bytes(data[index + 3:index + 5], "big")
            width = int.from_bytes(data[index + 5:index + 7], "big")
            return width, height
        index += segment_length
    return None


def validate_image_dimensions(width, height):
    if (
        width < 1
        or height < 1
        or width > MAX_IMAGE_DIMENSION
        or height > MAX_IMAGE_DIMENSION
        or width * height > MAX_IMAGE_PIXELS
    ):
        fail("MFDS image dimensions exceeded the evaluation bound")


def validate_image_payload(data, content_type):
    if content_type in {"image/jpeg", "image/jpg"} and data.startswith(b"\xff\xd8"):
        dimensions = jpeg_dimensions(data)
        extension = ".jpeg"
    elif (
        content_type == "image/png"
        and data.startswith(b"\x89PNG\r\n\x1a\n")
        and len(data) >= 24
        and data[12:16] == b"IHDR"
    ):
        dimensions = (
            int.from_bytes(data[16:20], "big"),
            int.from_bytes(data[20:24], "big"),
        )
        extension = ".png"
    else:
        fail("MFDS image response was not a supported image")
    if dimensions is None:
        fail("MFDS image dimensions could not be validated")
    validate_image_dimensions(*dimensions)
    return extension


def candidate_from_row(row):
    if not isinstance(row, dict):
        return None
    recipe_id = row.get("RCP_SEQ")
    recipe_name = row.get("RCP_NM")
    if (
        not isinstance(recipe_id, str)
        or not RECIPE_ID_PATTERN.fullmatch(recipe_id)
        or not isinstance(recipe_name, str)
        or not recipe_name.strip()
        or len(recipe_name) > 200
        or any(ord(character) < 32 for character in recipe_name)
    ):
        return None

    image_url = normalize_image_url(row.get("ATT_FILE_NO_MAIN"))
    if image_url is None:
        return None

    ground_truth = {}
    for nutrient, (field, maximum) in NUTRIENT_FIELDS.items():
        parsed = bounded_decimal(row.get(field), maximum)
        if parsed is None:
            return None
        ground_truth[nutrient] = round(float(parsed), 6)
    if ground_truth["calories"] <= 0:
        return None

    identifier = "mfds_" + hashlib.sha256(recipe_id.encode("utf-8")).hexdigest()[:16]
    rank = hashlib.sha256(
        f"{SELECTION_POLICY}:{recipe_id}:{image_url}".encode("utf-8")
    ).hexdigest()
    return {
        "id": identifier,
        "recipeId": recipe_id,
        "imageUrl": image_url,
        "groundTruth": ground_truth,
        "rank": rank,
    }


def select_mfds_candidates(rows, count=None):
    if not isinstance(rows, list):
        fail("MFDS response rows are invalid")
    by_identifier = {}
    for row in rows:
        candidate = candidate_from_row(row)
        if candidate is None:
            continue
        existing = by_identifier.get(candidate["id"])
        if existing is None or (candidate["rank"], candidate["imageUrl"]) < (existing["rank"], existing["imageUrl"]):
            by_identifier[candidate["id"]] = candidate

    ranked = sorted(by_identifier.values(), key=lambda item: (item["rank"], item["id"]))
    if count is not None:
        if not isinstance(count, int) or count < 1:
            fail("MFDS selection count is invalid")
        if len(ranked) < count:
            fail("MFDS did not return enough complete recipe records")
        return ranked[:count]
    return ranked


def fetch_json_page(url):
    request = Request(url, headers={"User-Agent": "CycleBalance-public-quality-evaluation/1.0"})
    try:
        with urlopen(request, timeout=45) as response:
            if (urlparse(response.geturl()).hostname or "").lower() != API_HOST:
                fail("MFDS API redirected to an unexpected host")
            data = response.read(MAX_API_RESPONSE_BYTES + 1)
    except ValueError:
        raise
    except Exception:
        raise RuntimeError("MFDS API request failed; the key was not stored or logged") from None
    if len(data) > MAX_API_RESPONSE_BYTES:
        fail("MFDS API response exceeded its size limit")
    try:
        return json.loads(data.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        fail("MFDS API response was not valid JSON")


def parse_recipe_page(document):
    if not isinstance(document, dict):
        fail("MFDS API response shape is invalid")
    payload = document.get(SERVICE_ID)
    if not isinstance(payload, dict):
        fail("MFDS API rejected the credential or request")
    result = payload.get("RESULT")
    if not isinstance(result, dict) or result.get("CODE") != "INFO-000":
        fail("MFDS API rejected the credential or request")
    try:
        total_count = int(payload.get("total_count"))
    except (TypeError, ValueError):
        fail("MFDS API total count is invalid")
    if total_count < RECORD_COUNT or total_count > MAX_TOTAL_RECORDS:
        fail("MFDS API total count is outside the evaluation bound")
    rows = payload.get("row")
    if not isinstance(rows, list):
        fail("MFDS API rows are invalid")
    return total_count, rows


def fetch_mfds_rows(api_key):
    validate_api_key(api_key)
    rows = []
    start = 1
    total_count = None
    while total_count is None or start <= total_count:
        end = start + PAGE_SIZE - 1 if total_count is None else min(start + PAGE_SIZE - 1, total_count)
        key_segment = quote(api_key, safe="")
        url = f"https://{API_HOST}/api/{key_segment}/{SERVICE_ID}/json/{start}/{end}"
        page_total, page_rows = parse_recipe_page(fetch_json_page(url))
        if total_count is None:
            total_count = page_total
        elif page_total != total_count:
            fail("MFDS API total count changed during acquisition")
        if not page_rows:
            fail("MFDS API returned an empty page")
        rows.extend(page_rows)
        start = end + 1
    return rows


def fetch_official_image(url):
    normalized_url = normalize_image_url(url)
    if normalized_url is None:
        fail("MFDS image URL is not allowlisted")
    request = Request(normalized_url, headers={"User-Agent": "CycleBalance-public-quality-evaluation/1.0"})
    try:
        with urlopen(request, timeout=30) as response:
            final_url = normalize_image_url(response.geturl())
            if final_url is None:
                fail("MFDS image redirected to an unexpected location")
            content_length = response.headers.get("Content-Length")
            if content_length is not None and int(content_length) > MAX_IMAGE_BYTES:
                fail("MFDS image exceeded its size limit")
            content_type = response.headers.get_content_type().lower()
            data = response.read(MAX_IMAGE_BYTES + 1)
    except ValueError:
        raise
    except Exception:
        raise RuntimeError("MFDS image request failed") from None
    if len(data) > MAX_IMAGE_BYTES:
        fail("MFDS image exceeded its size limit")
    return data, validate_image_payload(data, content_type)


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
        "source": "MFDS",
        "sourceUrl": DATASET_URL,
        "license": LICENSE_NAME,
        "sourceImagePath": str(image_path.resolve()),
        "groundTruth": candidate["groundTruth"],
        "referenceType": "MFDS published recipe nutrition record",
        "samplingReason": "Deterministic public Korean recipe sample selected before model execution",
        "mealType": "lunch",
        "locale": "ko_KR",
    }


def acquire_mfds(output_directory, api_key, row_fetcher=fetch_mfds_rows, image_fetcher=fetch_official_image):
    if not Path(output_directory).is_absolute():
        fail("MFDS output directory must be absolute")
    output_directory = Path(output_directory).resolve()
    if output_directory.exists():
        fail("MFDS output directory already exists")
    validate_api_key(api_key)

    output_directory.mkdir(mode=0o700)
    image_directory = output_directory / "images"
    image_directory.mkdir(mode=0o700)
    try:
        candidates = select_mfds_candidates(row_fetcher(api_key))
        records = []
        recipe_ids = []
        for candidate in candidates:
            if len(records) == RECORD_COUNT:
                break
            try:
                image_bytes, extension = image_fetcher(candidate["imageUrl"])
            except (RuntimeError, ValueError):
                continue
            if extension not in {".jpeg", ".png"}:
                continue
            image_path = image_directory / f"{candidate['id']}{extension}"
            write_private_file(image_path, image_bytes)
            records.append(record_from_candidate(candidate, image_path))
            recipe_ids.append(candidate["recipeId"])

        if len(records) != RECORD_COUNT:
            fail("MFDS acquisition could not find ten usable official recipe images")

        write_private_json(output_directory / "source-index-fragment.json", {
            "version": 1,
            "records": records,
        })
        write_private_json(output_directory / "provenance.json", {
            "source": "MFDS",
            "serviceId": SERVICE_ID,
            "datasetUrl": DATASET_URL,
            "apiEndpointTemplate": f"https://{API_HOST}/api/{{key}}/{SERVICE_ID}/json/{{start}}/{{end}}",
            "imageHost": IMAGE_HOST,
            "license": LICENSE_NAME,
            "licenseUrl": DATASET_URL,
            "selectionPolicy": SELECTION_POLICY,
            "recordCount": len(records),
            "recipeIds": recipe_ids,
        })
        return len(records)
    except Exception:
        shutil.rmtree(output_directory, ignore_errors=True)
        raise


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Acquire ten deterministic public MFDS recipe records without persisting the API key."
    )
    parser.add_argument("--output-dir", required=True, type=Path)
    arguments = parser.parse_args()
    if not arguments.output_dir.is_absolute():
        parser.error("--output-dir must be absolute")
    return arguments


def main():
    arguments = parse_arguments()
    api_key = getpass.getpass("MFDS API key (input hidden; never saved): ")
    try:
        record_count = acquire_mfds(arguments.output_dir, api_key)
    finally:
        api_key = None
    print(f"Prepared {record_count} public MFDS records in {arguments.output_dir}.")


if __name__ == "__main__":
    main()
