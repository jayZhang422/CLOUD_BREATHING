"""Generate a 2.5D INT8 BIN directly from a source DICOM directory or ZIP."""

import argparse
import json
from pathlib import Path

from .dicom_ct import load_ct_series
from .preprocess import write_int8_input


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, required=True, help="Read-only DICOM directory or CT ZIP")
    parser.add_argument("--output-dir", type=Path, required=True, help="Directory for derived BIN and metadata")
    parser.add_argument("--series-uid")
    args = parser.parse_args()
    volume, metadata = load_ct_series(args.data_dir, args.series_uid)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    metadata["model_input"] = write_int8_input(
        volume, args.output_dir / "input_int8.bin", -1024.0, 1000.0
    )
    (args.output_dir / "metadata.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"BIN: {args.output_dir / 'input_int8.bin'}")
    print(f"Shape: {metadata['model_input']['shape']}, spacing: {metadata['spacing_z_y_x_mm']} mm")


if __name__ == "__main__":
    main()
