import importlib.util
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "acquire_mfds.py"
SPEC = importlib.util.spec_from_file_location("acquire_mfds", SCRIPT_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def recipe_row(index, image_url=None):
    return {
        "RCP_SEQ": str(1000 + index),
        "RCP_NM": f"Public recipe {index}",
        "RCP_PAT2": "일품",
        "INFO_ENG": str(300 + index),
        "INFO_PRO": "20",
        "INFO_CAR": "35",
        "INFO_FAT": "10",
        "ATT_FILE_NO_MAIN": image_url
        or f"http://www.foodsafetykorea.go.kr/uploadimg/cook/10_{1000 + index}_2.png",
    }


def png_bytes(width=640, height=480):
    return b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + struct.pack(">II", width, height) + b"\x08\x02\x00\x00\x00"


class MfdsAcquisitionTests(unittest.TestCase):
    def test_ranks_only_complete_records_deterministically(self):
        rows = [recipe_row(index) for index in range(14)]
        rows.append(recipe_row(90, "https://example.com/not-allowed.png"))
        invalid_nutrition = recipe_row(91)
        invalid_nutrition["INFO_ENG"] = "not-a-number"
        rows.append(invalid_nutrition)

        selected = MODULE.select_mfds_candidates(rows, count=10)
        reversed_selected = MODULE.select_mfds_candidates(list(reversed(rows)), count=10)

        self.assertEqual([item["id"] for item in selected], [item["id"] for item in reversed_selected])
        self.assertEqual(len(selected), 10)
        self.assertTrue(all(item["imageUrl"].startswith("https://www.foodsafetykorea.go.kr/uploadimg/") for item in selected))
        self.assertTrue(all(item["groundTruth"] == {
            "calories": float(300 + int(item["recipeId"]) - 1000),
            "protein": 20.0,
            "carbs": 35.0,
            "fat": 10.0,
        } for item in selected))

    def test_acquire_writes_owner_only_outputs_without_persisting_key(self):
        secret = "PRIVATEKEY-1234567890"
        rows = [recipe_row(index) for index in range(12)]
        seen_keys = []

        def row_fetcher(api_key):
            seen_keys.append(api_key)
            return rows

        def image_fetcher(url):
            self.assertTrue(url.startswith("https://www.foodsafetykorea.go.kr/uploadimg/"))
            return png_bytes(), ".png"

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "mfds"
            count = MODULE.acquire_mfds(
                output,
                secret,
                row_fetcher=row_fetcher,
                image_fetcher=image_fetcher,
            )

            fragment = json.loads((output / "source-index-fragment.json").read_text())
            provenance = json.loads((output / "provenance.json").read_text())
            serialized = "\n".join(path.read_text(errors="ignore") for path in output.rglob("*") if path.is_file())

            self.assertEqual(count, 10)
            self.assertEqual(seen_keys, [secret])
            self.assertEqual(len(fragment["records"]), 10)
            self.assertEqual(provenance["recordCount"], 10)
            self.assertTrue(all(record["license"] == "Korea Open Government License Type 1 (Attribution)" for record in fragment["records"]))
            self.assertEqual(provenance["licenseUrl"], MODULE.DATASET_URL)
            self.assertNotIn(secret, serialized)
            self.assertEqual(os.stat(output).st_mode & 0o777, 0o700)
            self.assertTrue(all((os.stat(path).st_mode & 0o777) == 0o600 for path in output.rglob("*") if path.is_file()))
            self.assertTrue(all(Path(record["sourceImagePath"]).is_file() for record in fragment["records"]))

    def test_acquire_cleans_partial_output_after_download_failure(self):
        rows = [recipe_row(index) for index in range(12)]

        def fail_download(_url):
            raise ValueError("image unavailable")

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "mfds"
            with self.assertRaisesRegex(ValueError, "ten usable"):
                MODULE.acquire_mfds(
                    output,
                    "PRIVATEKEY-1234567890",
                    row_fetcher=lambda _key: rows,
                    image_fetcher=fail_download,
                )
            self.assertFalse(output.exists())

    def test_rejects_keys_that_could_escape_the_api_path(self):
        for key in ["", "short", "abc/def12345", "abc?def12345", "abc def12345"]:
            with self.subTest(key=key):
                with self.assertRaisesRegex(ValueError, "key format"):
                    MODULE.validate_api_key(key)

    def test_rejects_oversized_images_and_encoded_path_traversal(self):
        self.assertIsNone(MODULE.normalize_image_url(
            "https://www.foodsafetykorea.go.kr/uploadimg/%2e%2e/private.png"
        ))
        with self.assertRaisesRegex(ValueError, "dimensions"):
            MODULE.validate_image_payload(png_bytes(width=20_000, height=20_000), "image/png")


if __name__ == "__main__":
    unittest.main()
