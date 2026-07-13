#!/usr/bin/env python3

import argparse
import csv
from decimal import Decimal, InvalidOperation
import hashlib
import io
import json
import os
from pathlib import Path
import posixpath
import re
import shutil
import tarfile
from urllib.parse import urlparse
from urllib.request import Request, urlopen


ARTICLE_URL = "https://agdatacommons.nal.usda.gov/articles/dataset/SNAPMe_A_Benchmark_Dataset_of_Food_Photos_with_Food_Records_for_Evaluation_of_Computer_Vision_Algorithms_in_the_Context_of_Dietary_Assessment/24856449"
ARCHIVE_URL = "https://ndownloader.figshare.com/files/44532971"
ARCHIVE_SIZE = 2_034_227_035
ARCHIVE_MD5 = "95383fd42b78eb45adbad03c7673e8f7"
LINKAGE_URL = "https://raw.githubusercontent.com/JulesLarke-USDA/SNAPMe/main/input/master_SNAPME_linkfile.csv"
LICENSE_URL = "https://raw.githubusercontent.com/JulesLarke-USDA/SNAPMe/main/LICENSE.txt"
DEFAULT_QUOTAS = {"breakfast": 7, "lunch": 8, "dinner": 8, "snack": 7}
MAX_LINKAGE_BYTES = 5_000_000
MAX_SELECTED_IMAGE_BYTES = 20_000_000
ARCHIVE_ROOT = "snapme_db_09Dec2022"
BEFORE_LINK_PREFIX = f"{ARCHIVE_ROOT}/snapme_cs_db/before_photos/"
NUTRITION_IMAGE_PREFIX = f"{ARCHIVE_ROOT}/snapme_nut_db/"
FILENAME_PATTERN = re.compile(r"^[A-Za-z0-9]{20,64}\.jpeg$")
REQUIRED_COLUMNS = {
    "filename",
    "packaged_food",
    "Occ_Name",
    "KCAL",
    "PROT",
    "TFAT",
    "CARB",
}
MEAL_TYPE_BY_OCCASION = {
    "1": "breakfast",
    "2": "breakfast",
    "3": "lunch",
    "4": "dinner",
    "5": "dinner",
    "6": "snack",
    "7": "snack",
    "8": "snack",
}


def fail(message):
    raise ValueError(message)


def decimal_value(value, field):
    try:
        parsed = Decimal(value)
    except (InvalidOperation, TypeError):
        fail(f"SNAPMe linkage contains an invalid {field} value")
    if not parsed.is_finite() or parsed < 0:
        fail(f"SNAPMe linkage contains an invalid {field} value")
    return parsed


def select_snapme_groups(linkage_text, quotas):
    reader = csv.DictReader(io.StringIO(linkage_text))
    if not REQUIRED_COLUMNS.issubset(set(reader.fieldnames or [])):
        fail("SNAPMe linkage columns are incomplete")

    groups = {}
    for row in reader:
        if row["packaged_food"] != "0":
            continue
        filename = row["filename"]
        if (filename or "").strip() in {"", "NA"}:
            continue
        if not FILENAME_PATTERN.fullmatch(filename or ""):
            fail("SNAPMe linkage contains an invalid image filename")
        occasion = (row["Occ_Name"] or "").strip()
        if occasion in {"", "NA"}:
            continue
        meal_type = MEAL_TYPE_BY_OCCASION.get(occasion)
        if meal_type is None:
            fail("SNAPMe linkage contains an unsupported meal occasion")

        group = groups.setdefault(filename, {
            "filename": filename,
            "mealTypes": set(),
            "calories": Decimal(0),
            "protein": Decimal(0),
            "carbs": Decimal(0),
            "fat": Decimal(0),
        })
        group["mealTypes"].add(meal_type)
        group["calories"] += decimal_value(row["KCAL"], "KCAL")
        group["protein"] += decimal_value(row["PROT"], "PROT")
        group["carbs"] += decimal_value(row["CARB"], "CARB")
        group["fat"] += decimal_value(row["TFAT"], "TFAT")

    buckets = {meal_type: [] for meal_type in quotas}
    for group in groups.values():
        if len(group["mealTypes"]) != 1:
            continue
        meal_type = next(iter(group["mealTypes"]))
        if meal_type in buckets:
            group["mealType"] = meal_type
            group["rank"] = hashlib.sha256(
                f"cyclebalance-snapme-public-v1:{group['filename']}".encode("utf-8")
            ).hexdigest()
            buckets[meal_type].append(group)

    selected = []
    for meal_type, quota in quotas.items():
        if not isinstance(quota, int) or quota < 0:
            fail("SNAPMe meal quotas must be non-negative integers")
        ranked = sorted(buckets.get(meal_type, []), key=lambda group: (group["rank"], group["filename"]))
        if len(ranked) < quota:
            fail(f"SNAPMe does not contain enough {meal_type} images")
        selected.extend(ranked[:quota])
    return sorted(selected, key=lambda group: (group["mealType"], group["rank"]))


