import csv
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "acquire_snapme.py"
SPEC = importlib.util.spec_from_file_location("acquire_snapme", SCRIPT_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def linkage_csv():
    output = io.StringIO()
    fields = ["subject_id", "filename", "packaged_food", "Occ_Name", "KCAL", "PROT", "TFAT", "CARB"]
    writer = csv.DictWriter(output, fieldnames=fields)
    writer.writeheader()
    meal_codes = ["1", "3", "4", "6"]
    for index, code in enumerate(meal_codes):
        filename = f"meal{index:020d}.jpeg"
        writer.writerow({
            "subject_id": f"PRIVATE-{index}",
            "filename": filename,
            "packaged_food": "0",
            "Occ_Name": code,
            "KCAL": "100",
            "PROT": "5",
            "TFAT": "3",
            "CARB": "10",
        })
        writer.writerow({
            "subject_id": f"PRIVATE-{index}",
            "filename": filename,
            "packaged_food": "0",
            "Occ_Name": code,
            "KCAL": "50",
            "PROT": "2",
            "TFAT": "1",
            "CARB": "4",
        })
    return output.getvalue()


def synthetic_archive():
    output = io.BytesIO()
    jpeg = b"\xff\xd8public-meal\xff\xd9"
    root = "snapme_db_09Dec2022"
    filename = "meal00000000000000000000.jpeg"
    target = f"{root}/snapme_nut_db/9001_QC/day1/{filename}"
    with tarfile.open(fileobj=output, mode="w:gz") as archive:
        link = tarfile.TarInfo(f"{root}/snapme_cs_db/before_photos/{filename}")
        link.type = tarfile.SYMTYPE
        link.linkname = f"../../snapme_nut_db/9001_QC/day1/{filename}"
        archive.addfile(link)

        unrelated = tarfile.TarInfo(f"{root}/snapme_nut_db/9001_QC/day1/unrelated.jpeg")
        unrelated_bytes = b"\xff\xd8ignore\xff\xd9"
        unrelated.size = len(unrelated_bytes)
        archive.addfile(unrelated, io.BytesIO(unrelated_bytes))

        image = tarfile.TarInfo(target)
        image.size = len(jpeg)
        archive.addfile(image, io.BytesIO(jpeg))
    return output.getvalue(), filename, jpeg


class SnapmeAcquisitionTests(unittest.TestCase):
    def test_builds_balanced_aggregate_records_without_participant_identifiers(self):
        with tempfile.TemporaryDirectory() as directory:
            records = MODULE.select_snapme_records(
                linkage_csv(),
                image_directory=Path(directory),
                quotas={"breakfast": 1, "lunch": 1, "dinner": 1, "snack": 1},
            )

        self.assertEqual([record["mealType"] for record in records], ["breakfast", "dinner", "lunch", "snack"])
        self.assertTrue(all(record["groundTruth"] == {
            "calories": 150.0,
            "protein": 7.0,
            "carbs": 14.0,
            "fat": 4.0,
        } for record in records))
        self.assertNotIn("PRIVATE", json.dumps(records))
        self.assertEqual(len({record["id"] for record in records}), 4)

    def test_skips_official_unlinked_filename_sentinels(self):
        linkage = linkage_csv() + "PRIVATE-MISSING,NA ,0,1,100,5,3,10\r\n"
        with tempfile.TemporaryDirectory() as directory:
            records = MODULE.select_snapme_records(
                linkage,
                image_directory=Path(directory),
                quotas={"breakfast": 1, "lunch": 1, "dinner": 1, "snack": 1},
            )

        self.assertEqual(len(records), 4)

    def test_skips_official_missing_meal_occasion_sentinel(self):
        linkage = linkage_csv() + "PRIVATE-MISSING,meal99999999999999999999.jpeg,0,NA,100,5,3,10\r\n"
        with tempfile.TemporaryDirectory() as directory:
            records = MODULE.select_snapme_records(
                linkage,
                image_directory=Path(directory),
                quotas={"breakfast": 1, "lunch": 1, "dinner": 1, "snack": 1},
            )

        self.assertEqual(len(records), 4)

    def test_excludes_images_with_conflicting_meal_occasions(self):
        conflict = "meal88888888888888888888.jpeg"
        linkage = linkage_csv()
        linkage += f"PRIVATE-CONFLICT,{conflict},0,1,100,5,3,10\r\n"
        linkage += f"PRIVATE-CONFLICT,{conflict},0,3,100,5,3,10\r\n"
        with tempfile.TemporaryDirectory() as directory:
            records = MODULE.select_snapme_records(
                linkage,
                image_directory=Path(directory),
                quotas={"breakfast": 1, "lunch": 1, "dinner": 1, "snack": 1},
            )

        self.assertEqual(len(records), 4)
        self.assertNotIn(conflict, json.dumps(records))

    def test_streams_only_selected_regular_image_and_verifies_archive_digest(self):
        archive_bytes, filename, jpeg = synthetic_archive()
        with tempfile.TemporaryDirectory() as directory:
            output_path = Path(directory) / "selected.jpeg"
            MODULE.extract_selected_images(
                io.BytesIO(archive_bytes),
                selected_paths={filename: output_path},
                expected_size=len(archive_bytes),
                expected_md5=hashlib.md5(archive_bytes).hexdigest(),
            )

            self.assertEqual(output_path.read_bytes(), jpeg)
            self.assertEqual(os.stat(output_path).st_mode & 0o777, 0o600)
            self.assertEqual(list(Path(directory).iterdir()), [output_path])

    def test_rejects_archive_digest_mismatch(self):
        archive_bytes, filename, _ = synthetic_archive()
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(ValueError, "digest"):
                MODULE.extract_selected_images(
                    io.BytesIO(archive_bytes),
                    selected_paths={filename: Path(directory) / "selected.jpeg"},
                    expected_size=len(archive_bytes),
                    expected_md5="0" * 32,
                )


if __name__ == "__main__":
    unittest.main()
