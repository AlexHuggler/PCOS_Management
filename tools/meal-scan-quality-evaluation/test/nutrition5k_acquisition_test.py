import importlib.util
import json
import os
from pathlib import Path
import struct
import tempfile
import unittest


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "acquire_nutrition5k.py"
SPEC = importlib.util.spec_from_file_location("acquire_nutrition5k", SCRIPT_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def source_documents(count=45):
    dish_ids = [f"dish_{1_550_000_000 + index}" for index in range(count)]
    split = "\n".join(reversed(dish_ids)) + "\n"
    midpoint = count // 2

    def row(index):
        dish_id = dish_ids[index]
        return f"{dish_id},{400 + index},250,{10 + index / 10},{40 + index / 10},{20 + index / 10},ingr_0000000001,test ingredient,250,{400 + index},{10 + index / 10},{40 + index / 10},{20 + index / 10}"

    return {
        "split": split,
        "cafe1": "\n".join(row(index) for index in range(midpoint)) + "\n",
        "cafe2": "\n".join(row(index) for index in range(midpoint, count)) + "\n",
    }


def png_bytes(width=640, height=480):
    return b"\x89PNG\r\n\x1a\n" + b"\x00\x00\x00\rIHDR" + struct.pack(">II", width, height) + b"\x08\x02\x00\x00\x00"


class Nutrition5kAcquisitionTests(unittest.TestCase):
    def test_selects_40_depth_test_records_deterministically_with_correct_macro_order(self):
        documents = source_documents()
        selected = MODULE.select_candidates(documents, count=40)
        reordered = dict(documents)
        reordered["split"] = "\n".join(reversed(documents["split"].splitlines())) + "\n"
        reversed_selected = MODULE.select_candidates(reordered, count=40)

        self.assertEqual([item["id"] for item in selected], [item["id"] for item in reversed_selected])
        self.assertEqual(len(selected), 40)
        for item in selected:
            index = int(item["dishId"].removeprefix("dish_")) - 1_550_000_000
            self.assertEqual(item["groundTruth"], {
                "calories": float(400 + index),
                "protein": float(20 + index / 10),
                "carbs": float(40 + index / 10),
                "fat": float(10 + index / 10),
            })

    def test_acquire_writes_owner_only_fragment_and_image_hash_provenance(self):
        documents = source_documents()

        def image_fetcher(dish_id):
            return png_bytes(), MODULE.image_url(dish_id)

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "nutrition5k"
            count = MODULE.acquire_nutrition5k(
                output,
                source_fetcher=lambda: documents,
                image_fetcher=image_fetcher,
            )

            fragment = json.loads((output / "source-index-fragment.json").read_text())
            provenance = json.loads((output / "provenance.json").read_text())

            self.assertEqual(count, 40)
            self.assertEqual(len(fragment["records"]), 40)
            self.assertEqual(len(provenance["images"]), 40)
            self.assertTrue(all(record["license"] == "CC BY 4.0" for record in fragment["records"]))
            self.assertTrue(all(len(item["sha256"]) == 64 for item in provenance["images"]))
            self.assertEqual(os.stat(output).st_mode & 0o777, 0o700)
            self.assertTrue(all((os.stat(path).st_mode & 0o777) == 0o600 for path in output.rglob("*") if path.is_file()))

    def test_rejects_pinned_source_digest_mismatch(self):
        with self.assertRaisesRegex(ValueError, "digest"):
            MODULE.verify_digest(b"changed", "0" * 64, "test split")

    def test_excludes_zero_nutrition_depth_test_record(self):
        documents = source_documents()
        invalid_dish = "dish_1666666666"
        documents["split"] += invalid_dish + "\n"
        documents["cafe1"] += f"{invalid_dish},0,0,0,0,0\n"

        selected = MODULE.select_candidates(documents, count=40)

        self.assertEqual(len(selected), 40)
        self.assertNotIn(invalid_dish, [item["dishId"] for item in selected])

    def test_acquire_falls_through_one_unusable_ranked_image(self):
        calls = 0

        def image_fetcher(dish_id):
            nonlocal calls
            calls += 1
            if calls == 1:
                raise ValueError("unavailable")
            return png_bytes(), MODULE.image_url(dish_id)

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "nutrition5k"
            count = MODULE.acquire_nutrition5k(
                output,
                source_fetcher=source_documents,
                image_fetcher=image_fetcher,
            )

        self.assertEqual(count, 40)
        self.assertEqual(calls, 41)

    def test_acquire_removes_partial_output_when_images_are_unavailable(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "nutrition5k"
            with self.assertRaisesRegex(ValueError, "40 usable"):
                MODULE.acquire_nutrition5k(
                    output,
                    source_fetcher=source_documents,
                    image_fetcher=lambda _dish_id: (_ for _ in ()).throw(ValueError("unavailable")),
                )
            self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