def record_from_group(group, image_directory):
    identifier = "snapme_" + hashlib.sha256(group["filename"].encode("utf-8")).hexdigest()[:16]
    return {
        "id": identifier,
        "source": "SNAPMe",
        "sourceUrl": ARTICLE_URL,
        "license": "CC BY-SA 4.0",
        "sourceImagePath": str((image_directory / f"{identifier}.jpeg").resolve()),
        "groundTruth": {
            "calories": round(float(group["calories"]), 6),
            "protein": round(float(group["protein"]), 6),
            "carbs": round(float(group["carbs"]), 6),
            "fat": round(float(group["fat"]), 6),
        },
        "referenceType": "SNAPMe ASA24 linked food-record aggregate",
        "samplingReason": "Deterministic balanced public meal-photo sample selected before model execution",
        "mealType": group["mealType"],
        "locale": "en_US",
    }


def select_snapme_records(linkage_text, image_directory, quotas=None):
    quotas = dict(DEFAULT_QUOTAS if quotas is None else quotas)
    groups = select_snapme_groups(linkage_text, quotas)
    return [record_from_group(group, image_directory) for group in groups]


class HashingBoundedReader:
    def __init__(self, stream, maximum_bytes):
        self.stream = stream
        self.maximum_bytes = maximum_bytes
        self.bytes_read = 0
        self.md5 = hashlib.md5()

    def read(self, size=-1):
        data = self.stream.read(size)
        self.bytes_read += len(data)
        if self.bytes_read > self.maximum_bytes:
            fail("SNAPMe archive exceeded its pinned size")
        self.md5.update(data)
        return data


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


def extract_selected_images(archive_stream, selected_paths, expected_size, expected_md5):
    if not selected_paths or any(not Path(path).is_absolute() for path in selected_paths.values()):
        fail("selected SNAPMe output paths must be absolute")
    if len(set(map(str, selected_paths.values()))) != len(selected_paths):
        fail("selected SNAPMe output paths must be unique")

    reader = HashingBoundedReader(archive_stream, expected_size)
    target_to_filename = {}
    extracted = set()
    written_paths = []
    try:
        with tarfile.open(fileobj=reader, mode="r|gz") as archive:
            for member in archive:
                member_name = posixpath.normpath(member.name)
                if member.issym() and member_name.startswith(BEFORE_LINK_PREFIX):
                    filename = posixpath.basename(member_name)
                    if filename not in selected_paths:
                        continue
                    target = posixpath.normpath(
                        posixpath.join(posixpath.dirname(member_name), member.linkname)
                    )
                    if not target.startswith(NUTRITION_IMAGE_PREFIX):
                        fail("selected SNAPMe link escapes the nutrition image directory")
                    if target in target_to_filename:
                        fail("selected SNAPMe image has duplicate archive links")
                    target_to_filename[target] = filename
                    continue

                filename = target_to_filename.get(member_name)
                if filename is None:
                    continue
                if not member.isfile() or member.size < 4 or member.size > MAX_SELECTED_IMAGE_BYTES:
                    fail("selected SNAPMe archive member is not a bounded regular image")
                source = archive.extractfile(member)
                if source is None:
                    fail("selected SNAPMe image could not be read")
                image_bytes = source.read(MAX_SELECTED_IMAGE_BYTES + 1)
                if len(image_bytes) != member.size or not image_bytes.startswith(b"\xff\xd8"):
                    fail("selected SNAPMe image is not a valid bounded JPEG")
                output_path = Path(selected_paths[filename])
                write_private_file(output_path, image_bytes)
                written_paths.append(output_path)
                extracted.add(filename)

        while reader.read(1024 * 1024):
            pass
        if reader.bytes_read != expected_size:
            fail("SNAPMe archive size did not match the pinned release")
        if reader.md5.hexdigest().lower() != expected_md5.lower():
            fail("SNAPMe archive digest did not match the pinned release")
        if set(selected_paths) != extracted:
            fail("SNAPMe archive did not contain every selected meal image")
    except Exception:
        for path in written_paths:
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        raise


def fetch_bounded_text(url, maximum_bytes):
    request = Request(url, headers={"User-Agent": "CycleBalance-public-quality-evaluation/1.0"})
    with urlopen(request, timeout=30) as response:
        data = response.read(maximum_bytes + 1)
    if len(data) > maximum_bytes:
        fail("public SNAPMe metadata exceeded its size limit")
    return data.decode("utf-8-sig")


def write_private_json(path, value):
    write_private_file(path, (json.dumps(value, indent=2, sort_keys=True) + "\n").encode("utf-8"))


def acquire_snapme(output_directory):
    output_directory = output_directory.resolve()
    if not output_directory.is_absolute():
        fail("SNAPMe output directory must be absolute")
    if output_directory.exists():
        fail("SNAPMe output directory already exists")

    output_directory.mkdir(mode=0o700)
    image_directory = output_directory / "images"
    image_directory.mkdir(mode=0o700)
    try:
        linkage_text = fetch_bounded_text(LINKAGE_URL, MAX_LINKAGE_BYTES)
        groups = select_snapme_groups(linkage_text, DEFAULT_QUOTAS)
        records = [record_from_group(group, image_directory) for group in groups]
        selected_paths = {
            group["filename"]: Path(record["sourceImagePath"])
            for group, record in zip(groups, records)
        }

        request = Request(ARCHIVE_URL, headers={"User-Agent": "CycleBalance-public-quality-evaluation/1.0"})
        with urlopen(request, timeout=60) as response:
            host = (urlparse(response.geturl()).hostname or "").lower()
            if not (host == "ndownloader.figshare.com" or host.endswith(".amazonaws.com")):
                fail("SNAPMe download redirected to an unexpected host")
            extract_selected_images(
                response,
                selected_paths=selected_paths,
                expected_size=ARCHIVE_SIZE,
                expected_md5=ARCHIVE_MD5,
            )

        write_private_json(output_directory / "source-index-fragment.json", {
            "version": 1,
            "records": records,
        })
        write_private_json(output_directory / "provenance.json", {
            "source": "SNAPMe",
            "articleUrl": ARTICLE_URL,
            "linkageUrl": LINKAGE_URL,
            "license": "CC BY-SA 4.0",
            "licenseUrl": LICENSE_URL,
            "archive": {
                "fileId": 44532971,
                "name": "snapme_db_09Dec2022.tar.gz",
                "size": ARCHIVE_SIZE,
                "md5": ARCHIVE_MD5,
            },
            "selectionPolicy": "cyclebalance-snapme-public-v1",
            "recordCount": len(records),
        })
        return len(records)
    except Exception:
        shutil.rmtree(output_directory, ignore_errors=True)
        raise


def parse_arguments():
    parser = argparse.ArgumentParser(
        description="Stream and verify the official SNAPMe archive while retaining only 30 selected meal images."
    )
    parser.add_argument("--output-dir", required=True, type=Path)
    arguments = parser.parse_args()
    if not arguments.output_dir.is_absolute():
        parser.error("--output-dir must be absolute")
    return arguments


def main():
    arguments = parse_arguments()
    record_count = acquire_snapme(arguments.output_dir)
    print(f"Prepared {record_count} public SNAPMe records in {arguments.output_dir}.")


if __name__ == "__main__":
    main()
